-- =============================================================================
-- Migration: 20260914180000_server_order_flow.sql
-- Description: Server Order Flow — Atomic Dine-In Submission RPC,
--              Realtime publication for restaurant_tables, and Initial Café Seed Data.
-- =============================================================================

-- *****************************************************************************
-- SECTION 1: ATOMIC RPC submit_dine_in_order
-- *****************************************************************************

-- Ensure generate_order_number has extensions in search_path to access gen_random_bytes
CREATE OR REPLACE FUNCTION public.generate_order_number(p_prefix VARCHAR DEFAULT 'ORD-')
RETURNS VARCHAR(35)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_date_part TEXT;
    v_random_part TEXT;
    v_order_number VARCHAR(35);
    v_attempt INTEGER := 0;
    v_max_attempts CONSTANT INTEGER := 3;
BEGIN
    v_date_part := to_char(now() AT TIME ZONE 'Asia/Kolkata', 'YYYYMMDD');

    LOOP
        v_attempt := v_attempt + 1;
        v_random_part := encode(extensions.gen_random_bytes(2), 'hex');
        v_order_number := p_prefix || v_date_part || '-' || v_random_part;

        -- Check if this number already exists
        IF NOT EXISTS (SELECT 1 FROM public.orders WHERE order_number = v_order_number) THEN
            RETURN v_order_number;
        END IF;

        IF v_attempt >= v_max_attempts THEN
            RAISE EXCEPTION 'Failed to generate unique order number after % attempts', v_max_attempts;
        END IF;
    END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.generate_order_number(VARCHAR) FROM authenticated, anon, PUBLIC;

CREATE OR REPLACE FUNCTION public.submit_dine_in_order(
    p_table_id UUID,
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
    v_table RECORD;
    v_normalized_phone VARCHAR(10) := NULL;
    v_customer_id UUID := NULL;
    v_order_prefix VARCHAR(10) := 'ORD-';
    v_order_number VARCHAR(35);
    v_order_id UUID;
    v_attempt INTEGER;
    v_item RECORD;
    v_menu_item RECORD;
    v_category_name VARCHAR(100);
    v_item_qty INTEGER;
    v_instructions VARCHAR(200);
    v_items_count INTEGER := 0;
BEGIN
    -- 1. Authorization: verify caller is authenticated active staff with permitted role
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: authentication required';
    END IF;

    SELECT role INTO v_role
    FROM public.user_profiles
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR v_role NOT IN ('server', 'cashier', 'super_admin') THEN
        RAISE EXCEPTION 'Unauthorized: caller does not possess staff ordering privileges';
    END IF;

    -- 2. Validate items payload is not empty
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Order must contain at least one item';
    END IF;

    -- 3. Concurrency Lock: Lock table row FOR UPDATE and verify availability
    SELECT * INTO v_table
    FROM public.restaurant_tables
    WHERE id = p_table_id AND is_active = true
    FOR UPDATE;

    IF v_table IS NULL THEN
        RAISE EXCEPTION 'Table not found or inactive';
    END IF;

    IF v_table.status <> 'available' THEN
        RAISE EXCEPTION 'Table % is not available (current status: %)', v_table.table_number, v_table.status;
    END IF;

    -- 4. Customer Handling (Optional, normalized and upserted if provided)
    IF p_customer_phone IS NOT NULL AND trim(p_customer_phone) <> '' THEN
        v_normalized_phone := public.normalize_indian_phone(p_customer_phone);

        INSERT INTO public.customers (phone, name)
        VALUES (v_normalized_phone, NULLIF(trim(p_customer_name), ''))
        ON CONFLICT (phone) DO UPDATE SET
            name = COALESCE(NULLIF(trim(EXCLUDED.name), ''), public.customers.name),
            updated_at = now()
        RETURNING id INTO v_customer_id;
    END IF;

    -- 5. Retrieve order prefix from store_settings
    SELECT COALESCE(order_prefix, 'ORD-') INTO v_order_prefix
    FROM public.store_settings
    LIMIT 1;

    -- 6. Generate order number with collision retry loop (max 3 attempts)
    FOR v_attempt IN 1..3 LOOP
        v_order_number := public.generate_order_number(v_order_prefix);
        BEGIN
            INSERT INTO public.orders (
                id,
                order_number,
                order_type,
                table_id,
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
                v_customer_id,
                NULLIF(trim(p_customer_name), ''),
                v_normalized_phone,
                v_actor,
                'open',
                p_notes
            )
            RETURNING id INTO v_order_id;

            EXIT; -- Success, break retry loop
        EXCEPTION WHEN unique_violation THEN
            IF v_attempt = 3 THEN
                RAISE EXCEPTION 'Failed to allocate unique order number after 3 attempts due to concurrent collisions';
            END IF;
        END;
    END LOOP;

    -- 7. Validate and Insert Order Items with immutable snapshots
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
        menu_item_id UUID,
        quantity INTEGER,
        special_instructions TEXT
    ) LOOP
        -- Quantity validation
        v_item_qty := v_item.quantity;
        IF v_item_qty IS NULL OR v_item_qty <= 0 THEN
            RAISE EXCEPTION 'Invalid item quantity: must be a positive integer';
        END IF;

        IF v_item.menu_item_id IS NULL THEN
            RAISE EXCEPTION 'Missing menu_item_id in order items payload';
        END IF;

        -- Verify menu item exists and is active & available
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

        -- Insert line item with authoritative database price snapshot
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
            v_menu_item.base_price,
            v_item_qty,
            v_instructions,
            'ordered'
        );

        v_items_count := v_items_count + 1;
    END LOOP;

    IF v_items_count = 0 THEN
        RAISE EXCEPTION 'No valid order items could be processed';
    END IF;

    -- 8. Mark restaurant table as occupied
    UPDATE public.restaurant_tables
    SET status = 'occupied',
        updated_at = now()
    WHERE id = p_table_id;

    -- 9. Audit log entry
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (
        v_actor,
        'ORDER_CREATED',
        'order',
        v_order_id::text,
        jsonb_build_object(
            'order_number', v_order_number,
            'order_type', 'dine_in',
            'table_id', p_table_id,
            'table_number', v_table.table_number,
            'items_count', v_items_count,
            'customer_name', p_customer_name,
            'customer_phone', v_normalized_phone
        )
    );

    RETURN jsonb_build_object(
        'order_id', v_order_id,
        'order_number', v_order_number,
        'table_number', v_table.table_number
    );
END;
$$;

-- Security hardening: Zero-trust execution grants
REVOKE ALL ON FUNCTION public.submit_dine_in_order(UUID, TEXT, TEXT, JSONB, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.submit_dine_in_order(UUID, TEXT, TEXT, JSONB, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.submit_dine_in_order(UUID, TEXT, TEXT, JSONB, TEXT) TO authenticated;


-- *****************************************************************************
-- SECTION 2: REALTIME PUBLICATION CONFIGURATION
-- *****************************************************************************

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'restaurant_tables'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.restaurant_tables;
    END IF;
END $$;


-- *****************************************************************************
-- SECTION 3: INITIAL CAFÉ SEED DATA (Idempotent)
-- *****************************************************************************

-- 3.1 Dining Tables
INSERT INTO public.restaurant_tables (id, table_number, seating_capacity, status, is_active)
VALUES
    ('10000000-0000-0000-0000-000000000001', 'T-01', 4, 'available', true),
    ('10000000-0000-0000-0000-000000000002', 'T-02', 4, 'available', true),
    ('10000000-0000-0000-0000-000000000003', 'T-03', 2, 'available', true),
    ('10000000-0000-0000-0000-000000000004', 'T-04', 6, 'available', true),
    ('10000000-0000-0000-0000-000000000005', 'T-05', 4, 'available', true),
    ('10000000-0000-0000-0000-000000000006', 'T-06', 2, 'available', true),
    ('10000000-0000-0000-0000-000000000007', 'T-07', 4, 'available', true),
    ('10000000-0000-0000-0000-000000000008', 'T-08', 8, 'available', true)
ON CONFLICT (table_number) DO UPDATE SET
    seating_capacity = EXCLUDED.seating_capacity,
    is_active = true;

-- 3.2 Menu Categories
INSERT INTO public.categories (id, name, slug, display_order, is_active)
VALUES
    ('20000000-0000-0000-0000-000000000001', 'Fresh Juices', 'fresh-juices', 1, true),
    ('20000000-0000-0000-0000-000000000002', 'Milkshakes',   'milkshakes',   2, true),
    ('20000000-0000-0000-0000-000000000003', 'Snacks',       'snacks',       3, true)
ON CONFLICT (slug) DO UPDATE SET
    name = EXCLUDED.name,
    display_order = EXCLUDED.display_order,
    is_active = true;

-- 3.3 Menu Items
INSERT INTO public.menu_items (
    id, category_id, name, description, base_price, is_available, is_active, display_order
)
VALUES
    -- Fresh Juices
    (
        '30000000-0000-0000-0000-000000000001',
        '20000000-0000-0000-0000-000000000001',
        'Sugarcane Juice',
        'Freshly cold-pressed natural sugarcane juice with ginger & lime',
        40.00,
        true,
        true,
        1
    ),
    (
        '30000000-0000-0000-0000-000000000002',
        '20000000-0000-0000-0000-000000000001',
        'Lemon Juice',
        'Refreshing fresh lemon squeeze with mint and rock salt',
        30.00,
        true,
        true,
        2
    ),
    (
        '30000000-0000-0000-0000-000000000003',
        '20000000-0000-0000-0000-000000000001',
        'Orange Juice',
        '100% pure pulpy orange juice with no added preservatives',
        60.00,
        true,
        true,
        3
    ),

    -- Milkshakes
    (
        '30000000-0000-0000-0000-000000000004',
        '20000000-0000-0000-0000-000000000002',
        'Chocolate Milkshake',
        'Rich decadent Belgian chocolate shake topped with choco chips',
        90.00,
        true,
        true,
        1
    ),
    (
        '30000000-0000-0000-0000-000000000005',
        '20000000-0000-0000-0000-000000000002',
        'Vanilla Milkshake',
        'Classic creamy Madagascar vanilla bean thickshake',
        80.00,
        true,
        true,
        2
    ),

    -- Snacks
    (
        '30000000-0000-0000-0000-000000000006',
        '20000000-0000-0000-0000-000000000003',
        'Veg Sandwich',
        'Grilled whole wheat sandwich layered with fresh crisp veggies & cheese',
        70.00,
        true,
        true,
        1
    ),
    (
        '30000000-0000-0000-0000-000000000007',
        '20000000-0000-0000-0000-000000000003',
        'Classic Burger',
        'Crispy spiced veggie patty with lettuce, tomatoes, and house mayo',
        110.00,
        true,
        true,
        2
    )
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    base_price = EXCLUDED.base_price,
    is_available = EXCLUDED.is_available,
    is_active = EXCLUDED.is_active,
    display_order = EXCLUDED.display_order;
