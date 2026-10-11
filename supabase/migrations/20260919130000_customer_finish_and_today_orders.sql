-- =============================================================================
-- Migration: 20260919130000_customer_finish_and_today_orders.sql
-- Description: Phase 2 Database Implementation:
--              1. Alter table_session_customers:
--                 - add status ('active', 'finished', 'billed', 'closed')
--                 - add finished_at, finished_by
--                 - index on (session_id, status)
--              2. Update unique index on table_sessions for active/billing sessions
--              3. RPC finish_table_session_customer(p_customer_id UUID)
--                 - FOR UPDATE locking
--                 - active -> finished transition
--                 - idempotent if already finished (no duplicate audit)
--                 - reject if billed or closed
--                 - all-finished rule: table_sessions.status -> 'billing' (table remains 'occupied')
--                 - audit_log CUSTOMER_FINISHED
--              4. Update submit_dine_in_order:
--                 - Guard: reject orders if customer status <> 'active'
--              5. Update get_active_table_session_details:
--                 - include status, finished_at, finished_by in customer JSON
--                 - handle sessions in 'active' or 'billing'
--              6. Update open_or_get_table_session & close_table_session:
--                 - support 'billing' session status
--              7. RPC get_server_today_orders(p_server_id UUID, p_date DATE)
--                 - server isolation: auth.uid() enforced for servers
--                 - Asia/Kolkata (IST) date filtering
--                 - cancelled orders contribute ₹0 to total_amount
-- =============================================================================

-- *****************************************************************************
-- SECTION 1: SCHEMA ADJUSTMENTS FOR CUSTOMER STATUS
-- *****************************************************************************

ALTER TABLE public.table_session_customers
    ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'active',
    ADD COLUMN IF NOT EXISTS finished_at TIMESTAMPTZ NULL,
    ADD COLUMN IF NOT EXISTS finished_by UUID NULL REFERENCES public.user_profiles(id) ON DELETE SET NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'chk_table_session_customers_status'
    ) THEN
        ALTER TABLE public.table_session_customers
            ADD CONSTRAINT chk_table_session_customers_status 
            CHECK (status IN ('active', 'finished', 'billed', 'closed'));
    END IF;
END;
$$;

UPDATE public.table_session_customers
SET status = 'active'
WHERE status IS NULL;

CREATE INDEX IF NOT EXISTS idx_session_customers_status 
    ON public.table_session_customers (session_id, status);

DROP INDEX IF EXISTS public.idx_unique_active_table_session;
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_open_table_session 
    ON public.table_sessions (table_id) 
    WHERE status IN ('active', 'billing');

-- *****************************************************************************
-- SECTION 2: RPC finish_table_session_customer
-- *****************************************************************************

CREATE OR REPLACE FUNCTION public.finish_table_session_customer(p_customer_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_customer RECORD;
    v_session RECORD;
    v_table RECORD;
    v_active_count INTEGER;
    v_finished_at TIMESTAMPTZ;
    v_finished_by UUID;
    v_already_finished BOOLEAN := false;
BEGIN
    -- 1. Verify authentication
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: authentication required';
    END IF;

    -- 2. Verify staff role
    SELECT role INTO v_role
    FROM public.user_profiles
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR v_role NOT IN ('server', 'cashier', 'super_admin') THEN
        RAISE EXCEPTION 'Unauthorized: caller does not possess staff privileges';
    END IF;

    -- 3. Lock customer row with FOR UPDATE
    SELECT * INTO v_customer
    FROM public.table_session_customers
    WHERE id = p_customer_id
    FOR UPDATE;

    IF v_customer IS NULL THEN
        RAISE EXCEPTION 'Customer not found';
    END IF;

    -- 4. Retrieve associated table session
    SELECT * INTO v_session
    FROM public.table_sessions
    WHERE id = v_customer.session_id
    FOR UPDATE;

    -- 5. Verify session is still active/billing
    IF v_session IS NULL OR v_session.status NOT IN ('active', 'billing') THEN
        RAISE EXCEPTION 'Table session not found or inactive';
    END IF;

    -- 6. Lock table row to ensure consistency
    SELECT * INTO v_table
    FROM public.restaurant_tables
    WHERE id = v_session.table_id;

    -- 7. Inspect current customer status
    IF v_customer.status = 'active' THEN
        -- Perform active -> finished transition
        v_finished_at := now();
        v_finished_by := v_actor;

        UPDATE public.table_session_customers
        SET status = 'finished',
            finished_at = v_finished_at,
            finished_by = v_finished_by,
            updated_at = now()
        WHERE id = p_customer_id;

        -- Audit log for successful first finish transition
        INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
        VALUES (
            v_actor,
            'CUSTOMER_FINISHED',
            'table_session_customer',
            p_customer_id::text,
            jsonb_build_object(
                'customer_id', p_customer_id,
                'customer_label', v_customer.customer_label,
                'customer_name', v_customer.customer_name,
                'session_id', v_session.id,
                'table_id', v_session.table_id,
                'table_number', v_table.table_number,
                'finished_at', v_finished_at,
                'finished_by', v_finished_by
            )
        );

    ELSIF v_customer.status = 'finished' THEN
        -- Idempotent: return authoritative existing state without duplicating audit event
        v_already_finished := true;
        v_finished_at := v_customer.finished_at;
        v_finished_by := v_customer.finished_by;

    ELSIF v_customer.status IN ('billed', 'closed') THEN
        -- Terminal states cannot be altered by Server
        RAISE EXCEPTION 'Customer "%" is already % and cannot be modified',
            v_customer.customer_label, v_customer.status;
    ELSE
        RAISE EXCEPTION 'Unknown customer status: %', v_customer.status;
    END IF;

    -- 8. All-customers-finished check
    SELECT COUNT(*) INTO v_active_count
    FROM public.table_session_customers
    WHERE session_id = v_session.id
      AND status = 'active';

    IF v_active_count = 0 AND v_session.status = 'active' THEN
        -- Transition table session: active -> billing
        -- CRITICAL: Physical table restaurant_tables.status remains 'occupied'!
        UPDATE public.table_sessions
        SET status = 'billing',
            updated_at = now()
        WHERE id = v_session.id;

        -- Audit log for session entering billing queue
        INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
        VALUES (
            v_actor,
            'TABLE_SESSION_BILLING_READY',
            'table_session',
            v_session.id::text,
            jsonb_build_object(
                'session_id', v_session.id,
                'table_id', v_session.table_id,
                'table_number', v_table.table_number,
                'reason', 'All customers finished ordering'
            )
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'customer_id', p_customer_id,
        'customer_label', v_customer.customer_label,
        'status', 'finished',
        'finished_at', v_finished_at,
        'finished_by', v_finished_by,
        'session_id', v_session.id,
        'session_status', (SELECT status FROM public.table_sessions WHERE id = v_session.id),
        'all_finished', (v_active_count = 0),
        'already_finished', v_already_finished
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.finish_table_session_customer(UUID) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.finish_table_session_customer(UUID) TO authenticated;

-- *****************************************************************************
-- SECTION 3: UPDATE submit_dine_in_order WITH CUSTOMER STATUS GUARD
-- *****************************************************************************

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
            -- Automatically open new session
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

    -- 5. Customer resolution & Database-level Customer Status Guard
    IF v_session_customer_id IS NULL THEN
        SELECT id INTO v_session_customer_id
        FROM public.table_session_customers
        WHERE session_id = v_session_id AND status = 'active'
        ORDER BY created_at ASC
        LIMIT 1;

        IF v_session_customer_id IS NULL THEN
            -- Check if any customers exist in this session
            IF EXISTS (SELECT 1 FROM public.table_session_customers WHERE session_id = v_session_id) THEN
                RAISE EXCEPTION 'All customers in this table session have finished ordering. Add a new customer to place an order.';
            ELSE
                INSERT INTO public.table_session_customers (session_id, customer_label, customer_name, status)
                VALUES (v_session_id, COALESCE(NULLIF(trim(p_customer_name), ''), 'Customer 1'), NULLIF(trim(p_customer_name), ''), 'active')
                RETURNING id INTO v_session_customer_id;
            END IF;
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

    -- DATABASE-LEVEL GUARD: Only 'active' customers may place orders
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

-- *****************************************************************************
-- SECTION 4: UPDATE get_active_table_session_details WITH CUSTOMER STATUS FIELDS
-- *****************************************************************************

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

    -- Build customers with their status, finished metadata, and orders
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
        'status', v_session.status,
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
-- SECTION 5: UPDATE open_or_get_table_session, add_customer_to_table_session & close_table_session
-- *****************************************************************************

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

    -- Verify session is active or billing
    SELECT * INTO v_session
    FROM public.table_sessions
    WHERE id = p_session_id AND status IN ('active', 'billing');

    IF v_session IS NULL THEN
        RAISE EXCEPTION 'Table session not found or not active';
    END IF;

    -- If session was in billing, reactivate it since an active customer is joining
    IF v_session.status = 'billing' THEN
        UPDATE public.table_sessions
        SET status = 'active', updated_at = now()
        WHERE id = p_session_id;
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
        customer_phone,
        status
    )
    VALUES (
        p_session_id,
        v_canonical_customer_id,
        v_label,
        NULLIF(trim(p_name), ''),
        v_normalized_phone,
        'active'
    )
    RETURNING id INTO v_new_id;

    RETURN jsonb_build_object(
        'id', v_new_id,
        'session_id', p_session_id,
        'customer_label', v_label,
        'customer_name', NULLIF(trim(p_name), ''),
        'customer_phone', v_normalized_phone,
        'status', 'active',
        'finished_at', NULL,
        'finished_by', NULL
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.add_customer_to_table_session(UUID, TEXT, TEXT) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_customer_to_table_session(UUID, TEXT, TEXT) TO authenticated;

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

    -- Check if active or billing session already exists for this table
    SELECT id INTO v_session_id
    FROM public.table_sessions
    WHERE table_id = p_table_id AND status IN ('active', 'billing')
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
        ON CONFLICT (table_id) WHERE status IN ('active', 'billing')
        DO UPDATE SET updated_at = now()
        RETURNING id INTO v_session_id;

        -- Update table status to occupied
        UPDATE public.restaurant_tables
        SET status = 'occupied',
            updated_at = now()
        WHERE id = p_table_id;

        -- Create default "Customer 1" with status = 'active'
        INSERT INTO public.table_session_customers (
            session_id,
            customer_label,
            customer_name,
            status
        )
        VALUES (
            v_session_id,
            'Customer 1',
            'Customer 1',
            'active'
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
    SET status = 'completed', closed_at = now(), closed_by = v_actor, updated_at = now()
    WHERE table_id = p_table_id AND status IN ('active', 'billing');

    UPDATE public.restaurant_tables
    SET status = 'available', updated_at = now()
    WHERE id = p_table_id;

    RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.close_table_session(UUID, TEXT) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.close_table_session(UUID, TEXT) TO authenticated;

-- *****************************************************************************
-- SECTION 6: RPC get_server_today_orders (SERVER ISOLATION & IST BUSINESS DAY)
-- *****************************************************************************

CREATE OR REPLACE FUNCTION public.get_server_today_orders(
    p_server_id UUID DEFAULT NULL,
    p_date DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_target_server_id UUID;
    v_target_date DATE;
    v_orders JSONB := '[]'::jsonb;
BEGIN
    -- 1. Verify authentication
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: authentication required';
    END IF;

    -- 2. Verify staff role
    SELECT role INTO v_role
    FROM public.user_profiles
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR v_role NOT IN ('server', 'cashier', 'super_admin') THEN
        RAISE EXCEPTION 'Unauthorized: caller does not possess staff privileges';
    END IF;

    -- 3. SERVER ISOLATION: A server cannot request another server's orders
    IF v_role = 'server' THEN
        IF p_server_id IS NOT NULL AND p_server_id <> v_actor THEN
            RAISE EXCEPTION 'Unauthorized: servers may only view their own order history';
        END IF;
        v_target_server_id := v_actor;
    ELSE
        -- Cashier or Super Admin can inspect specified server or default to themselves
        v_target_server_id := COALESCE(p_server_id, v_actor);
    END IF;

    -- 4. BUSINESS-DAY FILTER: Asia/Kolkata (IST = UTC+05:30)
    -- Documented Expression: (o.created_at AT TIME ZONE 'Asia/Kolkata')::date = v_target_date
    v_target_date := COALESCE(p_date, (now() AT TIME ZONE 'Asia/Kolkata')::date);

    -- 5. Query orders with snapshots and cancellation ₹0 rule
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'order_id', o.id,
            'order_number', o.order_number,
            'table_id', o.table_id,
            'table_number', t.table_number,
            'session_id', o.session_id,
            'customer_id', sc.id,
            'customer_name', COALESCE(sc.customer_name, sc.customer_label, o.customer_name, 'Customer'),
            'customer_phone', COALESCE(sc.customer_phone, o.customer_phone),
            'customer_status', COALESCE(sc.status, 'active'),
            'order_status', o.status,
            'total_amount', CASE WHEN o.status = 'cancelled' THEN 0.00 ELSE COALESCE(ord_items.billable_total, 0.00) END,
            'raw_amount', COALESCE(ord_items.raw_total, 0.00),
            'items_count', COALESCE(ord_items.items_count, 0),
            'items_summary', COALESCE(ord_items.items_summary, ''),
            'created_at', o.created_at,
            'cancelled_at', o.cancelled_at,
            'cancellation_reason', o.cancellation_reason
        ) ORDER BY o.created_at DESC
    ), '[]'::jsonb)
    INTO v_orders
    FROM public.orders o
    JOIN public.restaurant_tables t ON t.id = o.table_id
    LEFT JOIN public.table_session_customers sc ON sc.id = o.session_customer_id
    LEFT JOIN LATERAL (
        SELECT 
            COALESCE(SUM(CASE WHEN oi.status <> 'cancelled' THEN oi.item_total ELSE 0 END), 0.00) AS billable_total,
            COALESCE(SUM(oi.item_total), 0.00) AS raw_total,
            COALESCE(SUM(oi.quantity), 0)::INTEGER AS items_count,
            COALESCE(string_agg(oi.item_name_snapshot || ' × ' || oi.quantity, ', '), '') AS items_summary
        FROM public.order_items oi
        WHERE oi.order_id = o.id
    ) ord_items ON true
    WHERE o.server_id = v_target_server_id
      AND (o.created_at AT TIME ZONE 'Asia/Kolkata')::date = v_target_date;

    RETURN v_orders;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_server_today_orders(UUID, DATE) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_server_today_orders(UUID, DATE) TO authenticated;
