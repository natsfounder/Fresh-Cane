-- Migration: 20260923100000_cashier_billing_and_parcel_flow.sql
-- Description: Phase 5 Cashier Module database enhancements for Dine-In billing, role-gated table closure, and Parcel order submission.

-- 1. Update generate_bill_for_order RPC: Allow orders in 'open' or 'served' status to generate bills
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
BEGIN
    -- 1. Verify actor — cashier or super_admin only
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL OR v_role NOT IN ('cashier', 'super_admin') THEN
        RAISE EXCEPTION 'Unauthorized: only cashier or super_admin can generate bills';
    END IF;

    -- 2. Lock parent order
    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order not found';
    END IF;

    -- 3. Verify order is billable (must be in 'open' or 'served' state)
    IF v_order.status NOT IN ('open', 'served') THEN
        RAISE EXCEPTION 'Order is not billable: order status must be open or served (current status: %)', v_order.status;
    END IF;

    -- 4. Verify no existing bill
    IF EXISTS (SELECT 1 FROM public.bills WHERE order_id = p_order_id) THEN
        RAISE EXCEPTION 'A bill already exists for this order';
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

    -- 7. Calculate subtotal from active items (server-side calculation)
    SELECT COALESCE(SUM(unit_price_snapshot * quantity), 0) INTO v_subtotal
    FROM public.order_items
    WHERE order_id = p_order_id AND status <> 'cancelled';

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
        IF v_role = 'cashier' THEN
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


-- 2. Update close_table_session RPC: Restrict to Cashier/Admin & verify zero unpaid active orders exist
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
    v_session RECORD;
BEGIN
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL OR v_role NOT IN ('cashier', 'super_admin') THEN
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

    -- Verify all active non-cancelled orders linked to session are completed (settled)
    IF EXISTS (
        SELECT 1 FROM public.orders
        WHERE session_id = v_session.id
          AND status <> 'completed'
          AND status <> 'cancelled'
    ) THEN
        RAISE EXCEPTION 'Cannot close table session: unpaid or active orders remain unbilled';
    END IF;

    UPDATE public.table_sessions
    SET status = 'completed', closed_at = now(), closed_by = v_actor, updated_at = now()
    WHERE id = v_session.id;

    UPDATE public.restaurant_tables
    SET status = 'available', updated_at = now()
    WHERE id = p_table_id;

    -- Mark session customers as closed
    UPDATE public.table_session_customers
    SET status = 'closed', updated_at = now()
    WHERE session_id = v_session.id AND status <> 'closed';

    -- Audit
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (v_actor, 'TABLE_SESSION_CLOSED', 'table_session', v_session.id::text,
        jsonb_build_object('table_id', p_table_id, 'reason', p_reason));

    RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.close_table_session(UUID, TEXT) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.close_table_session(UUID, TEXT) TO authenticated;


-- 3. Create submit_parcel_order RPC: Atomically submit parcel/takeaway order without physical table
CREATE OR REPLACE FUNCTION public.submit_parcel_order(
    p_customer_name TEXT,
    p_customer_phone TEXT,
    p_items JSONB,
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
    v_normalized_phone VARCHAR(10);
    v_canonical_customer_id UUID;
    v_order_prefix VARCHAR(10) := 'ORD-';
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
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL OR v_role NOT IN ('cashier', 'super_admin') THEN
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

    -- Order number generation loop
    FOR v_attempt IN 1..3 LOOP
        v_order_number := public.generate_order_number(v_order_prefix);
        BEGIN
            INSERT INTO public.orders (
                id,
                order_number,
                order_type,
                table_id,
                session_id,
                session_customer_id,
                customer_id,
                customer_name,
                customer_phone,
                server_id,
                status,
                notes
            )
            VALUES (
                gen_random_uuid(),
                v_order_number,
                'takeaway',
                NULL,
                NULL,
                NULL,
                v_canonical_customer_id,
                NULLIF(trim(p_customer_name), ''),
                v_normalized_phone,
                v_actor,
                'open',
                p_notes
            )
            RETURNING id INTO v_order_id;

            EXIT;
        EXCEPTION WHEN unique_violation THEN
            IF v_attempt = 3 THEN
                RAISE EXCEPTION 'Failed to allocate unique order number after 3 attempts';
            END IF;
        END;
    END LOOP;

    -- Process line items
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
        menu_item_id UUID,
        quantity INTEGER,
        special_instructions TEXT
    ) LOOP
        v_item_qty := v_item.quantity;
        IF v_item_qty IS NULL OR v_item_qty <= 0 THEN
            RAISE EXCEPTION 'Invalid item quantity: must be positive integer';
        END IF;

        SELECT m.*, c.name AS cat_name
        INTO v_menu_item
        FROM public.menu_items m
        JOIN public.categories c ON c.id = m.category_id
        WHERE m.id = v_item.menu_item_id AND m.is_active = true;

        IF v_menu_item IS NULL THEN
            RAISE EXCEPTION 'Menu item % not found or inactive', v_item.menu_item_id;
        END IF;

        IF NOT v_menu_item.is_available THEN
            RAISE EXCEPTION 'Menu item "%" is currently marked unavailable', v_menu_item.name;
        END IF;

        v_instructions := NULLIF(trim(v_item.special_instructions), '');
        IF length(v_instructions) > 200 THEN
            v_instructions := substr(v_instructions, 1, 200);
        END IF;

        v_item_subtotal := round((v_menu_item.base_price * v_item_qty)::numeric, 2);
        v_subtotal := v_subtotal + v_item_subtotal;
        v_items_count := v_items_count + v_item_qty;

        INSERT INTO public.order_items (
            order_id,
            menu_item_id,
            item_name_snapshot,
            category_name_snapshot,
            unit_price_snapshot,
            quantity,
            special_instructions,
            status
        )
        VALUES (
            v_order_id,
            v_menu_item.id,
            v_menu_item.name,
            v_menu_item.cat_name,
            v_menu_item.base_price,
            v_item_qty,
            v_instructions,
            'ordered'
        );
    END LOOP;

    v_total := v_subtotal;

    UPDATE public.orders
    SET subtotal = v_subtotal,
        total_amount = v_total
    WHERE id = v_order_id;

    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (
        v_actor,
        'PARCEL_ORDER_CREATED',
        'order',
        v_order_id::text,
        jsonb_build_object(
            'order_number', v_order_number,
            'customer_name', p_customer_name,
            'customer_phone', v_normalized_phone,
            'items_count', v_items_count,
            'total_amount', v_total
        )
    );

    RETURN jsonb_build_object(
        'order_id', v_order_id,
        'order_number', v_order_number,
        'total_amount', v_total,
        'items_count', v_items_count,
        'customer_name', p_customer_name,
        'customer_phone', v_normalized_phone
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.submit_parcel_order(TEXT, TEXT, JSONB, TEXT) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_parcel_order(TEXT, TEXT, JSONB, TEXT) TO authenticated;
