-- Migration: Allow Repeated Expenses and Accurate Timestamps
-- Description:
--   1. Drop unique index idx_unique_mandatory_period_expense that prevented recording
--      the same expense category more than once per period/month.
--   2. Add non-unique index for performance.
--   3. Ensure record_expense_transaction captures created_at timestamp and returns it.

-- 1. Drop the unique constraint index blocking repeated entries
DROP INDEX IF EXISTS public.idx_unique_mandatory_period_expense;

-- 2. Create non-unique index for query performance across periods
CREATE INDEX IF NOT EXISTS idx_expense_transactions_def_period
    ON public.expense_transactions (definition_id, applicable_period)
    WHERE status = 'completed';

-- 3. Update record_expense_transaction RPC
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
    v_now TIMESTAMPTZ;
BEGIN
    v_caller_id := auth.uid();
    v_now := clock_timestamp();

    -- Validate amount
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Expense amount must be greater than zero.';
    END IF;

    -- Validate payment method
    IF p_payment_method NOT IN ('cash', 'upi', 'bank_transfer', 'card', 'other') THEN
        RAISE EXCEPTION 'Invalid payment method: %', p_payment_method;
    END IF;

    IF p_definition_id IS NOT NULL THEN
        -- Category Expense (selected from Admin definitions)
        SELECT * INTO v_def FROM public.expense_definitions WHERE id = p_definition_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Expense category definition not found.';
        END IF;

        IF NOT v_def.is_active THEN
            RAISE EXCEPTION 'Cannot record against an inactive expense category.';
        END IF;

        v_expense_name := v_def.name;
        v_expense_type := v_def.expense_type;
        v_frequency := v_def.frequency;
        v_is_fixed := true;
        v_period := COALESCE(NULLIF(trim(p_applicable_period), ''), TO_CHAR(p_expense_date, 'YYYY-MM'));
    ELSE
        -- Ad-hoc / Custom Expense (created on-the-fly by cashier)
        IF p_custom_name IS NULL OR trim(p_custom_name) = '' THEN
            RAISE EXCEPTION 'Custom expense name is required for ad-hoc expenses.';
        END IF;

        v_expense_name := trim(p_custom_name);
        v_expense_type := 'occasional';
        v_frequency := 'as_needed';
        v_is_fixed := false;
        v_period := TO_CHAR(p_expense_date, 'YYYY-MM');
    END IF;

    -- Insert transaction with immutable snapshots and exact timestamp
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
        v_now,
        v_now
    ) RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'expense_name', v_expense_name,
        'amount', ROUND(p_amount, 2),
        'expense_date', p_expense_date,
        'payment_method', p_payment_method,
        'created_at', v_now,
        'sub_expenses', COALESCE(p_sub_expenses, '[]'::jsonb)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_expense_transaction(UUID, VARCHAR, NUMERIC, VARCHAR, TEXT, VARCHAR, DATE, JSONB) TO authenticated;
