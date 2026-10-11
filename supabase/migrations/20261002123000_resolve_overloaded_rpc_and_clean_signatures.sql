-- =============================================================================
-- Migration: 20261002123000_resolve_overloaded_rpc_and_clean_signatures.sql
-- Description:
--   Drop duplicate overloaded signatures for submit_parcel_order and
--   re-create with standard TEXT parameters and proper orders column mapping.
-- =============================================================================

DROP FUNCTION IF EXISTS public.submit_parcel_order(VARCHAR, VARCHAR, JSONB, TEXT);
DROP FUNCTION IF EXISTS public.submit_parcel_order(TEXT, TEXT, JSONB, TEXT);

CREATE OR REPLACE FUNCTION public.submit_parcel_order(
    p_customer_name TEXT DEFAULT NULL,
    p_customer_phone TEXT DEFAULT NULL,
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
    v_subtotal NUMERIC(10,2) := 0.00;
    v_total NUMERIC(10,2) := 0.00;
    v_item_subtotal NUMERIC(10,2) := 0.00;
    v_items_count INTEGER := 0;
    v_attempt INTEGER;
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

    FOR v_attempt IN 1..5 LOOP
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
                notes,
                subtotal,
                total_amount,
                created_at,
                updated_at
            ) VALUES (
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
                p_notes,
                0.00,
                0.00,
                now(),
                now()
            )
            RETURNING id INTO v_order_id;

            EXIT;
        EXCEPTION WHEN unique_violation THEN
            IF v_attempt = 5 THEN
                RAISE EXCEPTION 'Failed to allocate unique order number after 5 attempts';
            END IF;
        END;
    END LOOP;

    -- Insert items
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
        menu_item_id UUID,
        quantity INTEGER,
        instructions TEXT,
        special_instructions TEXT,
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
            COALESCE(NULLIF(trim(v_item.instructions), ''), NULLIF(trim(v_item.special_instructions), '')),
            'served',
            now(),
            now()
        );
    END LOOP;

    -- Update order totals
    UPDATE public.orders
    SET subtotal = v_subtotal,
        total_amount = v_total,
        status = 'served',
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

REVOKE EXECUTE ON FUNCTION public.submit_parcel_order(TEXT, TEXT, JSONB, TEXT) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_parcel_order(TEXT, TEXT, JSONB, TEXT) TO authenticated;
