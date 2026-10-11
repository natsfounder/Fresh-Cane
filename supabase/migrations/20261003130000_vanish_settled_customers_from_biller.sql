-- =============================================================================
-- Migration: 20261003130000_vanish_settled_customers_from_biller.sql
-- Description:
--   1. Update settle_bill:
--      - When a bill is settled, unconditionally mark ALL orders for that
--        session customer as 'completed' and any unpaid bills as 'paid'.
--      - Unconditionally update table_session_customers.status = 'billed'.
--      - If no unbilled orders remain in the session, update table_sessions to 'billing'.
--   2. Update get_active_table_session_details:
--      - Exclude customers whose status is 'billed' or 'closed' (AND sc.status NOT IN ('billed', 'closed')).
--      - Settled customers vanish immediately from table session details.
--   3. Grant execute permissions to authenticated users.
-- =============================================================================

-- 1. Settle Bill RPC: robust settlement and customer status transition
CREATE OR REPLACE FUNCTION public.settle_bill(
    p_bill_id UUID,
    p_payments JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_assigned_roles TEXT[];
    v_bill RECORD;
    v_order RECORD;
    v_payment_record JSONB;
    v_method VARCHAR(20);
    v_amount NUMERIC(10,2);
    v_cash_tendered NUMERIC(10,2);
    v_change_returned NUMERIC(10,2);
    v_tx_ref VARCHAR(100);
    v_total_paid NUMERIC(10,2) := 0;
    v_payment_ids UUID[] := '{}';
    v_payment_id UUID;
BEGIN
    -- 1. Authorization: cashier or super_admin (including assigned_roles)
    SELECT role, assigned_roles INTO v_role, v_assigned_roles
    FROM public.user_profiles 
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR (
        v_role NOT IN ('cashier', 'super_admin') 
        AND NOT ('cashier' = ANY(v_assigned_roles) OR 'super_admin' = ANY(v_assigned_roles))
    ) THEN
        RAISE EXCEPTION 'Unauthorized: only cashier or super_admin can settle bills';
    END IF;

    -- 2. Lock bill
    SELECT * INTO v_bill FROM public.bills WHERE id = p_bill_id FOR UPDATE;
    IF v_bill IS NULL THEN
        RAISE EXCEPTION 'Bill not found';
    END IF;

    -- 3. Verify bill is unpaid (idempotency guard)
    IF v_bill.status <> 'unpaid' THEN
        RAISE EXCEPTION 'Bill is not unpaid (status: %). Settlement rejected.', v_bill.status;
    END IF;

    -- 4. Lock parent order
    SELECT * INTO v_order FROM public.orders WHERE id = v_bill.order_id FOR UPDATE;
    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Parent order not found';
    END IF;

    -- 5. Verify order is not cancelled
    IF v_order.status = 'cancelled' THEN
        RAISE EXCEPTION 'Parent order is cancelled. Settlement rejected.';
    END IF;

    -- 6. Validate payment array
    IF p_payments IS NULL OR jsonb_array_length(p_payments) = 0 THEN
        RAISE EXCEPTION 'At least one payment entry is required';
    END IF;

    -- 7. Validate and sum payment entries
    FOR v_payment_record IN SELECT * FROM jsonb_array_elements(p_payments)
    LOOP
        v_method := v_payment_record->>'method';
        v_amount := (v_payment_record->>'amount')::numeric;
        v_cash_tendered := (v_payment_record->>'cash_tendered')::numeric;
        v_tx_ref := v_payment_record->>'transaction_reference';

        IF v_method IS NULL OR v_method NOT IN ('cash', 'upi', 'card') THEN
            RAISE EXCEPTION 'Invalid payment method: %. Must be cash, upi, or card', v_method;
        END IF;

        IF v_amount IS NULL OR v_amount <= 0 THEN
            RAISE EXCEPTION 'Payment amount must be greater than zero';
        END IF;

        IF v_method = 'cash' THEN
            IF v_cash_tendered IS NOT NULL AND v_cash_tendered < v_amount THEN
                RAISE EXCEPTION 'Cash tendered (₹%) cannot be less than payment amount (₹%)',
                    v_cash_tendered, v_amount;
            END IF;
            IF v_cash_tendered IS NOT NULL THEN
                v_change_returned := v_cash_tendered - v_amount;
            ELSE
                v_change_returned := 0;
            END IF;
        ELSE
            v_cash_tendered := NULL;
            v_change_returned := NULL;
        END IF;

        v_total_paid := v_total_paid + v_amount;

        -- Record individual payment
        INSERT INTO public.payments (
            id, bill_id, payment_method, amount, cash_tendered, change_returned,
            transaction_reference, received_by, status
        )
        VALUES (
            gen_random_uuid(), p_bill_id, v_method, v_amount, v_cash_tendered, v_change_returned,
            v_tx_ref, v_actor, 'completed'
        )
        RETURNING id INTO v_payment_id;

        v_payment_ids := array_append(v_payment_ids, v_payment_id);
    END LOOP;

    -- 8. Verify total payments equal bill final amount
    IF v_total_paid <> v_bill.final_amount THEN
        RAISE EXCEPTION 'Total payments (₹%) do not equal bill amount (₹%)',
            v_total_paid, v_bill.final_amount;
    END IF;

    -- 9. Mark bill as paid
    UPDATE public.bills SET
        status = 'paid',
        settled_by = v_actor,
        updated_at = now()
    WHERE id = p_bill_id;

    -- 10. Complete parent order
    UPDATE public.orders SET 
        status = 'completed',
        updated_at = now() 
    WHERE id = v_bill.order_id;

    -- 11. Unconditionally complete all orders for this customer and mark customer as 'billed'
    IF v_order.session_customer_id IS NOT NULL THEN
        -- Mark any other uncompleted orders for this customer as completed
        UPDATE public.orders
        SET status = 'completed', updated_at = now()
        WHERE session_customer_id = v_order.session_customer_id
          AND status NOT IN ('completed', 'cancelled');

        -- Mark any other unpaid bills for this customer as paid
        UPDATE public.bills
        SET status = 'paid', settled_by = v_actor, updated_at = now()
        WHERE order_id IN (
            SELECT id FROM public.orders WHERE session_customer_id = v_order.session_customer_id
        ) AND status = 'unpaid';

        -- Update customer status to 'billed' so they vanish from biller screen
        UPDATE public.table_session_customers
        SET status = 'billed', updated_at = now()
        WHERE id = v_order.session_customer_id;
    END IF;

    -- 12. If all orders in the session are now settled, update table_sessions to 'billing'
    IF v_order.session_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.orders o
            WHERE o.session_id = v_order.session_id
              AND o.status NOT IN ('completed', 'cancelled')
        ) THEN
            UPDATE public.table_sessions
            SET status = 'billing', updated_at = now()
            WHERE id = v_order.session_id AND status = 'active';
        END IF;
    END IF;

    -- 13. Audit log
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (v_actor, 'BILL_SETTLED', 'bill', p_bill_id::text,
        jsonb_build_object('bill_number', v_bill.bill_number, 'final_amount', v_bill.final_amount,
            'payment_count', jsonb_array_length(p_payments), 'payment_ids', v_payment_ids));

    RETURN jsonb_build_object(
        'success', true,
        'bill_id', p_bill_id,
        'bill_number', v_bill.bill_number,
        'final_amount', v_bill.final_amount,
        'payment_ids', v_payment_ids
    );
END;
$$;

REVOKE ALL ON FUNCTION public.settle_bill(UUID, JSONB) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.settle_bill(UUID, JSONB) TO authenticated;


-- 2. Update get_active_table_session_details RPC to EXCLUDE billed/closed customers
CREATE OR REPLACE FUNCTION public.get_active_table_session_details(p_table_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_table RECORD;
    v_session RECORD;
    v_customers JSONB := '[]'::jsonb;
    v_active_total NUMERIC(10,2) := 0.00;
    v_active_orders_count INTEGER := 0;
BEGIN
    SELECT * INTO v_table
    FROM public.restaurant_tables
    WHERE id = p_table_id;

    IF v_table IS NULL THEN
        RAISE EXCEPTION 'Table not found';
    END IF;

    -- Match session in 'active' or 'billing'
    SELECT * INTO v_session
    FROM public.table_sessions
    WHERE table_id = p_table_id AND status IN ('active', 'billing')
    LIMIT 1;

    IF v_session IS NULL THEN
        RETURN jsonb_build_object(
            'table_id', v_table.id,
            'table_number', v_table.table_number,
            'seating_capacity', v_table.seating_capacity,
            'table_status', v_table.status,
            'session_id', NULL,
            'status', 'available',
            'customers', '[]'::jsonb,
            'active_total', 0.00,
            'active_orders_count', 0
        );
    END IF;

    -- Calculate active UNSETTLED total and active orders count for this session
    SELECT 
        COALESCE(SUM(oi.item_total), 0.00),
        COUNT(DISTINCT o.id)
    INTO v_active_total, v_active_orders_count
    FROM public.orders o
    JOIN public.order_items oi ON oi.order_id = o.id
    WHERE o.session_id = v_session.id 
      AND o.status IN ('open', 'served')
      AND oi.status <> 'cancelled';

    -- Build customers EXCLUDING billed and closed customers (vanish settled customers)
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', sc.id,
            'session_id', sc.session_id,
            'customer_label', sc.customer_label,
            'customer_name', sc.customer_name,
            'customer_phone', sc.customer_phone,
            'status', sc.status,
            'finished_at', sc.finished_at,
            'finished_by', sc.finished_by,
            'created_at', sc.created_at,
            'active_orders_count', COALESCE(ord_summary.active_count, 0),
            'active_total', COALESCE(ord_summary.active_total, 0.00),
            'orders', COALESCE(ord_summary.orders_json, '[]'::jsonb)
        ) ORDER BY sc.created_at ASC
    )
    INTO v_customers
    FROM public.table_session_customers sc
    LEFT JOIN LATERAL (
        SELECT 
            COUNT(CASE WHEN o.status IN ('open', 'served') THEN 1 END) AS active_count,
            COALESCE(SUM(CASE WHEN o.status IN ('open', 'served') THEN o_items.total ELSE 0 END), 0.00) AS active_total,
            jsonb_agg(
                jsonb_build_object(
                    'id', o.id,
                    'order_number', o.order_number,
                    'status', o.status,
                    'created_at', o.created_at,
                    'cancelled_at', o.cancelled_at,
                    'cancellation_reason', o.cancellation_reason,
                    'total_amount', COALESCE(o_items.total, 0.00),
                    'items_count', COALESCE(o_items.cnt, 0),
                    'items_summary', COALESCE(o_items.summary, ''),
                    'is_settled', (o.status = 'completed')
                ) ORDER BY o.created_at DESC
            ) AS orders_json
        FROM public.orders o
        LEFT JOIN LATERAL (
            SELECT 
                SUM(CASE WHEN oi.status <> 'cancelled' THEN oi.item_total ELSE 0 END) AS total,
                SUM(CASE WHEN oi.status <> 'cancelled' THEN oi.quantity ELSE 0 END) AS cnt,
                string_agg(
                    oi.item_name_snapshot || 
                    CASE 
                        WHEN oi.special_instructions IS NOT NULL AND trim(oi.special_instructions) <> '' 
                        THEN ' (' || trim(oi.special_instructions) || ')' 
                        ELSE '' 
                    END || ' × ' || oi.quantity, 
                    ', '
                ) AS summary
            FROM public.order_items oi
            WHERE oi.order_id = o.id AND oi.status <> 'cancelled'
        ) o_items ON true
        WHERE o.session_customer_id = sc.id
          AND o.status <> 'cancelled'
    ) ord_summary ON true
    WHERE sc.session_id = v_session.id
      AND sc.status NOT IN ('billed', 'closed');

    RETURN jsonb_build_object(
        'table_id', v_table.id,
        'table_number', v_table.table_number,
        'seating_capacity', v_table.seating_capacity,
        'table_status', v_table.status,
        'session_id', v_session.id,
        'status', v_session.status,
        'opened_at', v_session.opened_at,
        'customers', COALESCE(v_customers, '[]'::jsonb),
        'active_total', v_active_total,
        'active_orders_count', v_active_orders_count
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_active_table_session_details(UUID) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_active_table_session_details(UUID) TO authenticated;
