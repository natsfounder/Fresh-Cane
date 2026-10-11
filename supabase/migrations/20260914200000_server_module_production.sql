-- =============================================================================
-- Migration: 20260914200000_server_module_production.sql
-- Description: Complete Production Server Module Architecture:
--              1. Drop obsolete 1-order-per-table index
--              2. Create table_sessions & table_session_customers
--              3. Add session & cancellation columns to orders
--              4. Atomic RPCs:
--                 - open_or_get_table_session
--                 - add_customer_to_table_session
--                 - submit_dine_in_order (multi-order / repeat-order aware)
--                 - cancel_server_order (independent order cancellation)
--                 - get_active_table_session_details
--              5. Realtime publication & RLS policies
-- =============================================================================

-- *****************************************************************************
-- SECTION 1: SCHEMA ADJUSTMENTS FOR MULTI-ORDER / MULTI-CUSTOMER TABLES
-- *****************************************************************************

-- 1. Drop obsolete partial unique index that prevented multiple active orders on a table
DROP INDEX IF EXISTS public.idx_unique_active_dine_in_table;

-- 2. Create table_sessions table
CREATE TABLE IF NOT EXISTS public.table_sessions (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    table_id    UUID         NOT NULL REFERENCES public.restaurant_tables(id) ON DELETE RESTRICT,
    status      VARCHAR(20)  NOT NULL DEFAULT 'active',
    opened_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    closed_at   TIMESTAMPTZ  NULL,
    opened_by   UUID         NOT NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
    closed_by   UUID         NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
    notes       TEXT         NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_table_sessions_status CHECK (status IN ('active', 'billing', 'completed', 'cancelled'))
);

-- Exactly one active session per physical table at any time (concurrency protection)
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_active_table_session
    ON public.table_sessions (table_id)
    WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_table_sessions_table ON public.table_sessions (table_id, status);

-- 3. Create table_session_customers table
CREATE TABLE IF NOT EXISTS public.table_session_customers (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id     UUID         NOT NULL REFERENCES public.table_sessions(id) ON DELETE CASCADE,
    customer_id    UUID         NULL REFERENCES public.customers(id) ON DELETE SET NULL,
    customer_label VARCHAR(100) NOT NULL,
    customer_name  VARCHAR(100) NULL,
    customer_phone VARCHAR(10)  NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_session_customers_session ON public.table_session_customers (session_id);

-- 4. Alter orders table to link to session and support order cancellation
ALTER TABLE public.orders 
    ADD COLUMN IF NOT EXISTS session_id UUID NULL REFERENCES public.table_sessions(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS session_customer_id UUID NULL REFERENCES public.table_session_customers(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ NULL,
    ADD COLUMN IF NOT EXISTS cancelled_by UUID NULL REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS cancellation_reason TEXT NULL;

CREATE INDEX IF NOT EXISTS idx_orders_session ON public.orders (session_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_session_customer ON public.orders (session_customer_id, status);

-- *****************************************************************************
-- SECTION 2: ROW LEVEL SECURITY (RLS)
-- *****************************************************************************

ALTER TABLE public.table_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.table_session_customers ENABLE ROW LEVEL SECURITY;

-- Staff roles: server, cashier, super_admin
DROP POLICY IF EXISTS "Staff can read table sessions" ON public.table_sessions;
CREATE POLICY "Staff can read table sessions"
    ON public.table_sessions FOR SELECT
    TO authenticated
    USING (public.is_staff());

DROP POLICY IF EXISTS "Staff can insert table sessions" ON public.table_sessions;
CREATE POLICY "Staff can insert table sessions"
    ON public.table_sessions FOR INSERT
    TO authenticated
    WITH CHECK (public.is_staff());

DROP POLICY IF EXISTS "Staff can update table sessions" ON public.table_sessions;
CREATE POLICY "Staff can update table sessions"
    ON public.table_sessions FOR UPDATE
    TO authenticated
    USING (public.is_staff())
    WITH CHECK (public.is_staff());

DROP POLICY IF EXISTS "Staff can read session customers" ON public.table_session_customers;
CREATE POLICY "Staff can read session customers"
    ON public.table_session_customers FOR SELECT
    TO authenticated
    USING (public.is_staff());

DROP POLICY IF EXISTS "Staff can insert session customers" ON public.table_session_customers;
CREATE POLICY "Staff can insert session customers"
    ON public.table_session_customers FOR INSERT
    TO authenticated
    WITH CHECK (public.is_staff());

DROP POLICY IF EXISTS "Staff can update session customers" ON public.table_session_customers;
CREATE POLICY "Staff can update session customers"
    ON public.table_session_customers FOR UPDATE
    TO authenticated
    USING (public.is_staff())
    WITH CHECK (public.is_staff());

-- *****************************************************************************
-- SECTION 3: ATOMIC RPCs
-- *****************************************************************************

-- 1. open_or_get_table_session
CREATE OR REPLACE FUNCTION public.open_or_get_table_session(p_table_id UUID)
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
    v_session RECORD;
    v_session_id UUID;
    v_customer_id UUID;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: authentication required';
    END IF;

    SELECT role INTO v_role
    FROM public.user_profiles
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR v_role NOT IN ('server', 'cashier', 'super_admin') THEN
        RAISE EXCEPTION 'Unauthorized: caller does not possess staff privileges';
    END IF;

    -- Lock table row
    SELECT * INTO v_table
    FROM public.restaurant_tables
    WHERE id = p_table_id AND is_active = true
    FOR UPDATE;

    IF v_table IS NULL THEN
        RAISE EXCEPTION 'Table not found or inactive';
    END IF;

    -- Check if active session already exists for this table
    SELECT id INTO v_session_id
    FROM public.table_sessions
    WHERE table_id = p_table_id AND status = 'active'
    LIMIT 1;

    IF v_session_id IS NULL THEN
        -- Create new active session
        INSERT INTO public.table_sessions (
            table_id,
            status,
            opened_at,
            opened_by
        )
        VALUES (
            p_table_id,
            'active',
            now(),
            v_actor
        )
        ON CONFLICT (table_id) WHERE status = 'active'
        DO UPDATE SET updated_at = now()
        RETURNING id INTO v_session_id;

        -- Update table status to occupied
        UPDATE public.restaurant_tables
        SET status = 'occupied',
            updated_at = now()
        WHERE id = p_table_id;

        -- Create default "Customer 1"
        INSERT INTO public.table_session_customers (
            session_id,
            customer_label,
            customer_name
        )
        VALUES (
            v_session_id,
            'Customer 1',
            'Customer 1'
        )
        RETURNING id INTO v_customer_id;

        -- Audit log
        INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
        VALUES (
            v_actor,
            'TABLE_SESSION_OPENED',
            'table_session',
            v_session_id::text,
            jsonb_build_object(
                'table_id', p_table_id,
                'table_number', v_table.table_number,
                'session_id', v_session_id
            )
        );
    END IF;

    -- Return complete session details
    RETURN public.get_active_table_session_details(p_table_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.open_or_get_table_session(UUID) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.open_or_get_table_session(UUID) TO authenticated;

-- 2. add_customer_to_table_session
CREATE OR REPLACE FUNCTION public.add_customer_to_table_session(
    p_session_id UUID,
    p_name TEXT DEFAULT NULL,
    p_phone TEXT DEFAULT NULL
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
    v_count INTEGER;
    v_label VARCHAR(100);
    v_canonical_customer_id UUID := NULL;
    v_normalized_phone VARCHAR(10) := NULL;
    v_new_id UUID;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: authentication required';
    END IF;

    SELECT role INTO v_role
    FROM public.user_profiles
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR v_role NOT IN ('server', 'cashier', 'super_admin') THEN
        RAISE EXCEPTION 'Unauthorized: caller does not possess staff privileges';
    END IF;

    -- Verify session is active
    SELECT * INTO v_session
    FROM public.table_sessions
    WHERE id = p_session_id AND status = 'active';

    IF v_session IS NULL THEN
        RAISE EXCEPTION 'Table session not found or not active';
    END IF;

    -- Phone handling (optional)
    IF p_phone IS NOT NULL AND trim(p_phone) <> '' THEN
        v_normalized_phone := public.normalize_indian_phone(p_phone);

        INSERT INTO public.customers (phone, name)
        VALUES (v_normalized_phone, NULLIF(trim(p_name), ''))
        ON CONFLICT (phone) DO UPDATE SET
            name = COALESCE(NULLIF(trim(EXCLUDED.name), ''), public.customers.name),
            updated_at = now()
        RETURNING id INTO v_canonical_customer_id;
    END IF;

    -- Determine label
    IF p_name IS NOT NULL AND trim(p_name) <> '' THEN
        v_label := trim(p_name);
    ELSE
        SELECT count(*) INTO v_count
        FROM public.table_session_customers
        WHERE session_id = p_session_id;

        v_label := 'Customer ' || (v_count + 1);
    END IF;

    INSERT INTO public.table_session_customers (
        session_id,
        customer_id,
        customer_label,
        customer_name,
        customer_phone
    )
    VALUES (
        p_session_id,
        v_canonical_customer_id,
        v_label,
        NULLIF(trim(p_name), ''),
        v_normalized_phone
    )
    RETURNING id INTO v_new_id;

    RETURN jsonb_build_object(
        'id', v_new_id,
        'session_id', p_session_id,
        'customer_label', v_label,
        'customer_name', NULLIF(trim(p_name), ''),
        'customer_phone', v_normalized_phone
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.add_customer_to_table_session(UUID, TEXT, TEXT) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_customer_to_table_session(UUID, TEXT, TEXT) TO authenticated;

-- 3. submit_dine_in_order (Multi-customer & Repeat-order compatible)
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
    v_session RECORD;
    v_session_id UUID := p_session_id;
    v_session_customer_id UUID := p_session_customer_id;
    v_normalized_phone VARCHAR(10) := NULL;
    v_canonical_customer_id UUID := NULL;
    v_order_prefix VARCHAR(10) := 'ORD-';
    v_order_number VARCHAR(35);
    v_order_id UUID;
    v_attempt INTEGER;
    v_item RECORD;
    v_menu_item RECORD;
    v_item_qty INTEGER;
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
        WHERE table_id = p_table_id AND status = 'active'
        LIMIT 1;

        IF v_session_id IS NULL THEN
            -- Automatically open new session
            INSERT INTO public.table_sessions (table_id, status, opened_at, opened_by)
            VALUES (p_table_id, 'active', now(), v_actor)
            ON CONFLICT (table_id) WHERE status = 'active'
            DO UPDATE SET updated_at = now()
            RETURNING id INTO v_session_id;

            UPDATE public.restaurant_tables
            SET status = 'occupied', updated_at = now()
            WHERE id = p_table_id;
        END IF;
    ELSE
        SELECT id INTO v_session_id
        FROM public.table_sessions
        WHERE id = v_session_id AND status = 'active';

        IF v_session_id IS NULL THEN
            RAISE EXCEPTION 'Specified table session is not active';
        END IF;
    END IF;

    -- 5. Customer resolution
    IF v_session_customer_id IS NULL THEN
        SELECT id INTO v_session_customer_id
        FROM public.table_session_customers
        WHERE session_id = v_session_id
        ORDER BY created_at ASC
        LIMIT 1;

        IF v_session_customer_id IS NULL THEN
            INSERT INTO public.table_session_customers (session_id, customer_label, customer_name)
            VALUES (v_session_id, COALESCE(NULLIF(trim(p_customer_name), ''), 'Customer 1'), NULLIF(trim(p_customer_name), ''))
            RETURNING id INTO v_session_customer_id;
        END IF;
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
                RAISE EXCEPTION 'Failed to allocate unique order number after 3 attempts';
            END IF;
        END;
    END LOOP;

    -- 9. Process line items with authoritative prices
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
        v_order_total := v_order_total + (v_item_qty * v_menu_item.base_price);
    END LOOP;

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
            'order_type', 'dine_in',
            'table_id', p_table_id,
            'table_number', v_table.table_number,
            'session_id', v_session_id,
            'session_customer_id', v_session_customer_id,
            'items_count', v_items_count,
            'total_amount', v_order_total
        )
    );

    RETURN jsonb_build_object(
        'order_id', v_order_id,
        'order_number', v_order_number,
        'table_id', p_table_id,
        'table_number', v_table.table_number,
        'session_id', v_session_id,
        'session_customer_id', v_session_customer_id,
        'total_amount', v_order_total
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.submit_dine_in_order(UUID, TEXT, TEXT, JSONB, TEXT, UUID, UUID) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_dine_in_order(UUID, TEXT, TEXT, JSONB, TEXT, UUID, UUID) TO authenticated;

-- 4. cancel_server_order (Independent Order Cancellation)
CREATE OR REPLACE FUNCTION public.cancel_server_order(
    p_order_id UUID,
    p_reason TEXT DEFAULT 'Cancelled by server'
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
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: authentication required';
    END IF;

    SELECT role INTO v_role
    FROM public.user_profiles
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR v_role NOT IN ('server', 'cashier', 'super_admin') THEN
        RAISE EXCEPTION 'Unauthorized: caller does not possess staff privileges';
    END IF;

    -- Lock order row
    SELECT * INTO v_order
    FROM public.orders
    WHERE id = p_order_id
    FOR UPDATE;

    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order not found';
    END IF;

    IF v_order.status = 'cancelled' THEN
        RAISE EXCEPTION 'Order is already cancelled';
    END IF;

    IF v_order.status = 'completed' THEN
        RAISE EXCEPTION 'Cannot cancel completed/settled order';
    END IF;

    -- Update order status to cancelled
    UPDATE public.orders
    SET status = 'cancelled',
        cancelled_at = now(),
        cancelled_by = v_actor,
        cancellation_reason = COALESCE(NULLIF(trim(p_reason), ''), 'Cancelled by server'),
        updated_at = now()
    WHERE id = p_order_id;

    -- Update order line items
    UPDATE public.order_items
    SET status = 'cancelled',
        updated_at = now()
    WHERE order_id = p_order_id;

    -- Audit log
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (
        v_actor,
        'ORDER_CANCELLED',
        'order',
        p_order_id::text,
        jsonb_build_object(
            'order_number', v_order.order_number,
            'table_id', v_order.table_id,
            'session_id', v_order.session_id,
            'reason', p_reason
        )
    );

    RETURN jsonb_build_object(
        'order_id', p_order_id,
        'order_number', v_order.order_number,
        'status', 'cancelled'
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cancel_server_order(UUID, TEXT) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_server_order(UUID, TEXT) TO authenticated;

-- 5. get_active_table_session_details (Aggregated table session details)
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

    SELECT * INTO v_session
    FROM public.table_sessions
    WHERE table_id = p_table_id AND status = 'active'
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

    -- Calculate active total and active orders count for this session
    SELECT 
        COALESCE(SUM(oi.item_total), 0.00),
        COUNT(DISTINCT o.id)
    INTO v_active_total, v_active_orders_count
    FROM public.orders o
    JOIN public.order_items oi ON oi.order_id = o.id
    WHERE o.session_id = v_session.id 
      AND o.status <> 'cancelled'
      AND oi.status <> 'cancelled';

    -- Build customers with their orders
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', sc.id,
            'session_id', sc.session_id,
            'customer_label', sc.customer_label,
            'customer_name', sc.customer_name,
            'customer_phone', sc.customer_phone,
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
            COUNT(CASE WHEN o.status <> 'cancelled' THEN 1 END) AS active_count,
            COALESCE(SUM(CASE WHEN o.status <> 'cancelled' THEN o_items.total ELSE 0 END), 0.00) AS active_total,
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
                    'items_summary', COALESCE(o_items.summary, '')
                ) ORDER BY o.created_at DESC
            ) AS orders_json
        FROM public.orders o
        LEFT JOIN LATERAL (
            SELECT 
                SUM(oi.item_total) AS total,
                SUM(oi.quantity) AS cnt,
                string_agg(oi.item_name_snapshot || ' × ' || oi.quantity, ', ') AS summary
            FROM public.order_items oi
            WHERE oi.order_id = o.id
        ) o_items ON true
        WHERE o.session_customer_id = sc.id
    ) ord_summary ON true
    WHERE sc.session_id = v_session.id;

    RETURN jsonb_build_object(
        'table_id', v_table.id,
        'table_number', v_table.table_number,
        'seating_capacity', v_table.seating_capacity,
        'table_status', v_table.status,
        'session_id', v_session.id,
        'status', 'active',
        'opened_at', v_session.opened_at,
        'customers', COALESCE(v_customers, '[]'::jsonb),
        'active_total', v_active_total,
        'active_orders_count', v_active_orders_count
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_active_table_session_details(UUID) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_active_table_session_details(UUID) TO authenticated;

-- *****************************************************************************
-- SECTION 4: REALTIME CONFIGURATION
-- *****************************************************************************

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'table_sessions'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.table_sessions;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'table_session_customers'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.table_session_customers;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'orders'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
    END IF;
END;
$$;

-- 6. close_table_session (Closes table session and releases table to available)
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
BEGIN
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL OR v_role NOT IN ('server', 'cashier', 'super_admin') THEN
        RAISE EXCEPTION 'Unauthorized: only staff can close table sessions';
    END IF;

    UPDATE public.table_sessions
    SET status = 'completed', closed_at = now(), closed_by = v_actor
    WHERE table_id = p_table_id AND status = 'active';

    UPDATE public.restaurant_tables
    SET status = 'available', updated_at = now()
    WHERE id = p_table_id;

    RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.close_table_session(UUID, TEXT) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.close_table_session(UUID, TEXT) TO authenticated;
