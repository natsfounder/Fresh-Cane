-- =============================================================================
-- Migration: 20261002120000_fix_cashier_multi_role_and_billing.sql
-- Description:
--   1. Support assigned_roles in all authorization checks:
--      - public.is_super_admin()
--      - public.is_cashier_or_admin()
--      - public.is_cashier()
--      - public.is_server()
--   2. Update generate_bill_for_order RPC:
--      - Check (role IN ('cashier','super_admin') OR assigned_roles && ARRAY['cashier','super_admin'])
--      - Allow billing orders in 'open', 'served', 'confirmed', 'preparing', 'ready' states
--      - Gracefully return existing bill if already generated (idempotent)
--   3. Update close_table_session RPC:
--      - Check multi-role authorization
--      - Auto-complete any orders whose bills are already settled/paid
--      - Auto-cancel any zero-item dummy orders
--      - Provide descriptive error message if unsettled orders remain
--   4. Update settle_bill RPC:
--      - Check multi-role authorization
--   5. Update submit_parcel_order RPC:
--      - Check multi-role authorization
--   6. Update cancel_order & void_bill RPCs:
--      - Check multi-role authorization
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Update Helper Functions to check assigned_roles
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE id = auth.uid() 
          AND is_active = true 
          AND (role = 'super_admin' OR 'super_admin' = ANY(assigned_roles))
    );
$$;

CREATE OR REPLACE FUNCTION public.is_cashier_or_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE id = auth.uid() 
          AND is_active = true 
          AND (
              role IN ('cashier', 'super_admin') 
              OR 'cashier' = ANY(assigned_roles) 
              OR 'super_admin' = ANY(assigned_roles)
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.is_cashier()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE id = auth.uid() 
          AND is_active = true 
          AND (role = 'cashier' OR 'cashier' = ANY(assigned_roles))
    );
$$;

CREATE OR REPLACE FUNCTION public.is_server()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE id = auth.uid() 
          AND is_active = true 
          AND (role = 'server' OR 'server' = ANY(assigned_roles))
    );
$$;


-- ---------------------------------------------------------------------------
-- 2. Update generate_bill_for_order RPC
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_bill_for_order(
    p_order_id UUID,
    p_discount_type VARCHAR(20) DEFAULT NULL,
    p_discount_value NUMERIC(10,2) DEFAULT 0,
    p_discount_reason TEXT DEFAULT NULL
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
    v_order RECORD;
    v_settings RECORD;
    v_subtotal NUMERIC(10,2);
    v_discount_amount NUMERIC(10,2) := 0;
    v_discount_rate NUMERIC(5,2) := 0;
    v_discounted_subtotal NUMERIC(10,2);
    v_tax_amount NUMERIC(10,2) := 0;
    v_raw_total NUMERIC(10,2);
    v_final_amount NUMERIC(10,2);
    v_round_off NUMERIC(10,2);
    v_bill_number VARCHAR(50);
    v_bill_id UUID;
    v_business_date DATE;
    v_existing_bill RECORD;
BEGIN
    -- 1. Authorization: cashier or super_admin (including assigned_roles)
    SELECT role, assigned_roles INTO v_role, v_assigned_roles
    FROM public.user_profiles 
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR (
        v_role NOT IN ('cashier', 'super_admin') 
        AND NOT ('cashier' = ANY(v_assigned_roles) OR 'super_admin' = ANY(v_assigned_roles))
    ) THEN
        RAISE EXCEPTION 'Unauthorized: only cashier or super_admin can generate bills';
    END IF;

    -- 2. Lock parent order
    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order not found';
    END IF;

    -- 3. Verify order is not in terminal state
    IF v_order.status IN ('completed', 'cancelled') THEN
        RAISE EXCEPTION 'Order cannot be billed because it is %', v_order.status;
    END IF;

    -- 4. Check if bill already exists (idempotent return)
    SELECT id, bill_number, subtotal_amount, discount_amount, tax_amount, round_off_amount, final_amount
    INTO v_existing_bill
    FROM public.bills 
    WHERE order_id = p_order_id 
    LIMIT 1;

    IF v_existing_bill.id IS NOT NULL THEN
        RETURN jsonb_build_object(
            'bill_id', v_existing_bill.id,
            'bill_number', v_existing_bill.bill_number,
            'subtotal', v_existing_bill.subtotal_amount,
            'discount_amount', v_existing_bill.discount_amount,
            'tax_amount', v_existing_bill.tax_amount,
            'round_off', v_existing_bill.round_off_amount,
            'final_amount', v_existing_bill.final_amount,
            'already_exists', true
        );
    END IF;

    -- 5. Verify at least one non-cancelled item
    IF NOT EXISTS (SELECT 1 FROM public.order_items WHERE order_id = p_order_id AND status <> 'cancelled') THEN
        RAISE EXCEPTION 'Order has no active items to bill';
    END IF;

    -- 6. Lock and read store settings
    SELECT * INTO v_settings FROM public.store_settings LIMIT 1 FOR SHARE;
    IF v_settings IS NULL THEN
        RAISE EXCEPTION 'Store settings not found';
    END IF;

    -- 7. Calculate subtotal from active items
    SELECT COALESCE(SUM(unit_price_snapshot * quantity), 0) INTO v_subtotal
    FROM public.order_items
    WHERE order_id = p_order_id AND status <> 'cancelled';

    IF v_subtotal = 0 AND v_order.total_amount > 0 THEN
        v_subtotal := COALESCE(v_order.subtotal, v_order.total_amount);
    END IF;

    -- 8. Apply discount rules
    IF p_discount_value < 0 THEN
        RAISE EXCEPTION 'Discount value cannot be negative: %', p_discount_value;
    END IF;

    IF p_discount_value > 0 THEN
        IF p_discount_type IS NULL THEN
            RAISE EXCEPTION 'Discount type is required when discount value is greater than 0';
        END IF;

        IF p_discount_type NOT IN ('percentage', 'flat') THEN
            RAISE EXCEPTION 'Invalid discount type: %. Must be percentage or flat', p_discount_type;
        END IF;

        IF p_discount_type = 'percentage' THEN
            v_discount_rate := p_discount_value;
            v_discount_amount := ROUND(v_subtotal * p_discount_value / 100, 2);
        ELSE -- flat
            v_discount_amount := ROUND(p_discount_value, 2);
            IF v_subtotal > 0 THEN
                v_discount_rate := ROUND(v_discount_amount / v_subtotal * 100, 2);
            END IF;
        END IF;

        -- Enforce cashier limits (super_admin bypasses caps)
        IF NOT (v_role = 'super_admin' OR 'super_admin' = ANY(v_assigned_roles)) THEN
            IF p_discount_type = 'percentage' AND p_discount_value > v_settings.max_cashier_discount_percentage THEN
                RAISE EXCEPTION 'Cashier discount percentage (%) exceeds limit (%)',
                    p_discount_value, v_settings.max_cashier_discount_percentage;
            END IF;
            IF v_discount_amount > v_settings.max_cashier_discount_amount THEN
                RAISE EXCEPTION 'Cashier discount amount (₹%) exceeds limit (₹%)',
                    v_discount_amount, v_settings.max_cashier_discount_amount;
            END IF;
        END IF;

        IF v_discount_amount > v_subtotal THEN
            v_discount_amount := v_subtotal;
        END IF;

        IF p_discount_reason IS NULL OR length(trim(p_discount_reason)) < 3 THEN
            RAISE EXCEPTION 'Discount reason is required (minimum 3 characters)';
        END IF;
    ELSE
        p_discount_type := NULL;
        v_discount_rate := 0;
        v_discount_amount := 0;
    END IF;

    -- 9. Tax calculation
    v_discounted_subtotal := v_subtotal - v_discount_amount;

    IF v_settings.tax_rate_percentage > 0 THEN
        IF v_settings.is_tax_inclusive THEN
            v_tax_amount := ROUND(
                v_discounted_subtotal - (v_discounted_subtotal / (1 + v_settings.tax_rate_percentage / 100)),
                2
            );
            v_raw_total := v_discounted_subtotal;
        ELSE
            v_tax_amount := ROUND(v_discounted_subtotal * v_settings.tax_rate_percentage / 100, 2);
            v_raw_total := v_discounted_subtotal + v_tax_amount;
        END IF;
    ELSE
        v_tax_amount := 0;
        v_raw_total := v_discounted_subtotal;
    END IF;

    -- 10. Rounding: nearest integer rupee
    v_final_amount := ROUND(v_raw_total, 0);
    v_round_off := v_final_amount - v_raw_total;

    -- 11. Business date (Asia/Kolkata)
    v_business_date := (now() AT TIME ZONE 'Asia/Kolkata')::date;

    -- 12. Allocate bill number atomically
    v_bill_number := public.get_next_bill_number(v_settings.bill_prefix);

    -- 13. Create bill
    INSERT INTO public.bills (
        id, bill_number, order_id, cashier_id, business_date,
        subtotal_amount, discount_type, discount_rate, discount_amount, discount_reason,
        tax_rate_snapshot, is_tax_inclusive_snapshot, tax_amount,
        round_off_amount, final_amount,
        store_name_snapshot, store_address_snapshot, store_gstin_snapshot,
        customer_name_snapshot, customer_phone_snapshot,
        status
    )
    VALUES (
        gen_random_uuid(), v_bill_number, p_order_id, v_actor, v_business_date,
        v_subtotal, p_discount_type, v_discount_rate, v_discount_amount, p_discount_reason,
        v_settings.tax_rate_percentage, v_settings.is_tax_inclusive, v_tax_amount,
        v_round_off, v_final_amount,
        v_settings.store_name, v_settings.address, v_settings.gstin,
        v_order.customer_name, v_order.customer_phone,
        'unpaid'
    )
    RETURNING id INTO v_bill_id;

    -- 14. Audit: BILL_GENERATED
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (v_actor, 'BILL_GENERATED', 'bill', v_bill_id::text,
        jsonb_build_object('bill_number', v_bill_number, 'order_id', p_order_id,
            'subtotal', v_subtotal, 'tax_amount', v_tax_amount, 'final_amount', v_final_amount));

    IF v_discount_amount > 0 THEN
        INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
        VALUES (v_actor, 'DISCOUNT_APPLIED', 'bill', v_bill_id::text,
            jsonb_build_object('discount_type', p_discount_type, 'discount_rate', v_discount_rate,
                'discount_amount', v_discount_amount, 'discount_reason', p_discount_reason));
    END IF;

    RETURN jsonb_build_object(
        'bill_id', v_bill_id,
        'bill_number', v_bill_number,
        'subtotal', v_subtotal,
        'discount_amount', v_discount_amount,
        'tax_amount', v_tax_amount,
        'round_off', v_round_off,
        'final_amount', v_final_amount
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.generate_bill_for_order(UUID, VARCHAR, NUMERIC, VARCHAR) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.generate_bill_for_order(UUID, VARCHAR, NUMERIC, VARCHAR) TO authenticated;


-- ---------------------------------------------------------------------------
-- 3. Update close_table_session RPC
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.close_table_session(
    p_table_id UUID,
    p_reason TEXT DEFAULT 'Session closed'
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
    v_session RECORD;
    v_unbilled_number VARCHAR(50);
BEGIN
    -- 1. Authorization: cashier or super_admin (including assigned_roles)
    SELECT role, assigned_roles INTO v_role, v_assigned_roles
    FROM public.user_profiles 
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR (
        v_role NOT IN ('cashier', 'super_admin') 
        AND NOT ('cashier' = ANY(v_assigned_roles) OR 'super_admin' = ANY(v_assigned_roles))
    ) THEN
        RAISE EXCEPTION 'Unauthorized: only cashier or super_admin can close table sessions';
    END IF;

    SELECT * INTO v_session FROM public.table_sessions
    WHERE table_id = p_table_id AND status IN ('active', 'billing')
    FOR UPDATE;

    IF v_session IS NULL THEN
        -- If no active session, ensure table status is available
        UPDATE public.restaurant_tables SET status = 'available', updated_at = now() WHERE id = p_table_id;
        RETURN jsonb_build_object('success', true);
    END IF;

    -- 2. Auto-complete any orders whose bills are already settled/paid
    UPDATE public.orders o
    SET status = 'completed', updated_at = now()
    WHERE o.session_id = v_session.id
      AND o.status NOT IN ('completed', 'cancelled')
      AND EXISTS (
          SELECT 1 FROM public.bills b
          WHERE b.order_id = o.id AND b.status = 'paid'
      );

    -- 3. Auto-cancel any zero-item dummy orders with no non-cancelled items
    UPDATE public.orders o
    SET status = 'cancelled', updated_at = now()
    WHERE o.session_id = v_session.id
      AND o.status NOT IN ('completed', 'cancelled')
      AND NOT EXISTS (
          SELECT 1 FROM public.order_items oi
          WHERE oi.order_id = o.id AND oi.status <> 'cancelled'
      );

    -- 4. Check for any remaining unsettled active orders
    SELECT o.order_number INTO v_unbilled_number
    FROM public.orders o
    WHERE o.session_id = v_session.id
      AND o.status NOT IN ('completed', 'cancelled')
    LIMIT 1;

    IF v_unbilled_number IS NOT NULL THEN
        RAISE EXCEPTION 'Cannot close table: Order "%" is not settled yet. Please generate and settle the bill first.', v_unbilled_number;
    END IF;

    -- 5. Mark table session completed
    UPDATE public.table_sessions
    SET status = 'completed', closed_at = now(), closed_by = v_actor, updated_at = now()
    WHERE id = v_session.id;

    -- 6. Release table
    UPDATE public.restaurant_tables
    SET status = 'available', updated_at = now()
    WHERE id = p_table_id;

    -- 7. Mark session customers as closed
    UPDATE public.table_session_customers
    SET status = 'completed', updated_at = now()
    WHERE session_id = v_session.id AND status <> 'cancelled';

    RETURN jsonb_build_object('success', true, 'table_id', p_table_id, 'session_id', v_session.id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.close_table_session(UUID, TEXT) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.close_table_session(UUID, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- 4. Update settle_bill RPC
-- ---------------------------------------------------------------------------
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

    -- 5. Verify order is not in terminal state
    IF v_order.status IN ('completed', 'cancelled') THEN
        RAISE EXCEPTION 'Parent order is in terminal state (status: %)', v_order.status;
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

    -- 11. Audit
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

REVOKE EXECUTE ON FUNCTION public.settle_bill(UUID, JSONB) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.settle_bill(UUID, JSONB) TO authenticated;


-- ---------------------------------------------------------------------------
-- 5. Update submit_parcel_order RPC
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_parcel_order(
    p_customer_name VARCHAR(100) DEFAULT NULL,
    p_customer_phone VARCHAR(20) DEFAULT NULL,
    p_items JSONB DEFAULT '[]'::jsonb,
    p_notes TEXT DEFAULT NULL
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
    v_canonical_customer_id UUID;
    v_normalized_phone VARCHAR(20);
    v_order_prefix VARCHAR(10);
    v_order_number VARCHAR(50);
    v_order_id UUID;
    v_item RECORD;
    v_menu_item RECORD;
    v_item_qty INTEGER;
    v_instructions TEXT;
    v_subtotal NUMERIC(10,2) := 0.00;
    v_total NUMERIC(10,2) := 0.00;
    v_item_subtotal NUMERIC(10,2) := 0.00;
    v_items_count INTEGER := 0;
BEGIN
    SELECT role, assigned_roles INTO v_role, v_assigned_roles
    FROM public.user_profiles 
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR (
        v_role NOT IN ('cashier', 'super_admin') 
        AND NOT ('cashier' = ANY(v_assigned_roles) OR 'super_admin' = ANY(v_assigned_roles))
    ) THEN
        RAISE EXCEPTION 'Unauthorized: only cashier or super_admin can place parcel orders';
    END IF;

    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Cannot place parcel order with no items';
    END IF;

    -- Canonical phone handling
    IF p_customer_phone IS NOT NULL AND trim(p_customer_phone) <> '' THEN
        v_normalized_phone := public.normalize_indian_phone(p_customer_phone);

        INSERT INTO public.customers (phone, name)
        VALUES (v_normalized_phone, NULLIF(trim(p_customer_name), ''))
        ON CONFLICT (phone) DO UPDATE SET
            name = COALESCE(NULLIF(trim(EXCLUDED.name), ''), public.customers.name),
            updated_at = now()
        RETURNING id INTO v_canonical_customer_id;
    END IF;

    -- Order prefix
    SELECT COALESCE(order_prefix, 'ORD-') INTO v_order_prefix
    FROM public.store_settings
    LIMIT 1;

    v_order_number := v_order_prefix || to_char(now(), 'YYYYMMDD') || '-' || LPAD(FLOOR(RANDOM() * 10000)::TEXT, 4, '0');
    v_order_id := gen_random_uuid();

    -- Create parcel order in 'served' state so it is immediately billable
    INSERT INTO public.orders (
        id,
        order_number,
        session_id,
        session_customer_id,
        order_type,
        status,
        customer_name,
        customer_phone,
        notes,
        created_by,
        subtotal,
        total_amount,
        created_at,
        updated_at
    ) VALUES (
        v_order_id,
        v_order_number,
        NULL,
        NULL,
        'parcel',
        'served',
        NULLIF(trim(p_customer_name), ''),
        v_normalized_phone,
        NULLIF(trim(p_notes), ''),
        v_actor,
        0.00,
        0.00,
        now(),
        now()
    );

    -- Insert items
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
        menu_item_id UUID,
        quantity INTEGER,
        instructions TEXT,
        unit_price NUMERIC(10,2)
    )
    LOOP
        SELECT * INTO v_menu_item FROM public.menu_items WHERE id = v_item.menu_item_id AND is_active = true;
        IF v_menu_item IS NULL THEN
            RAISE EXCEPTION 'Menu item % not found or inactive', v_item.menu_item_id;
        END IF;

        v_item_qty := COALESCE(v_item.quantity, 1);
        IF v_item_qty <= 0 THEN
            RAISE EXCEPTION 'Item quantity must be greater than zero';
        END IF;

        v_item_subtotal := COALESCE(v_item.unit_price, v_menu_item.price) * v_item_qty;
        v_subtotal := v_subtotal + v_item_subtotal;
        v_total := v_total + v_item_subtotal;
        v_items_count := v_items_count + 1;

        INSERT INTO public.order_items (
            order_id,
            menu_item_id,
            item_name_snapshot,
            unit_price_snapshot,
            quantity,
            subtotal,
            special_instructions,
            status,
            created_at,
            updated_at
        ) VALUES (
            v_order_id,
            v_menu_item.id,
            v_menu_item.name,
            COALESCE(v_item.unit_price, v_menu_item.price),
            v_item_qty,
            v_item_subtotal,
            NULLIF(trim(v_item.instructions), ''),
            'served',
            now(),
            now()
        );
    END LOOP;

    -- Update order totals
    UPDATE public.orders
    SET subtotal = v_subtotal,
        total_amount = v_total,
        updated_at = now()
    WHERE id = v_order_id;

    RETURN jsonb_build_object(
        'success', true,
        'order_id', v_order_id,
        'order_number', v_order_number,
        'items_count', v_items_count,
        'subtotal', v_subtotal,
        'total_amount', v_total
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.submit_parcel_order(VARCHAR, VARCHAR, JSONB, TEXT) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_parcel_order(VARCHAR, VARCHAR, JSONB, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- 6. Update cancel_order & void_bill RPCs
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_order(
    p_order_id UUID,
    p_reason TEXT DEFAULT NULL
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
    v_order RECORD;
BEGIN
    SELECT role, assigned_roles INTO v_role, v_assigned_roles
    FROM public.user_profiles 
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR (
        v_role NOT IN ('cashier', 'super_admin') 
        AND NOT ('cashier' = ANY(v_assigned_roles) OR 'super_admin' = ANY(v_assigned_roles))
    ) THEN
        RAISE EXCEPTION 'Unauthorized: only cashier or super_admin can cancel orders';
    END IF;

    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order not found';
    END IF;

    IF v_order.status IN ('completed', 'cancelled') THEN
        RAISE EXCEPTION 'Order cannot be cancelled (status: %)', v_order.status;
    END IF;
    IF EXISTS (SELECT 1 FROM public.bills WHERE order_id = p_order_id) THEN
        RAISE EXCEPTION 'Order has a bill — use void_bill() to cancel a billed order';
    END IF;

    UPDATE public.order_items SET status = 'cancelled', updated_at = now()
    WHERE order_id = p_order_id AND status <> 'cancelled';

    UPDATE public.orders SET status = 'cancelled', updated_at = now()
    WHERE id = p_order_id;

    RETURN jsonb_build_object('success', true, 'order_id', p_order_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_order(UUID, TEXT) TO authenticated;


CREATE OR REPLACE FUNCTION public.void_bill(
    p_bill_id UUID,
    p_reason TEXT
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
BEGIN
    SELECT role, assigned_roles INTO v_role, v_assigned_roles
    FROM public.user_profiles 
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR (
        v_role <> 'super_admin' 
        AND NOT ('super_admin' = ANY(v_assigned_roles))
    ) THEN
        RAISE EXCEPTION 'Unauthorized: only super_admin can void bills';
    END IF;

    IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
        RAISE EXCEPTION 'Void reason is required (minimum 3 characters)';
    END IF;

    SELECT * INTO v_bill FROM public.bills WHERE id = p_bill_id FOR UPDATE;
    IF v_bill IS NULL THEN
        RAISE EXCEPTION 'Bill not found';
    END IF;

    IF v_bill.status = 'voided' THEN
        RAISE EXCEPTION 'Bill % is already voided', v_bill.bill_number;
    END IF;

    UPDATE public.bills SET status = 'voided', void_reason = p_reason, voided_by = v_actor, voided_at = now(), updated_at = now()
    WHERE id = p_bill_id;

    -- Return order to open status
    UPDATE public.orders SET status = 'open', updated_at = now()
    WHERE id = v_bill.order_id;

    RETURN jsonb_build_object('success', true, 'bill_id', p_bill_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.void_bill(UUID, TEXT) TO authenticated;
