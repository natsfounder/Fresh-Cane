-- Migration: 20261009001500_enrich_order_rpcs_with_bill_number.sql
-- Description: Enrich get_active_table_session_details and get_server_today_orders
-- to include bill_number so that server and cashier interfaces consistently show
-- the generated bill number (FC-YYYYMMDD-XXXX) alongside the order number.

-- 1. Enrich get_server_today_orders
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
            'bill_number', (SELECT b.bill_number FROM public.bills b WHERE b.order_id = o.id AND b.status <> 'voided' ORDER BY b.created_at DESC LIMIT 1),
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

-- 2. Enrich get_active_table_session_details
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
                    'bill_number', (SELECT b.bill_number FROM public.bills b WHERE b.order_id = o.id AND b.status <> 'voided' ORDER BY b.created_at DESC LIMIT 1),
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
