-- =============================================================================
-- Migration: 20261003140000_admin_module_foundation_and_reports.sql
-- Description:
--   1. Create public.offers table for promotions and discounts.
--   2. Ensure RLS policies allow super_admin full management on:
--      categories, menu_items, menu_addons, offers, restaurant_tables, store_settings.
--   3. Create RPC public.get_admin_dashboard_metrics(p_start_date DATE, p_end_date DATE)
--      providing unified, consistent KPI metrics for the Admin Dashboard.
--   4. Create RPC public.get_admin_report_data(p_report_type TEXT, p_start_date DATE, p_end_date DATE)
--      providing accurate, single-source-of-truth datasets for all 9 required report types.
-- =============================================================================

-- 1. Create public.offers table
CREATE TABLE IF NOT EXISTS public.offers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(150) NOT NULL,
    code VARCHAR(50) UNIQUE,
    description TEXT,
    discount_type VARCHAR(20) NOT NULL DEFAULT 'percentage' CHECK (discount_type IN ('percentage', 'flat')),
    discount_value NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    min_order_amount NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    max_discount_amount NUMERIC(10,2),
    valid_from DATE DEFAULT CURRENT_DATE,
    valid_until DATE,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed initial sample offers if empty
INSERT INTO public.offers (name, code, description, discount_type, discount_value, min_order_amount, max_discount_amount, is_active)
VALUES 
    ('Welcome Discount', 'WELCOME10', '10% off on minimum bill of ₹100', 'percentage', 10.00, 100.00, 50.00, true),
    ('Festive Flat Discount', 'FESTIVE25', 'Flat ₹25 off on orders above ₹200', 'flat', 25.00, 200.00, 25.00, true)
ON CONFLICT (code) DO NOTHING;

-- Enable RLS on offers
ALTER TABLE public.offers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view active offers" ON public.offers;
CREATE POLICY "Anyone can view active offers" ON public.offers
    FOR SELECT TO authenticated, anon USING (is_active = true);

DROP POLICY IF EXISTS "Super admin full management on offers" ON public.offers;
CREATE POLICY "Super admin full management on offers" ON public.offers
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles
            WHERE id = auth.uid() AND is_active = true 
              AND (role = 'super_admin' OR 'super_admin' = ANY(assigned_roles))
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_profiles
            WHERE id = auth.uid() AND is_active = true 
              AND (role = 'super_admin' OR 'super_admin' = ANY(assigned_roles))
        )
    );

GRANT ALL ON public.offers TO authenticated;
GRANT SELECT ON public.offers TO anon;

-- Ensure super_admin full management on categories, menu_items, menu_addons, restaurant_tables, store_settings
DROP POLICY IF EXISTS "Super admin full management on categories" ON public.categories;
CREATE POLICY "Super admin full management on categories" ON public.categories
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles
            WHERE id = auth.uid() AND is_active = true 
              AND (role = 'super_admin' OR 'super_admin' = ANY(assigned_roles))
        )
    );

DROP POLICY IF EXISTS "Super admin full management on menu_items" ON public.menu_items;
CREATE POLICY "Super admin full management on menu_items" ON public.menu_items
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles
            WHERE id = auth.uid() AND is_active = true 
              AND (role = 'super_admin' OR 'super_admin' = ANY(assigned_roles))
        )
    );

DROP POLICY IF EXISTS "Super admin full management on menu_addons" ON public.menu_addons;
CREATE POLICY "Super admin full management on menu_addons" ON public.menu_addons
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles
            WHERE id = auth.uid() AND is_active = true 
              AND (role = 'super_admin' OR 'super_admin' = ANY(assigned_roles))
        )
    );

DROP POLICY IF EXISTS "Super admin full management on restaurant_tables" ON public.restaurant_tables;
CREATE POLICY "Super admin full management on restaurant_tables" ON public.restaurant_tables
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles
            WHERE id = auth.uid() AND is_active = true 
              AND (role = 'super_admin' OR 'super_admin' = ANY(assigned_roles))
        )
    );

DROP POLICY IF EXISTS "Super admin full management on store_settings" ON public.store_settings;
CREATE POLICY "Super admin full management on store_settings" ON public.store_settings
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles
            WHERE id = auth.uid() AND is_active = true 
              AND (role = 'super_admin' OR 'super_admin' = ANY(assigned_roles))
        )
    );

DROP POLICY IF EXISTS "Super admin read audit_logs" ON public.audit_logs;
CREATE POLICY "Super admin read audit_logs" ON public.audit_logs
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles
            WHERE id = auth.uid() AND is_active = true 
              AND (role = 'super_admin' OR 'super_admin' = ANY(assigned_roles))
        )
    );

GRANT ALL ON public.categories TO authenticated;
GRANT ALL ON public.menu_items TO authenticated;
GRANT ALL ON public.menu_addons TO authenticated;
GRANT ALL ON public.restaurant_tables TO authenticated;
GRANT ALL ON public.store_settings TO authenticated;
GRANT SELECT ON public.audit_logs TO authenticated;


-- =============================================================================
-- 2. RPC: get_admin_dashboard_metrics
-- Returns aggregated dashboard metrics across sales, tables, catalog, orders
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
            'method', p.payment_method,
            'count', COUNT(*),
            'amount', COALESCE(SUM(p.amount), 0.00)
        )
    ) INTO v_payment_breakdown
    FROM public.payments p
    JOIN public.bills b ON b.id = p.bill_id
    WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
      AND p.status = 'completed'
    GROUP BY p.payment_method;

    -- 6. Daily sales trend within selected range (grouped by business_date)
    SELECT jsonb_agg(
        jsonb_build_object(
            'date', b.business_date,
            'bills_count', COUNT(*),
            'total_sales', COALESCE(SUM(b.final_amount), 0.00)
        ) ORDER BY b.business_date ASC
    ) INTO v_sales_trend
    FROM public.bills b
    WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
      AND b.status = 'paid'
    GROUP BY b.business_date;

    -- 7. Recent 5 settled bills
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', b.id,
            'bill_number', b.bill_number,
            'customer_name', b.customer_name_snapshot,
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


-- =============================================================================
-- 3. RPC: get_admin_report_data
-- Single Source of Truth for all 9 Fresh Cane Report Types
-- Supported Types:
--   'sales'         : Itemized bills & orders with discount/tax/payments
--   'product'       : Product-wise quantity, gross, discount, net revenue
--   'category'      : Category-wise quantity sold and total revenue
--   'server'        : Factual server order count & sales totals
--   'payment'       : Payment method breakdown (Cash, UPI, Card)
--   'table'         : Table-wise sessions, order count & revenue
--   'order_type'    : Dine-in vs Parcel revenue & volume
--   'discount'      : Discounted bills, discounts given, net sales
--   'cancellation'  : Cancelled orders/items, voided bills, audit info
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_admin_report_data(
    p_report_type TEXT,
    p_start_date DATE,
    p_end_date DATE
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
    v_data JSONB := '[]'::jsonb;
BEGIN
    -- 1. Authorization check
    SELECT role, assigned_roles INTO v_role, v_assigned_roles
    FROM public.user_profiles
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR (
        v_role NOT IN ('super_admin', 'cashier') 
        AND NOT ('super_admin' = ANY(v_assigned_roles) OR 'cashier' = ANY(v_assigned_roles))
    ) THEN
        RAISE EXCEPTION 'Unauthorized: report access restricted to admin';
    END IF;

    -- 2. Dispatch based on report type
    CASE lower(trim(p_report_type))

        -- ─── 1. SALES REPORT ────────────────────────────────────────────────
        WHEN 'sales' THEN
            SELECT jsonb_agg(
                jsonb_build_object(
                    'bill_number', b.bill_number,
                    'business_date', b.business_date,
                    'created_at', b.created_at,
                    'order_type', o.order_type,
                    'table_number', t.table_number,
                    'customer_name', COALESCE(b.customer_name_snapshot, 'Walk-In'),
                    'customer_phone', b.customer_phone_snapshot,
                    'subtotal', b.subtotal_amount,
                    'discount', b.discount_amount,
                    'tax', b.tax_amount,
                    'round_off', b.round_off_amount,
                    'total', b.final_amount,
                    'status', b.status,
                    'payment_method', (
                        SELECT string_agg(DISTINCT p.payment_method, ', ')
                        FROM public.payments p 
                        WHERE p.bill_id = b.id AND p.status = 'completed'
                    )
                ) ORDER BY b.created_at DESC
            ) INTO v_data
            FROM public.bills b
            JOIN public.orders o ON o.id = b.order_id
            LEFT JOIN public.restaurant_tables t ON t.id = o.table_id
            WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
              AND b.status = 'paid';

        -- ─── 2. PRODUCT-WISE SALES ──────────────────────────────────────────
        WHEN 'product' THEN
            SELECT jsonb_agg(
                jsonb_build_object(
                    'product_name', oi.item_name_snapshot,
                    'category_name', COALESCE(oi.category_name_snapshot, 'Uncategorized'),
                    'quantity_sold', SUM(oi.quantity),
                    'gross_sales', SUM(oi.item_total),
                    'avg_price', ROUND(AVG(oi.unit_price_snapshot), 2),
                    'orders_count', COUNT(DISTINCT oi.order_id)
                ) ORDER BY SUM(oi.item_total) DESC
            ) INTO v_data
            FROM public.order_items oi
            JOIN public.orders o ON o.id = oi.order_id
            JOIN public.bills b ON b.order_id = o.id
            WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
              AND oi.status <> 'cancelled'
              AND b.status = 'paid'
            GROUP BY oi.item_name_snapshot, oi.category_name_snapshot;

        -- ─── 3. CATEGORY-WISE SALES ─────────────────────────────────────────
        WHEN 'category' THEN
            SELECT jsonb_agg(
                jsonb_build_object(
                    'category_name', COALESCE(oi.category_name_snapshot, 'Standard Menu'),
                    'quantity_sold', SUM(oi.quantity),
                    'total_revenue', SUM(oi.item_total),
                    'items_count', COUNT(DISTINCT oi.item_name_snapshot)
                ) ORDER BY SUM(oi.item_total) DESC
            ) INTO v_data
            FROM public.order_items oi
            JOIN public.orders o ON o.id = oi.order_id
            JOIN public.bills b ON b.order_id = o.id
            WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
              AND oi.status <> 'cancelled'
              AND b.status = 'paid'
            GROUP BY oi.category_name_snapshot;

        -- ─── 4. SERVER-WISE SALES ───────────────────────────────────────────
        WHEN 'server' THEN
            SELECT jsonb_agg(
                jsonb_build_object(
                    'server_name', COALESCE(u.full_name, 'Direct Cashier'),
                    'server_role', u.role,
                    'orders_served', COUNT(DISTINCT o.id),
                    'total_revenue', COALESCE(SUM(b.final_amount), 0.00),
                    'bills_count', COUNT(DISTINCT b.id)
                ) ORDER BY COALESCE(SUM(b.final_amount), 0.00) DESC
            ) INTO v_data
            FROM public.bills b
            JOIN public.orders o ON o.id = b.order_id
            LEFT JOIN public.user_profiles u ON u.id = o.server_id
            WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
              AND b.status = 'paid'
            GROUP BY u.full_name, u.role;

        -- ─── 5. PAYMENT-WISE REPORT ─────────────────────────────────────────
        WHEN 'payment' THEN
            SELECT jsonb_agg(
                jsonb_build_object(
                    'payment_method', p.payment_method,
                    'transaction_count', COUNT(*),
                    'total_collected', SUM(p.amount),
                    'avg_ticket_size', ROUND(AVG(p.amount), 2)
                ) ORDER BY SUM(p.amount) DESC
            ) INTO v_data
            FROM public.payments p
            JOIN public.bills b ON b.id = p.bill_id
            WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
              AND p.status = 'completed'
            GROUP BY p.payment_method;

        -- ─── 6. TABLE-WISE REPORT ───────────────────────────────────────────
        WHEN 'table' THEN
            SELECT jsonb_agg(
                jsonb_build_object(
                    'table_number', COALESCE(t.table_number, 'Takeaway / Parcel'),
                    'seating_capacity', t.seating_capacity,
                    'bills_count', COUNT(DISTINCT b.id),
                    'total_revenue', COALESCE(SUM(b.final_amount), 0.00),
                    'sessions_count', COUNT(DISTINCT o.session_id)
                ) ORDER BY COALESCE(SUM(b.final_amount), 0.00) DESC
            ) INTO v_data
            FROM public.bills b
            JOIN public.orders o ON o.id = b.order_id
            LEFT JOIN public.restaurant_tables t ON t.id = o.table_id
            WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
              AND b.status = 'paid'
            GROUP BY t.table_number, t.seating_capacity;

        -- ─── 7. ORDER TYPE REPORT (Dine-In vs Parcel) ────────────────────────
        WHEN 'order_type' THEN
            SELECT jsonb_agg(
                jsonb_build_object(
                    'order_type', CASE WHEN o.order_type = 'parcel' THEN 'Parcel / Takeaway' ELSE 'Dine-In' END,
                    'orders_count', COUNT(DISTINCT o.id),
                    'bills_count', COUNT(DISTINCT b.id),
                    'total_revenue', COALESCE(SUM(b.final_amount), 0.00),
                    'avg_order_value', ROUND(AVG(b.final_amount), 2)
                ) ORDER BY SUM(b.final_amount) DESC
            ) INTO v_data
            FROM public.bills b
            JOIN public.orders o ON o.id = b.order_id
            WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
              AND b.status = 'paid'
            GROUP BY o.order_type;

        -- ─── 8. DISCOUNT & OFFERS REPORT ────────────────────────────────────
        WHEN 'discount' THEN
            SELECT jsonb_agg(
                jsonb_build_object(
                    'bill_number', b.bill_number,
                    'business_date', b.business_date,
                    'customer_name', COALESCE(b.customer_name_snapshot, 'Guest'),
                    'discount_type', b.discount_type,
                    'discount_rate', b.discount_rate,
                    'discount_amount', b.discount_amount,
                    'discount_reason', COALESCE(b.discount_reason, 'Standard Promotion'),
                    'subtotal', b.subtotal_amount,
                    'final_amount', b.final_amount
                ) ORDER BY b.discount_amount DESC
            ) INTO v_data
            FROM public.bills b
            WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
              AND b.discount_amount > 0
              AND b.status = 'paid';

        -- ─── 9. CANCELLATION & VOID REPORT ──────────────────────────────────
        WHEN 'cancellation' THEN
            SELECT jsonb_agg(
                jsonb_build_object(
                    'type', report_union.type,
                    'reference', report_union.reference,
                    'timestamp', report_union.action_at,
                    'amount', report_union.amount,
                    'reason', report_union.reason,
                    'actor_name', COALESCE(u.full_name, 'System')
                ) ORDER BY report_union.action_at DESC
            ) INTO v_data
            FROM (
                -- Cancelled orders
                SELECT 
                    'Order Cancellation' AS type,
                    o.order_number AS reference,
                    o.cancelled_at AS action_at,
                    o.total_amount AS amount,
                    o.cancellation_reason AS reason,
                    o.cancelled_by AS actor_id
                FROM public.orders o
                WHERE o.status = 'cancelled'
                  AND o.created_at::date >= p_start_date AND o.created_at::date <= p_end_date

                UNION ALL

                -- Voided bills
                SELECT 
                    'Bill Void' AS type,
                    b.bill_number AS reference,
                    b.voided_at AS action_at,
                    b.final_amount AS amount,
                    b.void_reason AS reason,
                    b.voided_by AS actor_id
                FROM public.bills b
                WHERE b.status = 'voided'
                  AND b.business_date >= p_start_date AND b.business_date <= p_end_date
            ) report_union
            LEFT JOIN public.user_profiles u ON u.id = report_union.actor_id;

        ELSE
            RAISE EXCEPTION 'Invalid report type: %. Supported: sales, product, category, server, payment, table, order_type, discount, cancellation', p_report_type;
    END CASE;

    RETURN jsonb_build_object(
        'report_type', p_report_type,
        'start_date', p_start_date,
        'end_date', p_end_date,
        'generated_at', now(),
        'records_count', jsonb_array_length(COALESCE(v_data, '[]'::jsonb)),
        'records', COALESCE(v_data, '[]'::jsonb)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_admin_report_data(TEXT, DATE, DATE) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_admin_report_data(TEXT, DATE, DATE) TO authenticated;
