-- Fix get_admin_report_data to accept both 'discount' and 'offer' as report types
CREATE OR REPLACE FUNCTION public.get_admin_report_data(
    p_report_type TEXT,
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
                    'date', b.business_date,
                    'created_at', b.created_at,
                    'order_type', o.order_type,
                    'table_number', t.table_number,
                    'customer_name', COALESCE(b.customer_name_snapshot, 'Walk-In'),
                    'customer_phone', b.customer_phone_snapshot,
                    'subtotal', b.subtotal_amount,
                    'discount', b.discount_amount,
                    'discount_amount', b.discount_amount,
                    'tax', b.tax_amount,
                    'round_off', b.round_off_amount,
                    'total', b.final_amount,
                    'final_amount', b.final_amount,
                    'status', b.status,
                    'payment_method', COALESCE(
                        (SELECT p.payment_method FROM public.payments p WHERE p.bill_id = b.id LIMIT 1),
                        'cash'
                    ),
                    'item_count', (
                        SELECT COUNT(*) FROM public.order_items oi 
                        WHERE oi.order_id = o.id AND oi.status <> 'cancelled'
                    ),
                    'server_name', COALESCE(
                        (SELECT u.full_name FROM public.user_profiles u WHERE u.id = o.server_id),
                        'Cashier Desk'
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
                    'net_sales', SUM(oi.item_total),
                    'discount_share', 0.00,
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
                    'gross_sales', SUM(oi.item_total),
                    'total_revenue', SUM(oi.item_total),
                    'net_sales', SUM(oi.item_total),
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
                    'server_role', COALESCE(u.role, 'staff'),
                    'orders_served', COUNT(DISTINCT o.id),
                    'total_sales', COALESCE(SUM(b.final_amount), 0.00),
                    'total_revenue', COALESCE(SUM(b.final_amount), 0.00),
                    'bills_count', COUNT(DISTINCT b.id),
                    'bills_handled', COUNT(DISTINCT b.id)
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
                    'total_amount', SUM(p.amount),
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
                    'total_sales', COALESCE(SUM(b.final_amount), 0.00),
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

        -- ─── 7. ORDER TYPE BREAKDOWN ────────────────────────────────────────
        WHEN 'order_type' THEN
            SELECT jsonb_agg(
                jsonb_build_object(
                    'order_type', o.order_type,
                    'order_count', COUNT(DISTINCT o.id),
                    'bills_count', COUNT(DISTINCT b.id),
                    'total_sales', COALESCE(SUM(b.final_amount), 0.00),
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
        WHEN 'discount', 'offer' THEN
            SELECT jsonb_agg(
                jsonb_build_object(
                    'offer_name', COALESCE(b.discount_reason, 'Promotional Discount'),
                    'bill_number', b.bill_number,
                    'business_date', b.business_date,
                    'customer_name', COALESCE(b.customer_name_snapshot, 'Guest'),
                    'discount_type', COALESCE(b.discount_type, 'flat'),
                    'discount_rate', b.discount_rate,
                    'discount_amount', b.discount_amount,
                    'total_discount_amount', b.discount_amount,
                    'orders_count', 1,
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
                    'order_status', report_union.type,
                    'timestamp', report_union.action_at,
                    'cancelled_at', report_union.action_at,
                    'amount', report_union.amount,
                    'estimated_amount', report_union.amount,
                    'reason', report_union.reason,
                    'items_count', 1,
                    'table_number', report_union.table_num,
                    'actor_name', COALESCE(u.full_name, 'System')
                ) ORDER BY report_union.action_at DESC
            ) INTO v_data
            FROM (
                SELECT 
                    'Order Cancellation' AS type,
                    o.order_number AS reference,
                    o.cancelled_at AS action_at,
                    o.total_amount AS amount,
                    o.cancellation_reason AS reason,
                    o.cancelled_by AS actor_id,
                    t.table_number AS table_num
                FROM public.orders o
                LEFT JOIN public.restaurant_tables t ON t.id = o.table_id
                WHERE o.status = 'cancelled'
                  AND o.created_at::date >= p_start_date AND o.created_at::date <= p_end_date

                UNION ALL

                SELECT 
                    'Bill Void' AS type,
                    b.bill_number AS reference,
                    b.voided_at AS action_at,
                    b.final_amount AS amount,
                    b.void_reason AS reason,
                    b.voided_by AS actor_id,
                    t.table_number AS table_num
                FROM public.bills b
                JOIN public.orders o ON o.id = b.order_id
                LEFT JOIN public.restaurant_tables t ON t.id = o.table_id
                WHERE b.status = 'voided'
                  AND b.created_at::date >= p_start_date AND b.created_at::date <= p_end_date
            ) report_union
            LEFT JOIN public.user_profiles u ON u.id = report_union.actor_id;

        ELSE
            RAISE EXCEPTION 'Invalid report type "%". Supported types: sales, product, category, server, payment, table, order_type, discount, offer, cancellation', p_report_type;
    END CASE;

    -- Return JSON payload with metadata
    RETURN jsonb_build_object(
        'report_type', lower(trim(p_report_type)),
        'start_date', p_start_date,
        'end_date', p_end_date,
        'generated_at', now(),
        'records_count', COALESCE(jsonb_array_length(v_data), 0),
        'records', COALESCE(v_data, '[]'::jsonb)
    );
END;
$$;
