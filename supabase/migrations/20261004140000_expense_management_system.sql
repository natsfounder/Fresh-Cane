-- =============================================================================
-- Migration: 20261004140000_expense_management_system.sql
-- Description:
--   1. Create public.expense_definitions table for Admin-configured expense templates.
--   2. Create public.expense_transactions table for Cashier-recorded actual financial transactions.
--   3. Unique constraint preventing duplicate recording for same mandatory period.
--   4. RLS policies for Super Admin and Cashier roles.
--   5. Seed common initial expense definitions.
--   6. Scheduling logic function is_expense_applicable_for_month.
--   7. RPC get_cashier_applicable_expenses for Cashier expense workflow.
--   8. RPC record_expense_transaction for atomic recording with snapshot & audit trail.
--   9. RPC get_admin_expense_report for executive reporting, filtering, and export.
-- =============================================================================

-- 1. Create expense_definitions
CREATE TABLE IF NOT EXISTS public.expense_definitions (
    id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    name              VARCHAR(150)  NOT NULL,
    description       TEXT          NULL,
    expense_type      VARCHAR(20)   NOT NULL, -- 'mandatory' or 'occasional'
    frequency         VARCHAR(20)   NOT NULL, -- 'monthly', 'every_2_months', 'every_3_months', 'every_6_months', 'yearly', 'as_needed'
    start_date        DATE          NOT NULL DEFAULT CURRENT_DATE,
    is_active         BOOLEAN       NOT NULL DEFAULT true,
    created_by        UUID          NULL REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    updated_by        UUID          NULL REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    created_at        TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT chk_expense_definitions_type CHECK (expense_type IN ('mandatory', 'occasional')),
    CONSTRAINT chk_expense_definitions_freq CHECK (frequency IN ('monthly', 'every_2_months', 'every_3_months', 'every_6_months', 'yearly', 'as_needed'))
);

CREATE INDEX IF NOT EXISTS idx_expense_definitions_active ON public.expense_definitions (is_active, expense_type);

-- 2. Create expense_transactions
CREATE TABLE IF NOT EXISTS public.expense_transactions (
    id                    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    definition_id         UUID          NOT NULL REFERENCES public.expense_definitions(id) ON DELETE RESTRICT,
    expense_name_snapshot VARCHAR(150)  NOT NULL,
    expense_type_snapshot VARCHAR(20)   NOT NULL,
    frequency_snapshot    VARCHAR(20)   NOT NULL,
    applicable_period     VARCHAR(20)   NULL, -- e.g. '2026-10' for mandatory; NULL for occasional
    expense_date          DATE          NOT NULL DEFAULT CURRENT_DATE,
    amount                NUMERIC(10,2) NOT NULL,
    payment_method        VARCHAR(20)   NOT NULL DEFAULT 'cash', -- 'cash', 'upi', 'bank_transfer', 'card', 'other'
    notes                 TEXT          NULL,
    recorded_by           UUID          NOT NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
    status                VARCHAR(20)   NOT NULL DEFAULT 'completed', -- 'completed', 'voided'
    void_reason           TEXT          NULL,
    voided_by             UUID          NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
    voided_at             TIMESTAMPTZ   NULL,
    created_at            TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT chk_expense_transactions_amount CHECK (amount > 0),
    CONSTRAINT chk_expense_transactions_status CHECK (status IN ('completed', 'voided')),
    CONSTRAINT chk_expense_transactions_method CHECK (payment_method IN ('cash', 'upi', 'bank_transfer', 'card', 'other'))
);

-- Unique index preventing duplicate recording for same definition and period
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_mandatory_period_expense
    ON public.expense_transactions (definition_id, applicable_period)
    WHERE applicable_period IS NOT NULL AND status = 'completed';

CREATE INDEX IF NOT EXISTS idx_expense_transactions_date ON public.expense_transactions (expense_date, status);
CREATE INDEX IF NOT EXISTS idx_expense_transactions_def ON public.expense_transactions (definition_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_expense_transactions_recorder ON public.expense_transactions (recorded_by, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_expense_transactions_period ON public.expense_transactions (applicable_period);

-- 3. Enable RLS
ALTER TABLE public.expense_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_transactions ENABLE ROW LEVEL SECURITY;

-- Policies for expense_definitions
DROP POLICY IF EXISTS "Authenticated users can view active expense definitions" ON public.expense_definitions;
CREATE POLICY "Authenticated users can view active expense definitions" ON public.expense_definitions
    FOR SELECT TO authenticated
    USING (
        is_active = true 
        OR EXISTS (
            SELECT 1 FROM public.user_profiles
            WHERE id = auth.uid() AND is_active = true 
              AND (role = 'super_admin' OR 'super_admin' = ANY(assigned_roles))
        )
    );

DROP POLICY IF EXISTS "Super admin full management on expense definitions" ON public.expense_definitions;
CREATE POLICY "Super admin full management on expense definitions" ON public.expense_definitions
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

-- Policies for expense_transactions
DROP POLICY IF EXISTS "Super admin full management on expense transactions" ON public.expense_transactions;
CREATE POLICY "Super admin full management on expense transactions" ON public.expense_transactions
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

DROP POLICY IF EXISTS "Cashier can view and record expense transactions" ON public.expense_transactions;
CREATE POLICY "Cashier can view and record expense transactions" ON public.expense_transactions
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles
            WHERE id = auth.uid() AND is_active = true 
              AND (role = 'cashier' OR 'cashier' = ANY(assigned_roles) OR role = 'super_admin' OR 'super_admin' = ANY(assigned_roles))
        )
    );

DROP POLICY IF EXISTS "Cashier can insert expense transactions" ON public.expense_transactions;
CREATE POLICY "Cashier can insert expense transactions" ON public.expense_transactions
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_profiles
            WHERE id = auth.uid() AND is_active = true 
              AND (role = 'cashier' OR 'cashier' = ANY(assigned_roles) OR role = 'super_admin' OR 'super_admin' = ANY(assigned_roles))
        )
    );

-- 4. Seed initial standard expense definitions
INSERT INTO public.expense_definitions (name, description, expense_type, frequency, start_date, is_active)
VALUES 
    ('Rent', 'Store rental payment', 'mandatory', 'monthly', '2026-01-01', true),
    ('EB Bill', 'Electricity Board energy bill', 'mandatory', 'monthly', '2026-01-01', true),
    ('Internet', 'Broadband and Wi-Fi connection', 'mandatory', 'monthly', '2026-01-01', true),
    ('Staff Salary', 'Monthly staff payroll disbursements', 'mandatory', 'monthly', '2026-01-01', true),
    ('Water Bill', 'Municipal / tanker water supply', 'mandatory', 'monthly', '2026-01-01', true),
    ('AMC Machine Maintenance', 'Sugarcane crusher & POS hardware AMC', 'mandatory', 'every_3_months', '2026-01-01', true),
    ('Store Insurance', 'Café fire and commercial liability policy', 'mandatory', 'every_6_months', '2026-01-01', true),
    ('AC Repair & Servicing', 'Air conditioning filter cleaning & refrigerant repair', 'occasional', 'as_needed', '2026-01-01', true),
    ('Emergency Plumbing & Repairs', 'Plumbing leaks, electrical fixings, hardware repair', 'occasional', 'as_needed', '2026-01-01', true),
    ('Stationery & Printing', 'Billing thermal paper rolls, receipts, office supplies', 'occasional', 'as_needed', '2026-01-01', true),
    ('Transport & Logistics', 'Cane delivery conveyance & freight charges', 'occasional', 'as_needed', '2026-01-01', true),
    ('Miscellaneous', 'Other operational petty expenses', 'occasional', 'as_needed', '2026-01-01', true)
ON CONFLICT DO NOTHING;

-- 5. Helper function: is_expense_applicable_for_month
CREATE OR REPLACE FUNCTION public.is_expense_applicable_for_month(
    p_start_date DATE,
    p_frequency VARCHAR,
    p_target_date DATE
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_diff_months INTEGER;
BEGIN
    -- If occasional / as_needed, it does not follow a mandatory monthly schedule
    IF p_frequency = 'as_needed' THEN
        RETURN FALSE;
    END IF;

    -- Calculate difference in whole months: (Y2 - Y1)*12 + (M2 - M1)
    v_diff_months := (EXTRACT(YEAR FROM p_target_date)::INTEGER - EXTRACT(YEAR FROM p_start_date)::INTEGER) * 12 
                   + (EXTRACT(MONTH FROM p_target_date)::INTEGER - EXTRACT(MONTH FROM p_start_date)::INTEGER);

    -- If target month is prior to start month, not yet applicable
    IF v_diff_months < 0 THEN
        RETURN FALSE;
    END IF;

    -- Check frequency recurrence
    CASE p_frequency
        WHEN 'monthly' THEN
            RETURN TRUE;
        WHEN 'every_2_months' THEN
            RETURN (v_diff_months % 2 = 0);
        WHEN 'every_3_months' THEN
            RETURN (v_diff_months % 3 = 0);
        WHEN 'every_6_months' THEN
            RETURN (v_diff_months % 6 = 0);
        WHEN 'yearly' THEN
            RETURN (v_diff_months % 12 = 0);
        ELSE
            RETURN FALSE;
    END CASE;
END;
$$;

-- 6. RPC: get_cashier_applicable_expenses
CREATE OR REPLACE FUNCTION public.get_cashier_applicable_expenses(
    p_target_date DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_target_period VARCHAR(20);
    v_mandatory_list JSONB;
    v_occasional_list JSONB;
BEGIN
    v_target_period := TO_CHAR(p_target_date, 'YYYY-MM');

    -- Build list of applicable mandatory expenses for the target period
    SELECT COALESCE(jsonb_agg(item ORDER BY item->>'name' ASC), '[]'::jsonb)
    INTO v_mandatory_list
    FROM (
        SELECT jsonb_build_object(
            'definition_id', ed.id,
            'name', ed.name,
            'description', ed.description,
            'expense_type', ed.expense_type,
            'frequency', ed.frequency,
            'start_date', ed.start_date,
            'applicable_period', v_target_period,
            'is_recorded', (et.id IS NOT NULL),
            'transaction_id', et.id,
            'recorded_amount', et.amount,
            'payment_method', et.payment_method,
            'notes', et.notes,
            'expense_date', et.expense_date,
            'recorded_by_name', up.full_name,
            'recorded_at', et.created_at
        ) AS item
        FROM public.expense_definitions ed
        LEFT JOIN public.expense_transactions et 
            ON et.definition_id = ed.id 
           AND et.applicable_period = v_target_period 
           AND et.status = 'completed'
        LEFT JOIN public.user_profiles up ON up.id = et.recorded_by
        WHERE ed.is_active = true 
          AND ed.expense_type = 'mandatory'
          AND public.is_expense_applicable_for_month(ed.start_date, ed.frequency, p_target_date) = true
    ) sub;

    -- Build list of active occasional definitions
    SELECT COALESCE(jsonb_agg(item ORDER BY item->>'name' ASC), '[]'::jsonb)
    INTO v_occasional_list
    FROM (
        SELECT jsonb_build_object(
            'definition_id', ed.id,
            'name', ed.name,
            'description', ed.description,
            'expense_type', ed.expense_type,
            'frequency', ed.frequency,
            'start_date', ed.start_date
        ) AS item
        FROM public.expense_definitions ed
        WHERE ed.is_active = true 
          AND ed.expense_type = 'occasional'
    ) sub;

    RETURN jsonb_build_object(
        'target_date', p_target_date,
        'target_period', v_target_period,
        'mandatory_expenses', v_mandatory_list,
        'occasional_definitions', v_occasional_list
    );
END;
$$;

-- 7. RPC: record_expense_transaction
CREATE OR REPLACE FUNCTION public.record_expense_transaction(
    p_definition_id UUID,
    p_amount NUMERIC,
    p_payment_method VARCHAR,
    p_notes TEXT DEFAULT NULL,
    p_applicable_period VARCHAR DEFAULT NULL,
    p_expense_date DATE DEFAULT CURRENT_DATE
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
    v_created_tx JSONB;
BEGIN
    v_caller_id := auth.uid();

    -- Verify definition
    SELECT * INTO v_def FROM public.expense_definitions WHERE id = p_definition_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Expense definition not found.';
    END IF;

    IF NOT v_def.is_active THEN
        RAISE EXCEPTION 'Cannot record an expense against an inactive definition.';
    END IF;

    -- Verify amount
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Expense amount must be greater than zero.';
    END IF;

    -- Normalize payment method
    IF p_payment_method NOT IN ('cash', 'upi', 'bank_transfer', 'card', 'other') THEN
        RAISE EXCEPTION 'Invalid payment method: %', p_payment_method;
    END IF;

    -- Determine applicable period
    IF v_def.expense_type = 'mandatory' THEN
        v_period := COALESCE(NULLIF(trim(p_applicable_period), ''), TO_CHAR(p_expense_date, 'YYYY-MM'));
        
        -- Prevent duplicate recording for same period
        IF EXISTS (
            SELECT 1 FROM public.expense_transactions 
            WHERE definition_id = p_definition_id 
              AND applicable_period = v_period 
              AND status = 'completed'
        ) THEN
            RAISE EXCEPTION 'Expense for "%" has already been recorded for period %.', v_def.name, v_period;
        END IF;
    ELSE
        -- Occasional expenses do not have a mandatory period restriction
        v_period := NULL;
    END IF;

    -- Insert actual transaction with immutable snapshots
    INSERT INTO public.expense_transactions (
        definition_id,
        expense_name_snapshot,
        expense_type_snapshot,
        frequency_snapshot,
        applicable_period,
        expense_date,
        amount,
        payment_method,
        notes,
        recorded_by,
        status
    ) VALUES (
        v_def.id,
        v_def.name,
        v_def.expense_type,
        v_def.frequency,
        v_period,
        p_expense_date,
        ROUND(p_amount, 2),
        p_payment_method,
        NULLIF(trim(p_notes), ''),
        v_caller_id,
        'completed'
    ) RETURNING id INTO v_tx_id;

    -- Audit log
    INSERT INTO public.audit_logs (
        user_id,
        action,
        entity_type,
        entity_id,
        new_data
    ) VALUES (
        v_caller_id,
        'EXPENSE_RECORDED',
        'expense_transactions',
        v_tx_id::VARCHAR,
        jsonb_build_object(
            'definition_id', v_def.id,
            'name', v_def.name,
            'amount', ROUND(p_amount, 2),
            'payment_method', p_payment_method,
            'applicable_period', v_period,
            'expense_date', p_expense_date
        )
    );

    -- Return newly created transaction
    SELECT jsonb_build_object(
        'id', et.id,
        'definition_id', et.definition_id,
        'expense_name', et.expense_name_snapshot,
        'expense_type', et.expense_type_snapshot,
        'frequency', et.frequency_snapshot,
        'applicable_period', et.applicable_period,
        'expense_date', et.expense_date,
        'amount', et.amount,
        'payment_method', et.payment_method,
        'notes', et.notes,
        'status', et.status,
        'created_at', et.created_at
    ) INTO v_created_tx
    FROM public.expense_transactions et
    WHERE et.id = v_tx_id;

    RETURN v_created_tx;
END;
$$;

-- 8. RPC: get_admin_expense_report
CREATE OR REPLACE FUNCTION public.get_admin_expense_report(
    p_start_date DATE,
    p_end_date DATE,
    p_definition_id UUID DEFAULT NULL,
    p_expense_type VARCHAR DEFAULT NULL,
    p_payment_method VARCHAR DEFAULT NULL,
    p_recorded_by UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_expenses NUMERIC(10,2) := 0.00;
    v_mandatory_expenses NUMERIC(10,2) := 0.00;
    v_occasional_expenses NUMERIC(10,2) := 0.00;
    v_tx_count INTEGER := 0;
    v_records JSONB := '[]'::jsonb;
BEGIN
    -- Summary calculation
    SELECT 
        COALESCE(SUM(amount), 0.00),
        COALESCE(SUM(CASE WHEN expense_type_snapshot = 'mandatory' THEN amount ELSE 0 END), 0.00),
        COALESCE(SUM(CASE WHEN expense_type_snapshot = 'occasional' THEN amount ELSE 0 END), 0.00),
        COUNT(*)::INTEGER
    INTO 
        v_total_expenses,
        v_mandatory_expenses,
        v_occasional_expenses,
        v_tx_count
    FROM public.expense_transactions
    WHERE expense_date >= p_start_date 
      AND expense_date <= p_end_date
      AND status = 'completed'
      AND (p_definition_id IS NULL OR definition_id = p_definition_id)
      AND (p_expense_type IS NULL OR expense_type_snapshot = p_expense_type)
      AND (p_payment_method IS NULL OR payment_method = p_payment_method)
      AND (p_recorded_by IS NULL OR recorded_by = p_recorded_by);

    -- Records calculation
    SELECT COALESCE(jsonb_agg(item ORDER BY item->>'expense_date' DESC, item->>'created_at' DESC), '[]'::jsonb)
    INTO v_records
    FROM (
        SELECT jsonb_build_object(
            'id', et.id,
            'definition_id', et.definition_id,
            'expense_name', et.expense_name_snapshot,
            'expense_type', et.expense_type_snapshot,
            'frequency', et.frequency_snapshot,
            'applicable_period', et.applicable_period,
            'expense_date', et.expense_date,
            'amount', et.amount,
            'payment_method', et.payment_method,
            'notes', et.notes,
            'status', et.status,
            'recorded_by_id', et.recorded_by,
            'recorded_by_name', COALESCE(up.full_name, 'Staff'),
            'created_at', et.created_at
        ) AS item
        FROM public.expense_transactions et
        LEFT JOIN public.user_profiles up ON up.id = et.recorded_by
        WHERE et.expense_date >= p_start_date 
          AND et.expense_date <= p_end_date
          AND et.status = 'completed'
          AND (p_definition_id IS NULL OR et.definition_id = p_definition_id)
          AND (p_expense_type IS NULL OR et.expense_type_snapshot = p_expense_type)
          AND (p_payment_method IS NULL OR et.payment_method = p_payment_method)
          AND (p_recorded_by IS NULL OR et.recorded_by = p_recorded_by)
    ) sub;

    RETURN jsonb_build_object(
        'start_date', p_start_date,
        'end_date', p_end_date,
        'summary', jsonb_build_object(
            'total_expenses', v_total_expenses,
            'mandatory_expenses', v_mandatory_expenses,
            'occasional_expenses', v_occasional_expenses,
            'transactions_count', v_tx_count
        ),
        'records_count', v_tx_count,
        'records', v_records
    );
END;
$$;
