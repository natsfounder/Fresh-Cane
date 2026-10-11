-- =============================================================================
-- Migration: 20261002070000_addons_parcel_support_in_order_rpcs.sql
-- Description:
--   1. Create public.menu_addons table and seed default Fresh Cane add-ons.
--   2. Update submit_dine_in_order RPC to accept unit_price (accounting for add-ons).
--   3. Update update_server_order RPC to accept unit_price (accounting for add-ons).
-- =============================================================================

-- 1. Table: public.menu_addons
CREATE TABLE IF NOT EXISTS public.menu_addons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL UNIQUE,
    price NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    is_active BOOLEAN NOT NULL DEFAULT true,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed default Fresh Cane add-ons
INSERT INTO public.menu_addons (name, price, display_order)
VALUES 
    ('Fresh Ginger', 10.00, 1),
    ('Fresh Lemon', 5.00, 2),
    ('Mint / Pudina', 5.00, 3),
    ('Chat Masala / Pepper', 5.00, 4),
    ('Pure Honey', 20.00, 5),
    ('Chia / Sabja Seeds', 15.00, 6),
    ('Nannari Syrup', 15.00, 7),
    ('Extra Sugarcane Shot', 20.00, 8)
ON CONFLICT (name) DO UPDATE SET
    price = EXCLUDED.price,
    display_order = EXCLUDED.display_order;

-- RLS & Grants for menu_addons
ALTER TABLE public.menu_addons ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read active menu_addons" ON public.menu_addons;
CREATE POLICY "Anyone can read active menu_addons" ON public.menu_addons
    FOR SELECT TO authenticated, anon USING (is_active = true);

GRANT SELECT ON public.menu_addons TO authenticated, anon;


-- 2. Update submit_dine_in_order to accept unit_price
CREATE OR REPLACE FUNCTION public.submit_dine_in_order(
    p_table_id UUID,
    p_session_id UUID DEFAULT NULL,
    p_session_customer_id UUID DEFAULT NULL,
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
    v_session_id UUID;
    v_session_customer_id UUID;
    v_customer_status VARCHAR(20);
    v_order_id UUID;
    v_order_number VARCHAR(50);
    v_order_prefix VARCHAR(10);
    v_order_total NUMERIC(10,2) := 0.00;
    v_item RECORD;
    v_menu_item RECORD;
    v_item_qty INTEGER;
    v_unit_price NUMERIC(10,2);
    v_instructions TEXT;
    v_canonical_customer_id UUID;
    v_normalized_phone VARCHAR(20);
    v_items_count INTEGER := 0;
BEGIN
    -- 1. Authorization
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: authentication required';
    END IF;

    SELECT role INTO v_role
    FROM public.user_profiles
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR v_role NOT IN ('server', 'cashier', 'super_admin') THEN
        RAISE EXCEPTION 'Unauthorized: caller does not possess staff privileges';
    END IF;

    -- 2. Validate table
    IF NOT EXISTS (
        SELECT 1 FROM public.restaurant_tables
        WHERE id = p_table_id AND is_active = true
    ) THEN
        RAISE EXCEPTION 'Table not found or inactive';
    END IF;

    -- 3. Validate items
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Order must contain at least one item';
    END IF;

    -- 4. Session management
    IF p_session_id IS NOT NULL THEN
        SELECT id INTO v_session_id
        FROM public.table_sessions
        WHERE id = p_session_id AND table_id = p_table_id AND status = 'active';

        IF v_session_id IS NULL THEN
            RAISE EXCEPTION 'Provided session is not active or does not belong to table';
        END IF;
    ELSE
        SELECT id INTO v_session_id
        FROM public.table_sessions
        WHERE table_id = p_table_id AND status = 'active'
        ORDER BY opened_at DESC
        LIMIT 1;

        IF v_session_id IS NULL THEN
            INSERT INTO public.table_sessions (table_id, server_id, status)
            VALUES (p_table_id, v_actor, 'active')
            RETURNING id INTO v_session_id;
        END IF;
    END IF;

    -- 5. Customer management
    IF p_session_customer_id IS NOT NULL THEN
        SELECT id, status INTO v_session_customer_id, v_customer_status
        FROM public.table_session_customers
        WHERE id = p_session_customer_id AND session_id = v_session_id;

        IF v_session_customer_id IS NULL THEN
            RAISE EXCEPTION 'Customer does not belong to active table session';
        END IF;

        IF v_customer_status != 'active' THEN
            RAISE EXCEPTION 'Customer is marked as "%" and cannot place new orders. Session has completed ordering.', v_customer_status;
        END IF;
    ELSE
        INSERT INTO public.table_session_customers (
            session_id,
            customer_name,
            customer_phone,
            status
        )
        VALUES (
            v_session_id,
            NULLIF(trim(p_customer_name), ''),
            NULLIF(trim(p_customer_phone), ''),
            'active'
        )
        RETURNING id INTO v_session_customer_id;
    END IF;

    -- 6. Canonical customer linking
    IF p_customer_phone IS NOT NULL AND trim(p_customer_phone) != '' THEN
        v_normalized_phone := regexp_replace(trim(p_customer_phone), '\D', '', 'g');
        IF length(v_normalized_phone) = 10 THEN
            v_normalized_phone := '+91' || v_normalized_phone;
        ELSIF length(v_normalized_phone) = 12 AND v_normalized_phone LIKE '91%' THEN
            v_normalized_phone := '+' || v_normalized_phone;
        ELSE
            v_normalized_phone := trim(p_customer_phone);
        END IF;

        INSERT INTO public.customers (phone, name)
        VALUES (v_normalized_phone, NULLIF(trim(p_customer_name), ''))
        ON CONFLICT (phone) DO UPDATE SET
            name = COALESCE(NULLIF(trim(EXCLUDED.name), ''), public.customers.name),
            updated_at = now()
        RETURNING id INTO v_canonical_customer_id;
    END IF;

    -- 7. Retrieve order prefix
    SELECT COALESCE(order_prefix, 'ORD-') INTO v_order_prefix
    FROM public.store_settings
    LIMIT 1;

    -- 8. Generate order number
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
                'dine_in',
                p_table_id,
                v_session_id,
                v_session_customer_id,
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
                RAISE EXCEPTION 'Failed to generate unique order number after 3 attempts';
            END IF;
        END;
    END LOOP;

    -- 9. Insert line items (accounting for unit_price with add-ons)
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
        menu_item_id UUID,
        quantity INTEGER,
        special_instructions TEXT,
        unit_price NUMERIC
    ) LOOP
        v_item_qty := v_item.quantity;
        IF v_item_qty IS NULL OR v_item_qty <= 0 THEN
            CONTINUE;
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

        -- Use provided unit_price (base price + add-ons) if >= base_price
        v_unit_price := COALESCE(v_item.unit_price, v_menu_item.base_price);
        IF v_unit_price < v_menu_item.base_price THEN
            v_unit_price := v_menu_item.base_price;
        END IF;

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
            v_item.menu_item_id,
            v_menu_item.name,
            v_menu_item.cat_name,
            v_unit_price,
            v_item_qty,
            v_instructions,
            'ordered'
        );

        v_items_count := v_items_count + 1;
        v_order_total := v_order_total + (v_item_qty * v_unit_price);
    END LOOP;

    -- Update order totals
    UPDATE public.orders
    SET subtotal = v_order_total,
        total_amount = v_order_total,
        updated_at = now()
    WHERE id = v_order_id;

    -- 10. Update table status to occupied
    UPDATE public.restaurant_tables
    SET status = 'occupied',
        updated_at = now()
    WHERE id = p_table_id;

    -- 11. Audit log
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (
        v_actor,
        'ORDER_CREATED',
        'order',
        v_order_id::text,
        jsonb_build_object(
            'order_number', v_order_number,
            'table_id', p_table_id,
            'session_id', v_session_id,
            'customer_id', v_session_customer_id,
            'items_count', v_items_count,
            'total_amount', v_order_total
        )
    );

    RETURN jsonb_build_object(
        'order_id', v_order_id,
        'order_number', v_order_number,
        'table_id', p_table_id,
        'session_id', v_session_id,
        'session_customer_id', v_session_customer_id,
        'total_amount', v_order_total,
        'status', 'open'
    );
END;
$$;


-- 3. Update update_server_order to accept unit_price
CREATE OR REPLACE FUNCTION public.update_server_order(
    p_order_id UUID,
    p_items JSONB,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_order RECORD;
    v_item RECORD;
    v_menu_item RECORD;
    v_item_qty INTEGER;
    v_unit_price NUMERIC(10,2);
    v_instructions TEXT;
    v_subtotal NUMERIC(10,2) := 0.00;
    v_total NUMERIC(10,2) := 0.00;
    v_item_subtotal NUMERIC(10,2) := 0.00;
    v_items_count INTEGER := 0;
BEGIN
    SELECT * INTO v_order
    FROM public.orders
    WHERE id = p_order_id
    FOR UPDATE;

    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order not found';
    END IF;

    IF v_order.status = 'cancelled' THEN
        RAISE EXCEPTION 'Cannot edit a cancelled order';
    END IF;

    IF v_order.status = 'completed' THEN
        RAISE EXCEPTION 'Cannot edit a completed/settled order';
    END IF;

    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Order must contain at least one item. To cancel an order, use Cancel Order.';
    END IF;

    DELETE FROM public.order_items
    WHERE order_id = p_order_id;

    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
        menu_item_id UUID,
        quantity INTEGER,
        special_instructions TEXT,
        unit_price NUMERIC
    ) LOOP
        v_item_qty := v_item.quantity;
        IF v_item_qty IS NULL OR v_item_qty <= 0 THEN
            CONTINUE;
        END IF;

        SELECT m.*, c.name AS cat_name
        INTO v_menu_item
        FROM public.menu_items m
        JOIN public.categories c ON c.id = m.category_id
        WHERE m.id = v_item.menu_item_id;

        IF v_menu_item IS NULL THEN
            RAISE EXCEPTION 'Menu item % not found', v_item.menu_item_id;
        END IF;

        v_instructions := NULLIF(trim(v_item.special_instructions), '');
        IF length(v_instructions) > 200 THEN
            v_instructions := substr(v_instructions, 1, 200);
        END IF;

        v_unit_price := COALESCE(v_item.unit_price, v_menu_item.price);
        IF v_unit_price < v_menu_item.price THEN
            v_unit_price := v_menu_item.price;
        END IF;

        v_item_subtotal := round((v_unit_price * v_item_qty)::numeric, 2);
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
            p_order_id,
            v_menu_item.id,
            v_menu_item.name,
            v_menu_item.cat_name,
            v_unit_price,
            v_item_qty,
            v_instructions,
            'ordered'
        );
    END LOOP;

    IF v_items_count = 0 THEN
        RAISE EXCEPTION 'Order must contain at least one item with valid quantity';
    END IF;

    v_total := v_subtotal;

    UPDATE public.orders
    SET subtotal = v_subtotal,
        total_amount = v_total,
        notes = NULLIF(trim(p_notes), ''),
        updated_at = now()
    WHERE id = p_order_id;

    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (
        v_actor,
        'ORDER_EDITED',
        'order',
        p_order_id::text,
        jsonb_build_object(
            'order_number', v_order.order_number,
            'table_id', v_order.table_id,
            'subtotal', v_subtotal,
            'items_count', v_items_count
        )
    );

    RETURN jsonb_build_object(
        'order_id', p_order_id,
        'order_number', v_order.order_number,
        'subtotal', v_subtotal,
        'total_amount', v_total,
        'items_count', v_items_count,
        'status', v_order.status
    );
END;
$$;
