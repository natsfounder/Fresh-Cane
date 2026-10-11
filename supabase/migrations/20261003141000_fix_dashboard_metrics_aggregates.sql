-- =============================================================================
-- Migration: 20261003141000_fix_dashboard_metrics_aggregates.sql
-- Description:
--   Fix subquery grouping in get_admin_dashboard_metrics to prevent
--   nested aggregate function calls in PostgreSQL.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_admin_dashboard_metrics(
    p_start_date DATE DEFAULT CURRENT_DATE,
    p_end_date DATE DEFAULT CURRENT_DATE
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
    v_assigned_roles TEXT[];
    v_total_sales NUMERIC(10,2) := 0.00;
    v_total_bills INTEGER := 0;
    v_total_discounts NUMERIC(10,2) := 0.00;
    v_net_revenue NUMERIC(10,2) := 0.00;
    v_occupied_tables INTEGER := 0;
    v_total_tables INTEGER := 0;
    v_active_orders INTEGER := 0;
    v_billing_orders INTEGER := 0;
    v_cancelled_orders INTEGER := 0;
    v_total_products INTEGER := 0;
    v_active_products INTEGER := 0;
    v_total_categories INTEGER := 0;
    v_active_servers INTEGER := 0;
    v_payment_breakdown JSONB := '[]'::jsonb;
    v_sales_trend JSONB := '[]'::jsonb;
    v_recent_bills JSONB := '[]'::jsonb;
BEGIN
    -- 1. Authorization check
    SELECT role, assigned_roles INTO v_role, v_assigned_roles
    FROM public.user_profiles
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR (
        v_role NOT IN ('super_admin', 'cashier') 
        AND NOT ('super_admin' = ANY(v_assigned_roles) OR 'cashier' = ANY(v_assigned_roles))
    ) THEN
        RAISE EXCEPTION 'Unauthorized: access restricted to admin';
    END IF;

    -- 2. Sales metrics for selected date range
    SELECT 
        COALESCE(SUM(final_amount), 0.00),
        COUNT(*),
        COALESCE(SUM(discount_amount), 0.00),
        COALESCE(SUM(subtotal_amount), 0.00)
    INTO v_total_sales, v_total_bills, v_total_discounts, v_net_revenue
    FROM public.bills
    WHERE business_date >= p_start_date AND business_date <= p_end_date
      AND status = 'paid';

    -- 3. Operations metrics (current live state)
    SELECT COUNT(*) INTO v_total_tables FROM public.restaurant_tables WHERE is_active = true;
    SELECT COUNT(*) INTO v_occupied_tables FROM public.restaurant_tables 
    WHERE is_active = true AND status IN ('occupied', 'billing');

    SELECT COUNT(*) INTO v_active_orders FROM public.orders WHERE status IN ('open', 'served');
    SELECT COUNT(*) INTO v_billing_orders FROM public.table_sessions WHERE status = 'billing';
    SELECT COUNT(*) INTO v_cancelled_orders FROM public.orders 
    WHERE status = 'cancelled' AND created_at::date >= p_start_date AND created_at::date <= p_end_date;

    SELECT COUNT(*) INTO v_active_servers FROM public.user_profiles 
    WHERE is_active = true AND (role = 'server' OR 'server' = ANY(assigned_roles));

    -- 4. Catalog metrics
    SELECT COUNT(*) INTO v_total_products FROM public.menu_items;
    SELECT COUNT(*) INTO v_active_products FROM public.menu_items WHERE is_available = true AND is_active = true;
    SELECT COUNT(*) INTO v_total_categories FROM public.categories WHERE is_active = true;

    -- 5. Payment method breakdown for selected date range
    SELECT jsonb_agg(
        jsonb_build_object(
            'method', pmt.payment_method,
            'count', pmt.payment_count,
            'amount', pmt.total_amount
        )
    ) INTO v_payment_breakdown
    FROM (
        SELECT p.payment_method, COUNT(*) AS payment_count, COALESCE(SUM(p.amount), 0.00) AS total_amount
        FROM public.payments p
        JOIN public.bills b ON b.id = p.bill_id
        WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
          AND p.status = 'completed'
        GROUP BY p.payment_method
    ) pmt;

    -- 6. Daily sales trend within selected range (grouped by business_date)
    SELECT jsonb_agg(
        jsonb_build_object(
            'date', trend.business_date,
            'bills_count', trend.bills_count,
            'total_sales', trend.total_sales
        ) ORDER BY trend.business_date ASC
    ) INTO v_sales_trend
    FROM (
        SELECT b.business_date, COUNT(*) AS bills_count, COALESCE(SUM(b.final_amount), 0.00) AS total_sales
        FROM public.bills b
        WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
          AND b.status = 'paid'
        GROUP BY b.business_date
    ) trend;

    -- 7. Recent 5 settled bills
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', b.id,
            'bill_number', b.bill_number,
            'customer_name', COALESCE(b.customer_name_snapshot, 'Walk-In'),
            'final_amount', b.final_amount,
            'created_at', b.created_at,
            'status', b.status
        ) ORDER BY b.created_at DESC
    ) INTO v_recent_bills
    FROM (
        SELECT * FROM public.bills 
        WHERE status = 'paid' 
        ORDER BY created_at DESC 
        LIMIT 5
    ) b;

    RETURN jsonb_build_object(
        'start_date', p_start_date,
        'end_date', p_end_date,
        'total_sales', v_total_sales,
        'total_bills', v_total_bills,
        'total_discounts', v_total_discounts,
        'net_revenue', v_net_revenue,
        'occupied_tables', v_occupied_tables,
        'total_tables', v_total_tables,
        'active_orders', v_active_orders,
        'billing_orders', v_billing_orders,
        'cancelled_orders', v_cancelled_orders,
        'active_servers', v_active_servers,
        'total_products', v_total_products,
        'active_products', v_active_products,
        'total_categories', v_total_categories,
        'payment_breakdown', COALESCE(v_payment_breakdown, '[]'::jsonb),
        'sales_trend', COALESCE(v_sales_trend, '[]'::jsonb),
        'recent_bills', COALESCE(v_recent_bills, '[]'::jsonb)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_admin_dashboard_metrics(DATE, DATE) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_admin_dashboard_metrics(DATE, DATE) TO authenticated;
