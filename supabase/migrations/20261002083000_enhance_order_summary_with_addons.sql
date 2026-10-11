-- =============================================================================
-- Migration: 20261002083000_enhance_order_summary_with_addons.sql
-- Description:
--   Enhance get_active_table_session_details RPC so that order items summary
--   includes special instructions and add-ons (e.g. "+Fresh Ginger (+₹10)")
--   making itemized calculations completely transparent in Table Context / Order History.
-- =============================================================================

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

REVOKE ALL ON FUNCTION public.get_active_table_session_details(UUID) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_active_table_session_details(UUID) TO authenticated;
