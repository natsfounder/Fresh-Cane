-- =============================================================================
-- Migration: 20261003110000_consolidate_customer_orders_in_billing.sql
-- Description:
--   When generating a bill for an order in a dining session, automatically
--   consolidate any other active unbilled orders for the same customer (or session)
--   into this bill. Moves line items from secondary orders to the primary order,
--   marks secondary orders as 'completed' (consolidated), and calculates the bill
--   on the complete unified subtotal so no customer items or orders are omitted.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.generate_bill_for_order(
    p_order_id UUID,
    p_discount_type VARCHAR(20) DEFAULT NULL,
    p_discount_value NUMERIC(10,2) DEFAULT 0,
    p_discount_reason VARCHAR(150) DEFAULT NULL
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
    v_other_order_ids UUID[];
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

    -- 5. Consolidate any other active unbilled orders for this customer (or table session)
    SELECT array_agg(id) INTO v_other_order_ids
    FROM public.orders
    WHERE id <> p_order_id
      AND status IN ('open', 'served')
      AND (
          (v_order.session_customer_id IS NOT NULL AND session_customer_id = v_order.session_customer_id)
          OR (v_order.session_customer_id IS NULL AND v_order.session_id IS NOT NULL AND session_id = v_order.session_id)
      )
      AND NOT EXISTS (
          SELECT 1 FROM public.bills b WHERE b.order_id = orders.id
      );

    IF v_other_order_ids IS NOT NULL AND array_length(v_other_order_ids, 1) > 0 THEN
        -- Reassign all active order items from secondary orders to the primary bill order
        UPDATE public.order_items
        SET order_id = p_order_id
        WHERE order_id = ANY(v_other_order_ids)
          AND status <> 'cancelled';

        -- Mark secondary orders as completed (consolidated) so they are not left pending
        UPDATE public.orders
        SET status = 'completed',
            notes = COALESCE(notes || E'\n', '') || 'Items consolidated into Bill for Order ' || v_order.order_number,
            subtotal = 0,
            updated_at = now()
        WHERE id = ANY(v_other_order_ids);

        -- Update primary order subtotal
        UPDATE public.orders
        SET subtotal = (
            SELECT COALESCE(SUM(item_total), 0)
            FROM public.order_items
            WHERE order_id = p_order_id AND status <> 'cancelled'
        ),
        updated_at = now()
        WHERE id = p_order_id;
    END IF;

    -- 6. Verify at least one non-cancelled item
    IF NOT EXISTS (SELECT 1 FROM public.order_items WHERE order_id = p_order_id AND status <> 'cancelled') THEN
        RAISE EXCEPTION 'Order has no active items to bill';
    END IF;

    -- 7. Lock and read store settings
    SELECT * INTO v_settings FROM public.store_settings LIMIT 1 FOR SHARE;
    IF v_settings IS NULL THEN
        RAISE EXCEPTION 'Store settings not found';
    END IF;

    -- 8. Calculate unified subtotal from active items
    SELECT COALESCE(SUM(unit_price_snapshot * quantity), 0) INTO v_subtotal
    FROM public.order_items
    WHERE order_id = p_order_id AND status <> 'cancelled';

    IF v_subtotal = 0 AND v_order.total_amount > 0 THEN
        v_subtotal := COALESCE(v_order.subtotal, v_order.total_amount);
    END IF;

    -- 9. Apply discount rules
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

    -- 10. Tax calculation
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

    -- 11. Rounding: nearest integer rupee
    v_final_amount := ROUND(v_raw_total, 0);
    v_round_off := v_final_amount - v_raw_total;

    -- 12. Business date (Asia/Kolkata)
    v_business_date := (now() AT TIME ZONE 'Asia/Kolkata')::date;

    -- 13. Allocate bill number atomically
    v_bill_number := public.get_next_bill_number(v_settings.bill_prefix);

    -- 14. Create bill
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

    -- 15. Audit: BILL_GENERATED
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
        'final_amount', v_final_amount,
        'already_exists', false
    );
END;
$$;

REVOKE ALL ON FUNCTION public.generate_bill_for_order(UUID, VARCHAR, NUMERIC, VARCHAR) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.generate_bill_for_order(UUID, VARCHAR, NUMERIC, VARCHAR) TO authenticated;
