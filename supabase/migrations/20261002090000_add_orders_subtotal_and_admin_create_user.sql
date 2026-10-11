-- =============================================================================
-- Migration: 20261002090000_add_orders_subtotal_and_admin_create_user.sql
-- Description:
--   1. Add missing `subtotal` and `total_amount` columns to `public.orders`.
--   2. Backfill existing orders with item totals.
--   3. Ensure `submit_dine_in_order` and `update_server_order` run without errors.
--   4. Implement `admin_create_staff_user` RPC for super_admin user management.
-- =============================================================================

-- 1. Add subtotal and total_amount to public.orders
ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS subtotal NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS total_amount NUMERIC(10,2) NOT NULL DEFAULT 0.00;

-- 2. Backfill existing orders with totals from order_items
UPDATE public.orders o
SET subtotal = COALESCE(sub.tot, 0.00),
    total_amount = COALESCE(sub.tot, 0.00),
    updated_at = now()
FROM (
    SELECT order_id, SUM(item_total) AS tot
    FROM public.order_items
    WHERE status <> 'cancelled'
    GROUP BY order_id
) sub
WHERE o.id = sub.order_id
  AND (o.subtotal = 0.00 OR o.total_amount = 0.00);

-- 3. Ensure submit_dine_in_order is updated and rock-solid
CREATE OR REPLACE FUNCTION public.submit_dine_in_order(
    p_table_id UUID,
    p_customer_name TEXT DEFAULT NULL,
    p_customer_phone TEXT DEFAULT NULL,
    p_items JSONB DEFAULT '[]'::jsonb,
    p_notes TEXT DEFAULT NULL,
    p_session_id UUID DEFAULT NULL,
    p_session_customer_id UUID DEFAULT NULL
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
    v_session_id UUID := p_session_id;
    v_session_customer_id UUID := p_session_customer_id;
    v_customer_rec RECORD;
    v_normalized_phone VARCHAR(10) := NULL;
    v_canonical_customer_id UUID := NULL;
    v_order_prefix VARCHAR(10) := 'ORD-';
    v_order_number VARCHAR(35);
    v_order_id UUID;
    v_attempt INTEGER;
    v_item RECORD;
    v_menu_item RECORD;
    v_item_qty INTEGER;
    v_unit_price NUMERIC(10,2);
    v_instructions VARCHAR(200);
    v_items_count INTEGER := 0;
    v_order_total NUMERIC(10,2) := 0.00;
BEGIN
    -- 1. Authorization
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: authentication required';
    END IF;

    SELECT role INTO v_role
    FROM public.user_profiles
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR v_role NOT IN ('server', 'cashier', 'super_admin') THEN
        RAISE EXCEPTION 'Unauthorized: caller does not possess staff ordering privileges';
    END IF;

    -- 2. Items validation
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Order must contain at least one item';
    END IF;

    -- 3. Concurrency Lock: Lock table row
    SELECT * INTO v_table
    FROM public.restaurant_tables
    WHERE id = p_table_id AND is_active = true
    FOR UPDATE;

    IF v_table IS NULL THEN
        RAISE EXCEPTION 'Table not found or inactive';
    END IF;

    -- 4. Session resolution
    IF v_session_id IS NULL THEN
        SELECT id INTO v_session_id
        FROM public.table_sessions
        WHERE table_id = p_table_id AND status IN ('active', 'billing')
        LIMIT 1;

        IF v_session_id IS NULL THEN
            INSERT INTO public.table_sessions (table_id, status, opened_at, opened_by)
            VALUES (p_table_id, 'active', now(), v_actor)
            ON CONFLICT (table_id) WHERE status IN ('active', 'billing')
            DO UPDATE SET updated_at = now()
            RETURNING id INTO v_session_id;

            UPDATE public.restaurant_tables
            SET status = 'occupied', updated_at = now()
            WHERE id = p_table_id;
        END IF;
    ELSE
        SELECT id INTO v_session_id
        FROM public.table_sessions
        WHERE id = v_session_id AND status IN ('active', 'billing');

        IF v_session_id IS NULL THEN
            RAISE EXCEPTION 'Specified table session is not active';
        END IF;
    END IF;

    -- 5. Customer resolution
    IF v_session_customer_id IS NULL THEN
        SELECT id INTO v_session_customer_id
        FROM public.table_session_customers
        WHERE session_id = v_session_id AND status = 'active'
        ORDER BY created_at ASC
        LIMIT 1;

        IF v_session_customer_id IS NULL THEN
            INSERT INTO public.table_session_customers (
                session_id,
                customer_label,
                customer_name,
                customer_phone,
                status
            )
            VALUES (
                v_session_id,
                COALESCE(NULLIF(trim(p_customer_name), ''), 'Customer 1'),
                NULLIF(trim(p_customer_name), ''),
                NULLIF(trim(p_customer_phone), ''),
                'active'
            )
            RETURNING id INTO v_session_customer_id;
        END IF;
    END IF;

    -- Retrieve and lock customer record to verify status
    SELECT * INTO v_customer_rec
    FROM public.table_session_customers
    WHERE id = v_session_customer_id
    FOR SHARE;

    IF v_customer_rec IS NULL THEN
        RAISE EXCEPTION 'Customer not found in table session';
    END IF;

    IF v_customer_rec.status <> 'active' THEN
        RAISE EXCEPTION 'Customer "%" has completed ordering (status: %) and cannot place new orders',
            v_customer_rec.customer_label, v_customer_rec.status;
    END IF;

    -- 6. Canonical Customer phone handling (optional)
    IF p_customer_phone IS NOT NULL AND trim(p_customer_phone) <> '' THEN
        v_normalized_phone := public.normalize_indian_phone(p_customer_phone);

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

    -- 8. Generate order number with collision retry loop
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
                notes,
                subtotal,
                total_amount
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
                p_notes,
                0.00,
                0.00
            )
            RETURNING id INTO v_order_id;

            EXIT;
        EXCEPTION WHEN unique_violation THEN
            IF v_attempt = 3 THEN
                RAISE EXCEPTION 'Failed to allocate unique order number after 3 attempts';
            END IF;
        END;
    END LOOP;

    -- 9. Process line items with authoritative prices & add-on support
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
        menu_item_id UUID,
        quantity INTEGER,
        special_instructions TEXT,
        unit_price NUMERIC
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

    -- Update order totals in public.orders
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

    -- 11. Write audit log
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
            'session_customer_id', v_session_customer_id,
            'items_count', v_items_count,
            'total_amount', v_order_total
        )
    );

    -- 12. Return composite response
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

-- Grant permissions for submit_dine_in_order
REVOKE ALL ON FUNCTION public.submit_dine_in_order(UUID, TEXT, TEXT, JSONB, TEXT, UUID, UUID) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_dine_in_order(UUID, TEXT, TEXT, JSONB, TEXT, UUID, UUID) TO authenticated;


-- 4. RPC for Super Admin to create staff users
CREATE OR REPLACE FUNCTION public.admin_create_staff_user(
    p_email TEXT,
    p_password TEXT,
    p_full_name TEXT,
    p_role TEXT,
    p_phone TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, auth, extensions, pg_temp
AS $$
DECLARE
    v_admin_id UUID := auth.uid();
    v_admin_role VARCHAR(20);
    v_new_user_id UUID;
    v_clean_email TEXT := lower(trim(p_email));
    v_clean_name TEXT := trim(p_full_name);
    v_clean_role TEXT := lower(trim(p_role));
    v_clean_phone TEXT := NULLIF(trim(p_phone), '');
    v_encrypted_pw TEXT;
BEGIN
    -- 1. Authorization: Only super_admin can create users
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: authentication required';
    END IF;

    SELECT role INTO v_admin_role
    FROM public.user_profiles
    WHERE id = v_admin_id AND is_active = true;

    IF v_admin_role IS NULL OR v_admin_role <> 'super_admin' THEN
        RAISE EXCEPTION 'Unauthorized: only Super Admin can create staff accounts';
    END IF;

    -- 2. Validation
    IF v_clean_email IS NULL OR v_clean_email = '' OR v_clean_email NOT LIKE '%_@__%.__%' THEN
        RAISE EXCEPTION 'Invalid email address';
    END IF;

    IF p_password IS NULL OR length(p_password) < 6 THEN
        RAISE EXCEPTION 'Password must be at least 6 characters long';
    END IF;

    IF v_clean_name IS NULL OR v_clean_name = '' THEN
        RAISE EXCEPTION 'Full name is required';
    END IF;

    IF v_clean_role NOT IN ('server', 'cashier', 'super_admin') THEN
        RAISE EXCEPTION 'Invalid role. Must be server, cashier, or super_admin';
    END IF;

    -- Check if email already exists
    IF EXISTS (SELECT 1 FROM auth.users WHERE email = v_clean_email) THEN
        RAISE EXCEPTION 'A user with email "%" already exists', v_clean_email;
    END IF;

    -- 3. Create user in auth.users
    v_new_user_id := gen_random_uuid();
    v_encrypted_pw := crypt(p_password, gen_salt('bf', 10));

    INSERT INTO auth.users (
        instance_id,
        id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        raw_app_meta_data,
        raw_user_meta_data,
        is_sso_user,
        is_anonymous,
        created_at,
        updated_at
    ) VALUES (
        '00000000-0000-0000-0000-000000000000',
        v_new_user_id,
        'authenticated',
        'authenticated',
        v_clean_email,
        v_encrypted_pw,
        now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('full_name', v_clean_name),
        false,
        false,
        now(),
        now()
    );

    -- 4. Create identity in auth.identities
    INSERT INTO auth.identities (
        id,
        provider_id,
        user_id,
        identity_data,
        provider,
        last_sign_in_at,
        created_at,
        updated_at
    ) VALUES (
        gen_random_uuid(),
        v_new_user_id::text,
        v_new_user_id,
        jsonb_build_object('sub', v_new_user_id::text, 'email', v_clean_email),
        'email',
        now(),
        now(),
        now()
    );

    -- 5. Create profile in public.user_profiles
    INSERT INTO public.user_profiles (
        id,
        full_name,
        role,
        phone,
        is_active,
        created_at,
        updated_at
    ) VALUES (
        v_new_user_id,
        v_clean_name,
        v_clean_role,
        v_clean_phone,
        true,
        now(),
        now()
    )
    ON CONFLICT (id) DO UPDATE SET
        full_name = EXCLUDED.full_name,
        role = EXCLUDED.role,
        phone = EXCLUDED.phone,
        is_active = true,
        updated_at = now();

    -- 6. Write audit log
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (
        v_admin_id,
        'STAFF_USER_CREATED',
        'user_profile',
        v_new_user_id::text,
        jsonb_build_object(
            'email', v_clean_email,
            'full_name', v_clean_name,
            'role', v_clean_role,
            'created_by', v_admin_id
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'user_id', v_new_user_id,
        'email', v_clean_email,
        'full_name', v_clean_name,
        'role', v_clean_role
    );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_staff_user(TEXT, TEXT, TEXT, TEXT, TEXT) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_staff_user(TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
