-- Migration: 20261019130000_admin_reports_and_metrics_support_edited_bills.sql
-- Description: Update swap_bill_payment_method to support both 'method' and 'payment_method' keys,
-- and update get_admin_report_data and get_admin_dashboard_metrics to return is_edited and accurate payment_method.

-- 1. Refine swap_bill_payment_method to accept both key naming conventions
CREATE OR REPLACE FUNCTION public.swap_bill_payment_method(
    p_bill_id UUID,
    p_new_payments JSONB,
    p_reason TEXT DEFAULT 'Payment method swapped by cashier'
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
    v_assigned_roles TEXT[];
    v_bill RECORD;
    v_order RECORD;
    v_old_payments JSONB;
    v_payment_record JSONB;
    v_method VARCHAR(20);
    v_amount NUMERIC(10,2);
    v_cash_tendered NUMERIC(10,2);
    v_change_returned NUMERIC(10,2);
    v_tx_ref VARCHAR(100);
    v_total_paid NUMERIC(10,2) := 0;
    v_new_methods_summary TEXT := '';
    v_method_count INT := 0;
    v_current_local_date DATE;
BEGIN
    -- 1. Authorization: cashier or super_admin
    SELECT role, assigned_roles INTO v_role, v_assigned_roles
    FROM public.user_profiles
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR (
        v_role NOT IN ('cashier', 'super_admin') 
        AND NOT ('cashier' = ANY(v_assigned_roles) OR 'super_admin' = ANY(v_assigned_roles))
    ) THEN
        RAISE EXCEPTION 'Unauthorized: only cashier or super_admin can swap payment methods';
    END IF;

    -- 2. Lock bill
    SELECT * INTO v_bill FROM public.bills WHERE id = p_bill_id FOR UPDATE;
    IF v_bill IS NULL THEN
        RAISE EXCEPTION 'Bill not found';
    END IF;

    -- 3. Verify bill is paid (cannot swap unpaid or voided bills)
    IF v_bill.status <> 'paid' THEN
        RAISE EXCEPTION 'Only paid bills can have payment method swapped (current status: %).', v_bill.status;
    END IF;

    -- 4. Same-Day Restriction: only allow swapping on the day the bill was generated
    v_current_local_date := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
    IF (v_bill.created_at AT TIME ZONE 'Asia/Kolkata')::DATE < v_current_local_date 
       AND (v_bill.business_date IS NULL OR v_bill.business_date < v_current_local_date) THEN
        RAISE EXCEPTION 'Payment method swap is strictly restricted to same-day bills (generated today).';
    END IF;

    -- 5. Validate new payment array
    IF p_new_payments IS NULL OR jsonb_array_length(p_new_payments) = 0 THEN
        RAISE EXCEPTION 'At least one new payment entry is required';
    END IF;

    -- 6. Lock parent order
    SELECT * INTO v_order FROM public.orders WHERE id = v_bill.order_id FOR UPDATE;

    -- 7. Snapshot old payments for audit log
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', p.id,
            'payment_method', p.payment_method,
            'amount', p.amount,
            'cash_tendered', p.cash_tendered,
            'transaction_reference', p.transaction_reference,
            'status', p.status
        )
    ) INTO v_old_payments
    FROM public.payments p
    WHERE p.bill_id = p_bill_id;

    -- 8. Validate and sum new payment entries
    FOR v_payment_record IN SELECT * FROM jsonb_array_elements(p_new_payments)
    LOOP
        v_method := LOWER(TRIM(COALESCE(v_payment_record->>'method', v_payment_record->>'payment_method', '')));
        v_amount := (v_payment_record->>'amount')::NUMERIC;
        v_cash_tendered := (v_payment_record->>'cash_tendered')::NUMERIC;
        v_tx_ref := COALESCE(v_payment_record->>'transaction_reference', v_payment_record->>'tx_ref');

        IF v_method IS NULL OR v_method NOT IN ('cash', 'upi', 'card') THEN
            RAISE EXCEPTION 'Invalid payment method: %. Must be cash, upi, or card', v_method;
        END IF;

        IF v_amount IS NULL OR v_amount <= 0 THEN
            RAISE EXCEPTION 'Payment amount must be greater than zero';
        END IF;

        v_total_paid := v_total_paid + v_amount;

        IF v_method_count > 0 THEN
            v_new_methods_summary := v_new_methods_summary || ' + ';
        END IF;
        v_new_methods_summary := v_new_methods_summary || UPPER(v_method) || ' (₹' || v_amount::TEXT || ')';
        v_method_count := v_method_count + 1;
    END LOOP;

    -- 9. Strict Amount Check: Total of new payments MUST equal bill final_amount
    IF ROUND(v_total_paid, 2) <> ROUND(v_bill.final_amount, 2) THEN
        RAISE EXCEPTION 'New payments sum (₹%) does not match bill final amount (₹%)',
            ROUND(v_total_paid, 2), ROUND(v_bill.final_amount, 2);
    END IF;

    -- 10. Atomic replacement of payment rows
    DELETE FROM public.payments WHERE bill_id = p_bill_id;

    FOR v_payment_record IN SELECT * FROM jsonb_array_elements(p_new_payments)
    LOOP
        v_method := LOWER(TRIM(COALESCE(v_payment_record->>'method', v_payment_record->>'payment_method', '')));
        v_amount := (v_payment_record->>'amount')::NUMERIC;
        v_cash_tendered := (v_payment_record->>'cash_tendered')::NUMERIC;
        v_tx_ref := COALESCE(v_payment_record->>'transaction_reference', v_payment_record->>'tx_ref');

        IF v_method = 'cash' THEN
            IF v_cash_tendered IS NULL OR v_cash_tendered < v_amount THEN
                v_cash_tendered := v_amount;
            END IF;
            v_change_returned := v_cash_tendered - v_amount;
        ELSE
            v_cash_tendered := NULL;
            v_change_returned := NULL;
        END IF;

        INSERT INTO public.payments (
            id,
            bill_id,
            payment_method,
            amount,
            cash_tendered,
            change_returned,
            transaction_reference,
            received_by,
            status,
            created_at
        )
        VALUES (
            gen_random_uuid(),
            p_bill_id,
            v_method,
            v_amount,
            v_cash_tendered,
            v_change_returned,
            v_tx_ref,
            COALESCE(v_actor, v_bill.cashier_id),
            'completed',
            v_bill.created_at
        );
    END LOOP;

    -- 11. Append [EDITED] and payment swap note to parent order notes
    IF v_order.id IS NOT NULL THEN
        UPDATE public.orders
        SET notes = CASE
            WHEN notes IS NULL OR TRIM(notes) = '' THEN
                '[EDITED] (Payment swapped to ' || v_new_methods_summary || ')'
            WHEN notes NOT LIKE '%[EDITED]%' THEN
                notes || ' | [EDITED] (Payment swapped to ' || v_new_methods_summary || ')'
            ELSE
                notes || ' | (Payment swapped to ' || v_new_methods_summary || ')'
        END,
        updated_at = now()
        WHERE id = v_order.id;
    END IF;

    -- 12. Record audit log
    INSERT INTO public.audit_logs (
        user_id,
        action,
        entity_type,
        entity_id,
        old_data,
        new_data
    )
    VALUES (
        v_actor,
        'SWAP_PAYMENT_METHOD',
        'bills',
        p_bill_id::text,
        jsonb_build_object(
            'bill_number', v_bill.bill_number,
            'final_amount', v_bill.final_amount,
            'old_payments', v_old_payments
        ),
        jsonb_build_object(
            'bill_number', v_bill.bill_number,
            'final_amount', v_bill.final_amount,
            'new_payments', p_new_payments,
            'methods_summary', v_new_methods_summary,
            'reason', p_reason
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'bill_id', p_bill_id,
        'bill_number', v_bill.bill_number,
        'final_amount', v_bill.final_amount,
        'methods_summary', v_new_methods_summary
    );
END;
$$;

-- 2. Update get_admin_dashboard_metrics to return is_edited and accurate payment method for recent bills
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
    v_total_sales NUMERIC(12,2) := 0;
    v_total_bills INT := 0;
    v_active_orders INT := 0;
    v_billing_orders INT := 0;
    v_cancelled_orders INT := 0;
    v_total_tables INT := 0;
    v_occupied_tables INT := 0;
    v_total_products INT := 0;
    v_active_products INT := 0;
    v_total_categories INT := 0;
    v_active_servers INT := 0;
    v_sales_trend JSONB := '[]'::jsonb;
    v_payment_breakdown JSONB := '[]'::jsonb;
    v_recent_bills JSONB := '[]'::jsonb;
BEGIN
    SELECT role, assigned_roles INTO v_role, v_assigned_roles
    FROM public.user_profiles
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR (
        v_role NOT IN ('super_admin', 'cashier') 
        AND NOT ('super_admin' = ANY(v_assigned_roles) OR 'cashier' = ANY(v_assigned_roles))
    ) THEN
        RAISE EXCEPTION 'Unauthorized: dashboard metrics restricted to admin';
    END IF;

    SELECT 
        COALESCE(SUM(final_amount), 0),
        COUNT(*)
    INTO v_total_sales, v_total_bills
    FROM public.bills
    WHERE business_date >= p_start_date AND business_date <= p_end_date
      AND status = 'paid';

    SELECT
        COUNT(*) FILTER (WHERE status IN ('active', 'in_progress', 'served')),
        COUNT(*) FILTER (WHERE status = 'billing'),
        COUNT(*) FILTER (WHERE status = 'cancelled')
    INTO v_active_orders, v_billing_orders, v_cancelled_orders
    FROM public.orders
    WHERE created_at::date >= p_start_date AND created_at::date <= p_end_date;

    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE is_active = true)
    INTO v_total_tables, v_occupied_tables
    FROM public.restaurant_tables;

    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE is_available = true)
    INTO v_total_products, v_active_products
    FROM public.menu_items;

    SELECT COUNT(*) INTO v_total_categories FROM public.categories;

    SELECT COUNT(DISTINCT server_id) INTO v_active_servers
    FROM public.orders
    WHERE created_at::date >= p_start_date AND created_at::date <= p_end_date
      AND server_id IS NOT NULL;

    SELECT jsonb_agg(
        jsonb_build_object(
            'payment_method', p.payment_method,
            'total_amount', p.total_amount,
            'transaction_count', p.transaction_count
        )
    ) INTO v_payment_breakdown
    FROM (
        SELECT 
            pm.payment_method,
            COALESCE(SUM(pm.amount), 0) AS total_amount,
            COUNT(*) AS transaction_count
        FROM public.payments pm
        JOIN public.bills b ON b.id = pm.bill_id
        WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
          AND pm.status = 'completed'
        GROUP BY pm.payment_method
    ) p;

    SELECT jsonb_agg(
        jsonb_build_object(
            'date', trend.business_date,
            'total_sales', trend.day_sales,
            'bills_count', trend.day_bills
        ) ORDER BY trend.business_date ASC
    ) INTO v_sales_trend
    FROM (
        SELECT 
            b.business_date,
            COALESCE(SUM(b.final_amount), 0) AS day_sales,
            COUNT(*) AS day_bills
        FROM public.bills b
        WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
          AND b.status = 'paid'
        GROUP BY b.business_date
    ) trend;

    -- Recent 5 settled bills with is_edited and accurate payment_method
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', b.id,
            'bill_number', b.bill_number,
            'customer_name', COALESCE(b.customer_name_snapshot, 'Walk-In'),
            'final_amount', b.final_amount,
            'created_at', b.created_at,
            'status', b.status,
            'is_edited', (b.notes ILIKE '%[EDITED]%'),
            'payment_method', COALESCE(
                CASE 
                    WHEN (SELECT COUNT(DISTINCT p.payment_method) FROM public.payments p WHERE p.bill_id = b.id) > 1 THEN 'split'
                    ELSE (SELECT p.payment_method FROM public.payments p WHERE p.bill_id = b.id LIMIT 1)
                END,
                'cash'
            )
        ) ORDER BY b.created_at DESC
    ) INTO v_recent_bills
    FROM (
        SELECT b.*, o.notes 
        FROM public.bills b
        JOIN public.orders o ON o.id = b.order_id
        WHERE b.status = 'paid' 
        ORDER BY b.created_at DESC 
        LIMIT 5
    ) b;

    RETURN jsonb_build_object(
        'start_date', p_start_date,
        'end_date', p_end_date,
        'total_sales', v_total_sales,
        'total_bills', v_total_bills,
        'active_orders', v_active_orders,
        'billing_orders', v_billing_orders,
        'cancelled_orders', v_cancelled_orders,
        'total_tables', v_total_tables,
        'occupied_tables', v_occupied_tables,
        'total_products', v_total_products,
        'active_products', v_active_products,
        'total_categories', v_total_categories,
        'active_servers', v_active_servers,
        'sales_trend', COALESCE(v_sales_trend, '[]'::jsonb),
        'payment_breakdown', COALESCE(v_payment_breakdown, '[]'::jsonb),
        'recent_bills', COALESCE(v_recent_bills, '[]'::jsonb)
    );
END;
$$;

-- 3. Update get_admin_report_data for 'sales' report type
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
    SELECT role, assigned_roles INTO v_role, v_assigned_roles
    FROM public.user_profiles
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR (
        v_role NOT IN ('super_admin', 'cashier') 
        AND NOT ('super_admin' = ANY(v_assigned_roles) OR 'cashier' = ANY(v_assigned_roles))
    ) THEN
        RAISE EXCEPTION 'Unauthorized: report access restricted to admin';
    END IF;

    CASE lower(trim(p_report_type))
        WHEN 'sales' THEN
            SELECT COALESCE(jsonb_agg(
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
                    'notes', o.notes,
                    'is_edited', (o.notes ILIKE '%[EDITED]%'),
                    'payment_method', COALESCE(
                        CASE 
                            WHEN (SELECT COUNT(DISTINCT p.payment_method) FROM public.payments p WHERE p.bill_id = b.id) > 1 THEN 'split'
                            ELSE (SELECT p.payment_method FROM public.payments p WHERE p.bill_id = b.id LIMIT 1)
                        END,
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
            ), '[]'::jsonb) INTO v_data
            FROM public.bills b
            JOIN public.orders o ON o.id = b.order_id
            LEFT JOIN public.restaurant_tables t ON t.id = o.table_id
            WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
              AND b.status = 'paid';

        WHEN 'product' THEN
            SELECT COALESCE(jsonb_agg(
                jsonb_build_object(
                    'product_name', p_agg.product_name,
                    'category_name', p_agg.category_name,
                    'quantity_sold', p_agg.quantity_sold,
                    'total_revenue', p_agg.total_revenue
                ) ORDER BY p_agg.total_revenue DESC
            ), '[]'::jsonb) INTO v_data
            FROM (
                SELECT 
                    oi.item_name_snapshot AS product_name,
                    COALESCE(c.name, 'Uncategorized') AS category_name,
                    SUM(oi.quantity) AS quantity_sold,
                    SUM(oi.item_total) AS total_revenue
                FROM public.order_items oi
                JOIN public.orders o ON o.id = oi.order_id
                JOIN public.bills b ON b.order_id = o.id
                LEFT JOIN public.menu_items mi ON mi.id = oi.menu_item_id
                LEFT JOIN public.categories c ON c.id = mi.category_id
                WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
                  AND b.status = 'paid'
                  AND oi.status <> 'cancelled'
                GROUP BY oi.item_name_snapshot, c.name
            ) p_agg;

        WHEN 'category' THEN
            SELECT COALESCE(jsonb_agg(
                jsonb_build_object(
                    'category_name', c_agg.category_name,
                    'items_sold', c_agg.items_sold,
                    'total_revenue', c_agg.total_revenue
                ) ORDER BY c_agg.total_revenue DESC
            ), '[]'::jsonb) INTO v_data
            FROM (
                SELECT 
                    COALESCE(c.name, 'Uncategorized') AS category_name,
                    SUM(oi.quantity) AS items_sold,
                    SUM(oi.item_total) AS total_revenue
                FROM public.order_items oi
                JOIN public.orders o ON o.id = oi.order_id
                JOIN public.bills b ON b.order_id = o.id
                LEFT JOIN public.menu_items mi ON mi.id = oi.menu_item_id
                LEFT JOIN public.categories c ON c.id = mi.category_id
                WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
                  AND b.status = 'paid'
                  AND oi.status <> 'cancelled'
                GROUP BY c.name
            ) c_agg;

        WHEN 'server' THEN
            SELECT COALESCE(jsonb_agg(
                jsonb_build_object(
                    'server_name', s_agg.server_name,
                    'orders_count', s_agg.orders_count,
                    'total_sales', s_agg.total_sales
                ) ORDER BY s_agg.total_sales DESC
            ), '[]'::jsonb) INTO v_data
            FROM (
                SELECT 
                    COALESCE(u.full_name, 'Cashier Direct') AS server_name,
                    COUNT(DISTINCT b.id) AS orders_count,
                    SUM(b.final_amount) AS total_sales
                FROM public.bills b
                JOIN public.orders o ON o.id = b.order_id
                LEFT JOIN public.user_profiles u ON u.id = o.server_id
                WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
                  AND b.status = 'paid'
                GROUP BY u.full_name
            ) s_agg;

        WHEN 'payment' THEN
            SELECT COALESCE(jsonb_agg(
                jsonb_build_object(
                    'payment_method', pay_agg.payment_method,
                    'transaction_count', pay_agg.transaction_count,
                    'total_amount', pay_agg.total_amount
                ) ORDER BY pay_agg.total_amount DESC
            ), '[]'::jsonb) INTO v_data
            FROM (
                SELECT 
                    pm.payment_method,
                    COUNT(*) AS transaction_count,
                    SUM(pm.amount) AS total_amount
                FROM public.payments pm
                JOIN public.bills b ON b.id = pm.bill_id
                WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
                  AND pm.status = 'completed'
                GROUP BY pm.payment_method
            ) pay_agg;

        WHEN 'table' THEN
            SELECT COALESCE(jsonb_agg(
                jsonb_build_object(
                    'table_number', t_agg.table_number,
                    'capacity', t_agg.capacity,
                    'orders_count', t_agg.orders_count,
                    'total_sales', t_agg.total_sales
                ) ORDER BY t_agg.total_sales DESC
            ), '[]'::jsonb) INTO v_data
            FROM (
                SELECT 
                    COALESCE(t.table_number, 'Takeaway') AS table_number,
                    t.capacity,
                    COUNT(DISTINCT b.id) AS orders_count,
                    SUM(b.final_amount) AS total_sales
                FROM public.bills b
                JOIN public.orders o ON o.id = b.order_id
                LEFT JOIN public.restaurant_tables t ON t.id = o.table_id
                WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
                  AND b.status = 'paid'
                GROUP BY t.table_number, t.capacity
            ) t_agg;

        WHEN 'order_type' THEN
            SELECT COALESCE(jsonb_agg(
                jsonb_build_object(
                    'order_type', ot_agg.order_type,
                    'bills_count', ot_agg.bills_count,
                    'total_sales', ot_agg.total_sales
                ) ORDER BY ot_agg.total_sales DESC
            ), '[]'::jsonb) INTO v_data
            FROM (
                SELECT 
                    o.order_type,
                    COUNT(DISTINCT b.id) AS bills_count,
                    SUM(b.final_amount) AS total_sales
                FROM public.bills b
                JOIN public.orders o ON o.id = b.order_id
                WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
                  AND b.status = 'paid'
                GROUP BY o.order_type
            ) ot_agg;

        WHEN 'discount', 'offer' THEN
            SELECT COALESCE(jsonb_agg(
                jsonb_build_object(
                    'bill_number', b.bill_number,
                    'created_at', b.created_at,
                    'discount_type', b.discount_type,
                    'discount_value', b.discount_value,
                    'discount_amount', b.discount_amount,
                    'discount_reason', b.discount_reason,
                    'final_amount', b.final_amount,
                    'customer_name', COALESCE(b.customer_name_snapshot, 'Walk-In')
                ) ORDER BY b.created_at DESC
            ), '[]'::jsonb) INTO v_data
            FROM public.bills b
            WHERE b.business_date >= p_start_date AND b.business_date <= p_end_date
              AND b.status = 'paid'
              AND b.discount_amount > 0;

        WHEN 'cancellation' THEN
            SELECT COALESCE(jsonb_agg(
                jsonb_build_object(
                    'item_name', oi.item_name_snapshot,
                    'quantity', oi.quantity,
                    'unit_price', oi.unit_price_snapshot,
                    'cancellation_reason', oi.cancellation_reason,
                    'cancelled_at', oi.cancelled_at,
                    'cancelled_by', u.full_name,
                    'order_type', o.order_type,
                    'table_number', t.table_number
                ) ORDER BY oi.cancelled_at DESC
            ), '[]'::jsonb) INTO v_data
            FROM public.order_items oi
            JOIN public.orders o ON o.id = oi.order_id
            LEFT JOIN public.restaurant_tables t ON t.id = o.table_id
            LEFT JOIN public.user_profiles u ON u.id = oi.cancelled_by
            WHERE oi.cancelled_at::date >= p_start_date AND oi.cancelled_at::date <= p_end_date
              AND oi.status = 'cancelled';

        ELSE
            RAISE EXCEPTION 'Invalid report type: %', p_report_type;
    END CASE;

    RETURN v_data;
END;
$$;
