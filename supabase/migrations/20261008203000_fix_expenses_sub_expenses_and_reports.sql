-- ============================================================================
-- Migration: 20261008203000_fix_expenses_sub_expenses_and_reports.sql
-- Description:
--   1. Update record_expense_transaction RPC to accept and persist p_sub_expenses JSONB.
--   2. Update edit_expense_transaction RPC to accept and persist p_sub_expenses JSONB.
--   3. Update get_cashier_month_expenses RPC to include sub_expenses in both
--      active transactions and fixed_definitions.
--   4. Update get_admin_expense_report RPC to include sub_expenses in transaction rows.
--   5. Ensure authenticated execution permissions.
-- ============================================================================

-- 1. RPC: record_expense_transaction with sub_expenses support
CREATE OR REPLACE FUNCTION public.record_expense_transaction(
    p_definition_id UUID DEFAULT NULL,
    p_custom_name VARCHAR DEFAULT NULL,
    p_amount NUMERIC DEFAULT NULL,
    p_payment_method VARCHAR DEFAULT 'cash',
    p_notes TEXT DEFAULT NULL,
    p_applicable_period VARCHAR DEFAULT NULL,
    p_expense_date DATE DEFAULT CURRENT_DATE,
    p_sub_expenses JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_def RECORD;
    v_caller_id UUID;
    v_period VARCHAR(20);
    v_tx_id UUID;
    v_expense_name VARCHAR(150);
    v_expense_type VARCHAR(20);
    v_frequency VARCHAR(20);
    v_is_fixed BOOLEAN;
BEGIN
    v_caller_id := auth.uid();

    -- Validate amount
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Expense amount must be greater than zero.';
    END IF;

    -- Validate payment method
    IF p_payment_method NOT IN ('cash', 'upi', 'bank_transfer', 'card', 'other') THEN
        RAISE EXCEPTION 'Invalid payment method: %', p_payment_method;
    END IF;

    IF p_definition_id IS NOT NULL THEN
        -- Fixed Expense (selected from Admin definitions)
        SELECT * INTO v_def FROM public.expense_definitions WHERE id = p_definition_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Fixed expense definition not found.';
        END IF;

        IF NOT v_def.is_active THEN
            RAISE EXCEPTION 'Cannot record against an inactive definition.';
        END IF;

        v_expense_name := v_def.name;
        v_expense_type := v_def.expense_type;
        v_frequency := v_def.frequency;
        v_is_fixed := true;
        v_period := COALESCE(NULLIF(trim(p_applicable_period), ''), TO_CHAR(p_expense_date, 'YYYY-MM'));
    ELSE
        -- Non-Fixed Expense (created on-the-fly by cashier)
        IF p_custom_name IS NULL OR trim(p_custom_name) = '' THEN
            RAISE EXCEPTION 'Custom expense name is required for non-fixed expenses.';
        END IF;

        v_expense_name := trim(p_custom_name);
        v_expense_type := 'occasional';
        v_frequency := 'as_needed';
        v_is_fixed := false;
        v_period := TO_CHAR(p_expense_date, 'YYYY-MM');
    END IF;

    -- Insert actual transaction with immutable snapshots and sub_expenses
    INSERT INTO public.expense_transactions (
        definition_id,
        expense_name_snapshot,
        expense_type_snapshot,
        frequency_snapshot,
        is_fixed,
        applicable_period,
        expense_date,
        amount,
        payment_method,
        notes,
        sub_expenses,
        recorded_by,
        status,
        created_at,
        updated_at
    ) VALUES (
        p_definition_id,
        v_expense_name,
        v_expense_type,
        v_frequency,
        v_is_fixed,
        v_period,
        p_expense_date,
        ROUND(p_amount, 2),
        p_payment_method,
        NULLIF(trim(p_notes), ''),
        COALESCE(p_sub_expenses, '[]'::jsonb),
        v_caller_id,
        'completed',
        now(),
        now()
    ) RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'expense_name', v_expense_name,
        'amount', ROUND(p_amount, 2),
        'expense_date', p_expense_date,
        'payment_method', p_payment_method,
        'sub_expenses', COALESCE(p_sub_expenses, '[]'::jsonb)
    );
END;
$$;

-- 2. RPC: edit_expense_transaction with sub_expenses support
CREATE OR REPLACE FUNCTION public.edit_expense_transaction(
    p_transaction_id UUID,
    p_amount NUMERIC,
    p_payment_method VARCHAR,
    p_notes TEXT DEFAULT NULL,
    p_edit_reason TEXT DEFAULT NULL,
    p_sub_expenses JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tx RECORD;
    v_caller_id UUID;
    v_old_amount NUMERIC(10,2);
BEGIN
    v_caller_id := auth.uid();

    SELECT * INTO v_tx FROM public.expense_transactions WHERE id = p_transaction_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Expense transaction not found.';
    END IF;

    IF v_tx.is_deleted OR v_tx.status = 'deleted' THEN
        RAISE EXCEPTION 'Cannot edit a deleted expense.';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Expense amount must be greater than zero.';
    END IF;

    IF p_payment_method NOT IN ('cash', 'upi', 'bank_transfer', 'card', 'other') THEN
        RAISE EXCEPTION 'Invalid payment method: %', p_payment_method;
    END IF;

    v_old_amount := v_tx.amount;

    UPDATE public.expense_transactions
    SET amount = ROUND(p_amount, 2),
        original_amount = COALESCE(v_tx.original_amount, v_old_amount),
        payment_method = p_payment_method,
        notes = NULLIF(trim(p_notes), ''),
        sub_expenses = CASE 
            WHEN p_sub_expenses IS NOT NULL THEN p_sub_expenses 
            ELSE sub_expenses 
        END,
        is_edited = true,
        edited_at = now(),
        edited_by = v_caller_id,
        edit_reason = NULLIF(trim(p_edit_reason), ''),
        updated_at = now()
    WHERE id = p_transaction_id;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', p_transaction_id,
        'new_amount', ROUND(p_amount, 2),
        'original_amount', COALESCE(v_tx.original_amount, v_old_amount),
        'edited_at', now()
    );
END;
$$;

-- 3. RPC: get_cashier_month_expenses with sub_expenses in transactions & fixed_definitions
CREATE OR REPLACE FUNCTION public.get_cashier_month_expenses(
    p_target_date DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_period VARCHAR(20);
    v_month_label VARCHAR(50);
    v_expenses JSONB;
    v_fixed_defs JSONB;
    v_total_expenses NUMERIC(12,2) := 0.00;
    v_fixed_total NUMERIC(12,2) := 0.00;
    v_non_fixed_total NUMERIC(12,2) := 0.00;
    v_fixed_count INT := 0;
    v_non_fixed_count INT := 0;
BEGIN
    v_period := TO_CHAR(p_target_date, 'YYYY-MM');
    v_month_label := TO_CHAR(p_target_date, 'FMMonth YYYY');

    -- Aggregate monthly active expenses (not deleted)
    SELECT 
        COALESCE(SUM(amount), 0.00),
        COALESCE(SUM(CASE WHEN is_fixed = true THEN amount ELSE 0 END), 0.00),
        COALESCE(SUM(CASE WHEN is_fixed = false THEN amount ELSE 0 END), 0.00),
        COUNT(CASE WHEN is_fixed = true THEN 1 END),
        COUNT(CASE WHEN is_fixed = false THEN 1 END)
    INTO 
        v_total_expenses,
        v_fixed_total,
        v_non_fixed_total,
        v_fixed_count,
        v_non_fixed_count
    FROM public.expense_transactions
    WHERE status = 'completed'
      AND is_deleted = false
      AND (applicable_period = v_period OR TO_CHAR(expense_date, 'YYYY-MM') = v_period);

    -- Build list of current month expenses
    SELECT COALESCE(jsonb_agg(item ORDER BY item->>'created_at' DESC), '[]'::jsonb)
    INTO v_expenses
    FROM (
        SELECT jsonb_build_object(
            'id', et.id,
            'definition_id', et.definition_id,
            'name', et.expense_name_snapshot,
            'is_fixed', et.is_fixed,
            'expense_type', et.expense_type_snapshot,
            'frequency', et.frequency_snapshot,
            'applicable_period', et.applicable_period,
            'expense_date', et.expense_date,
            'amount', et.amount,
            'original_amount', et.original_amount,
            'payment_method', et.payment_method,
            'notes', et.notes,
            'sub_expenses', COALESCE(et.sub_expenses, '[]'::jsonb),
            'status', et.status,
            'recorded_by_id', et.recorded_by,
            'recorded_by_name', COALESCE(up.full_name, 'Staff'),
            'is_edited', et.is_edited,
            'edited_at', et.edited_at,
            'edited_by_name', COALESCE(ed_up.full_name, 'Staff'),
            'edit_reason', et.edit_reason,
            'created_at', et.created_at
        ) AS item
        FROM public.expense_transactions et
        LEFT JOIN public.user_profiles up ON up.id = et.recorded_by
        LEFT JOIN public.user_profiles ed_up ON ed_up.id = et.edited_by
        WHERE et.status = 'completed'
          AND et.is_deleted = false
          AND (et.applicable_period = v_period OR TO_CHAR(et.expense_date, 'YYYY-MM') = v_period)
    ) sub;

    -- Build list of active fixed definitions configured by Admin
    SELECT COALESCE(jsonb_agg(d ORDER BY d->>'name' ASC), '[]'::jsonb)
    INTO v_fixed_defs
    FROM (
        SELECT jsonb_build_object(
            'id', ed.id,
            'name', ed.name,
            'description', ed.description,
            'expense_type', ed.expense_type,
            'frequency', ed.frequency,
            'start_date', ed.start_date,
            'sub_expenses', COALESCE(ed.sub_expenses, '[]'::jsonb)
        ) AS d
        FROM public.expense_definitions ed
        WHERE ed.is_active = true
    ) d_sub;

    RETURN jsonb_build_object(
        'target_date', p_target_date,
        'target_period', v_period,
        'month_label', v_month_label,
        'total_expenses', v_total_expenses,
        'fixed_total', v_fixed_total,
        'non_fixed_total', v_non_fixed_total,
        'fixed_count', v_fixed_count,
        'non_fixed_count', v_non_fixed_count,
        'expenses', v_expenses,
        'fixed_definitions', v_fixed_defs
    );
END;
$$;

-- 4. RPC: get_admin_expense_report with sub_expenses in rows
CREATE OR REPLACE FUNCTION public.get_admin_expense_report(
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL,
    p_filter_status VARCHAR DEFAULT 'all',     -- 'all', 'active_only', 'deleted_only'
    p_expense_type VARCHAR DEFAULT 'all',      -- 'all', 'fixed', 'non_fixed'
    p_definition_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_start DATE;
    v_end DATE;
    v_rows JSONB;
    v_summary JSONB;
BEGIN
    v_start := COALESCE(p_start_date, (CURRENT_DATE - INTERVAL '30 days')::DATE);
    v_end := COALESCE(p_end_date, CURRENT_DATE);

    -- Build individual transaction rows
    SELECT COALESCE(jsonb_agg(row_item ORDER BY row_item->>'created_at' DESC), '[]'::jsonb)
    INTO v_rows
    FROM (
        SELECT jsonb_build_object(
            'id', et.id,
            'definition_id', et.definition_id,
            'name', et.expense_name_snapshot,
            'is_fixed', et.is_fixed,
            'expense_type', et.expense_type_snapshot,
            'frequency', et.frequency_snapshot,
            'applicable_period', et.applicable_period,
            'expense_date', et.expense_date,
            'amount', et.amount,
            'original_amount', et.original_amount,
            'payment_method', et.payment_method,
            'notes', et.notes,
            'sub_expenses', COALESCE(et.sub_expenses, '[]'::jsonb),
            'status', et.status,
            'recorded_by_name', COALESCE(up.full_name, 'Staff'),
            'is_edited', et.is_edited,
            'edited_at', et.edited_at,
            'edited_by_name', COALESCE(ed_up.full_name, 'Staff'),
            'edit_reason', et.edit_reason,
            'is_deleted', et.is_deleted,
            'deleted_at', et.deleted_at,
            'deleted_by_name', COALESCE(del_up.full_name, 'Staff'),
            'delete_reason', et.delete_reason,
            'created_at', et.created_at
        ) AS row_item
        FROM public.expense_transactions et
        LEFT JOIN public.user_profiles up ON up.id = et.recorded_by
        LEFT JOIN public.user_profiles ed_up ON ed_up.id = et.edited_by
        LEFT JOIN public.user_profiles del_up ON del_up.id = et.deleted_by
        WHERE et.expense_date BETWEEN v_start AND v_end
          AND (
              p_filter_status = 'all'
              OR (p_filter_status = 'active_only' AND et.is_deleted = false AND et.status = 'completed')
              OR (p_filter_status = 'deleted_only' AND (et.is_deleted = true OR et.status = 'deleted'))
          )
          AND (
              p_expense_type = 'all'
              OR (p_expense_type = 'fixed' AND et.is_fixed = true)
              OR (p_expense_type = 'non_fixed' AND et.is_fixed = false)
          )
          AND (p_definition_id IS NULL OR et.definition_id = p_definition_id)
    ) sub;

    -- Build aggregate summary KPIs
    SELECT jsonb_build_object(
        'start_date', v_start,
        'end_date', v_end,
        'total_active_amount', COALESCE(SUM(CASE WHEN is_deleted = false AND status = 'completed' THEN amount ELSE 0 END), 0.00),
        'total_active_count', COUNT(CASE WHEN is_deleted = false AND status = 'completed' THEN 1 END),
        'total_deleted_amount', COALESCE(SUM(CASE WHEN is_deleted = true OR status = 'deleted' THEN amount ELSE 0 END), 0.00),
        'total_deleted_count', COUNT(CASE WHEN is_deleted = true OR status = 'deleted' THEN 1 END),
        'fixed_active_amount', COALESCE(SUM(CASE WHEN is_fixed = true AND is_deleted = false AND status = 'completed' THEN amount ELSE 0 END), 0.00),
        'non_fixed_active_amount', COALESCE(SUM(CASE WHEN is_fixed = false AND is_deleted = false AND status = 'completed' THEN amount ELSE 0 END), 0.00)
    )
    INTO v_summary
    FROM public.expense_transactions
    WHERE expense_date BETWEEN v_start AND v_end
      AND (p_definition_id IS NULL OR definition_id = p_definition_id);

    RETURN jsonb_build_object(
        'summary', v_summary,
        'transactions', v_rows
    );
END;
$$;

-- Grant permissions to authenticated
GRANT EXECUTE ON FUNCTION public.record_expense_transaction(UUID, VARCHAR, NUMERIC, VARCHAR, TEXT, VARCHAR, DATE, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.edit_expense_transaction(UUID, NUMERIC, VARCHAR, TEXT, TEXT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_cashier_month_expenses(DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_admin_expense_report(DATE, DATE, VARCHAR, VARCHAR, UUID) TO authenticated;
