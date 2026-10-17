-- Migration: 20261011180000_daily_settlement_overrides.sql
-- Description: Isolated daily settlement overrides for ₹0 opening/closing balances with RPC-only writes and strict audit trail.
-- Status: PREPARED FOR REVIEW (NOT APPLIED TO PRODUCTION YET)

-- 1. Create table for isolated settlement overrides
CREATE TABLE IF NOT EXISTS public.daily_settlement_overrides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    settlement_date DATE NOT NULL,
    opening_cash NUMERIC DEFAULT NULL CHECK (opening_cash IS NULL OR opening_cash >= 0),
    opening_upi NUMERIC DEFAULT NULL CHECK (opening_upi IS NULL OR opening_upi >= 0),
    closing_cash NUMERIC DEFAULT NULL CHECK (closing_cash IS NULL OR closing_cash >= 0),
    closing_upi NUMERIC DEFAULT NULL CHECK (closing_upi IS NULL OR closing_upi >= 0),
    opening_reason TEXT,
    closing_reason TEXT,
    created_by UUID REFERENCES auth.users(id),
    updated_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT daily_settlement_overrides_date_unique UNIQUE (settlement_date)
);

-- 2. Enable Row-Level Security (RLS)
ALTER TABLE public.daily_settlement_overrides ENABLE ROW LEVEL SECURITY;

-- 3. Read policy: All authenticated staff can view overrides for reporting consistency
CREATE POLICY "Staff can view daily settlement overrides"
ON public.daily_settlement_overrides FOR SELECT
TO authenticated
USING (public.is_staff());

-- 4. Direct Table Grants: Strictly READ-ONLY for authenticated users.
-- Writes are REVOKED and strictly routed through SECURITY DEFINER RPCs.
REVOKE INSERT, UPDATE, DELETE ON public.daily_settlement_overrides FROM authenticated, anon, public;
GRANT SELECT ON public.daily_settlement_overrides TO authenticated;

-- 5. Atomic RPC with Backend Zero-Validation, SuperAdmin Guard, and Audit Logging
CREATE OR REPLACE FUNCTION public.save_daily_settlement_override(
    p_settlement_date DATE,
    p_override_type VARCHAR, -- 'opening' or 'closing'
    p_cash_amount NUMERIC,
    p_upi_amount NUMERIC,
    p_reason TEXT,
    p_start_of_day_utc TIMESTAMPTZ,
    p_end_of_day_utc TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID;
    v_old_data JSONB;
    v_new_row public.daily_settlement_overrides%ROWTYPE;
    v_calculated_opening_cash NUMERIC := 0.0;
    v_calculated_opening_upi NUMERIC := 0.0;
    v_calculated_opening_total NUMERIC := 0.0;
    v_sales_cash NUMERIC := 0.0;
    v_sales_upi NUMERIC := 0.0;
    v_exp_cash NUMERIC := 0.0;
    v_exp_upi NUMERIC := 0.0;
    v_effective_opening_cash NUMERIC := 0.0;
    v_effective_opening_upi NUMERIC := 0.0;
    v_calculated_closing_total NUMERIC := 0.0;
    v_existing_row public.daily_settlement_overrides%ROWTYPE;
BEGIN
    -- 1. Authorization: Super Admin check
    IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Access denied: Super Administrator privileges required.';
    END IF;

    -- 2. Input validation
    IF p_reason IS NULL OR trim(p_reason) = '' THEN
        RAISE EXCEPTION 'A non-empty audit reason is mandatory for manual settlement adjustments.';
    END IF;

    IF p_cash_amount IS NULL OR p_cash_amount < 0 OR p_upi_amount IS NULL OR p_upi_amount < 0 THEN
        RAISE EXCEPTION 'Amounts cannot be null or negative.';
    END IF;

    v_user_id := auth.uid();

    -- 3. Calculate natural Opening Balance prior to p_start_of_day_utc
    SELECT 
        COALESCE(SUM(CASE WHEN LOWER(payment_method) = 'cash' THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN LOWER(payment_method) = 'upi' THEN amount ELSE 0 END), 0)
    INTO v_calculated_opening_cash, v_calculated_opening_upi
    FROM public.payments
    WHERE status = 'completed' AND created_at < p_start_of_day_utc;

    -- Subtract prior non-voided expenses
    SELECT 
        v_calculated_opening_cash - COALESCE(SUM(CASE WHEN LOWER(payment_method) = 'cash' THEN amount ELSE 0 END), 0),
        v_calculated_opening_upi - COALESCE(SUM(CASE WHEN LOWER(payment_method) = 'upi' THEN amount ELSE 0 END), 0)
    INTO v_calculated_opening_cash, v_calculated_opening_upi
    FROM public.expense_transactions
    WHERE status <> 'voided' AND created_at < p_start_of_day_utc;

    v_calculated_opening_total := v_calculated_opening_cash + v_calculated_opening_upi;

    -- Fetch existing override record if any
    SELECT * INTO v_existing_row
    FROM public.daily_settlement_overrides
    WHERE settlement_date = p_settlement_date;

    IF FOUND THEN
        v_old_data := to_jsonb(v_existing_row);
    ELSE
        v_old_data := NULL;
    END IF;

    -- 4. Enforce ZERO-ONLY condition at the database level
    IF p_override_type = 'opening' THEN
        IF v_calculated_opening_total <> 0.0 THEN
            RAISE EXCEPTION 'Accounting constraint violation: Manual opening entry is only permitted when natural calculated opening is exactly 0. Calculated opening is %', v_calculated_opening_total;
        END IF;

        INSERT INTO public.daily_settlement_overrides (
            settlement_date, opening_cash, opening_upi, opening_reason, created_by, updated_by, updated_at
        )
        VALUES (
            p_settlement_date, p_cash_amount, p_upi_amount, trim(p_reason), v_user_id, v_user_id, now()
        )
        ON CONFLICT (settlement_date) DO UPDATE
        SET opening_cash = EXCLUDED.opening_cash,
            opening_upi = EXCLUDED.opening_upi,
            opening_reason = EXCLUDED.opening_reason,
            updated_by = v_user_id,
            updated_at = now()
        RETURNING * INTO v_new_row;

    ELSIF p_override_type = 'closing' THEN
        -- Calculate today's sales and expenses
        SELECT 
            COALESCE(SUM(CASE WHEN LOWER(payment_method) = 'cash' THEN amount ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN LOWER(payment_method) = 'upi' THEN amount ELSE 0 END), 0)
        INTO v_sales_cash, v_sales_upi
        FROM public.payments
        WHERE status = 'completed' AND created_at >= p_start_of_day_utc AND created_at < p_end_of_day_utc;

        SELECT 
            COALESCE(SUM(CASE WHEN LOWER(payment_method) = 'cash' THEN amount ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN LOWER(payment_method) = 'upi' THEN amount ELSE 0 END), 0)
        INTO v_exp_cash, v_exp_upi
        FROM public.expense_transactions
        WHERE status <> 'voided' AND created_at >= p_start_of_day_utc AND created_at < p_end_of_day_utc;

        v_effective_opening_cash := COALESCE(v_existing_row.opening_cash, v_calculated_opening_cash);
        v_effective_opening_upi := COALESCE(v_existing_row.opening_upi, v_calculated_opening_upi);

        v_calculated_closing_total := (v_effective_opening_cash + v_sales_cash - v_exp_cash) +
                                      (v_effective_opening_upi + v_sales_upi - v_exp_upi);

        IF v_calculated_closing_total <> 0.0 THEN
            RAISE EXCEPTION 'Accounting constraint violation: Manual closing entry is only permitted when calculated closing is exactly 0. Calculated closing is %', v_calculated_closing_total;
        END IF;

        INSERT INTO public.daily_settlement_overrides (
            settlement_date, closing_cash, closing_upi, closing_reason, created_by, updated_by, updated_at
        )
        VALUES (
            p_settlement_date, p_cash_amount, p_upi_amount, trim(p_reason), v_user_id, v_user_id, now()
        )
        ON CONFLICT (settlement_date) DO UPDATE
        SET closing_cash = EXCLUDED.closing_cash,
            closing_upi = EXCLUDED.closing_upi,
            closing_reason = EXCLUDED.closing_reason,
            updated_by = v_user_id,
            updated_at = now()
        RETURNING * INTO v_new_row;

    ELSE
        RAISE EXCEPTION 'Invalid override_type: must be either opening or closing';
    END IF;

    -- 5. Audit Logging in public.audit_logs (Atomic)
    INSERT INTO public.audit_logs (
        user_id, action, entity_type, entity_id, old_data, new_data
    )
    VALUES (
        v_user_id,
        'SETTLEMENT_OVERRIDE_' || UPPER(p_override_type),
        'daily_settlement_overrides',
        p_settlement_date::text,
        v_old_data,
        to_jsonb(v_new_row)
    );

    RETURN to_jsonb(v_new_row);
END;
$$;

-- 6. Atomic Reset RPC to restore natural 0
CREATE OR REPLACE FUNCTION public.reset_daily_settlement_override(
    p_settlement_date DATE,
    p_override_type VARCHAR, -- 'opening', 'closing', or 'both'
    p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID;
    v_old_data JSONB;
    v_new_row public.daily_settlement_overrides%ROWTYPE;
BEGIN
    IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Access denied: Super Administrator privileges required.';
    END IF;

    IF p_reason IS NULL OR trim(p_reason) = '' THEN
        RAISE EXCEPTION 'A non-empty audit reason is mandatory for resetting adjustments.';
    END IF;

    v_user_id := auth.uid();

    SELECT * INTO v_new_row
    FROM public.daily_settlement_overrides
    WHERE settlement_date = p_settlement_date;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', true, 'message', 'No override to reset.');
    END IF;

    v_old_data := to_jsonb(v_new_row);

    IF p_override_type = 'opening' THEN
        UPDATE public.daily_settlement_overrides
        SET opening_cash = NULL,
            opening_upi = NULL,
            opening_reason = NULL,
            updated_by = v_user_id,
            updated_at = now()
        WHERE settlement_date = p_settlement_date
        RETURNING * INTO v_new_row;
    ELSIF p_override_type = 'closing' THEN
        UPDATE public.daily_settlement_overrides
        SET closing_cash = NULL,
            closing_upi = NULL,
            closing_reason = NULL,
            updated_by = v_user_id,
            updated_at = now()
        WHERE settlement_date = p_settlement_date
        RETURNING * INTO v_new_row;
    ELSE
        UPDATE public.daily_settlement_overrides
        SET opening_cash = NULL,
            opening_upi = NULL,
            opening_reason = NULL,
            closing_cash = NULL,
            closing_upi = NULL,
            closing_reason = NULL,
            updated_by = v_user_id,
            updated_at = now()
        WHERE settlement_date = p_settlement_date
        RETURNING * INTO v_new_row;
    END IF;

    INSERT INTO public.audit_logs (
        user_id, action, entity_type, entity_id, old_data, new_data
    )
    VALUES (
        v_user_id,
        'SETTLEMENT_OVERRIDE_RESET',
        'daily_settlement_overrides',
        p_settlement_date::text,
        v_old_data,
        jsonb_build_object('reset_type', p_override_type, 'reason', trim(p_reason), 'remaining', to_jsonb(v_new_row))
    );

    RETURN to_jsonb(v_new_row);
END;
$$;
