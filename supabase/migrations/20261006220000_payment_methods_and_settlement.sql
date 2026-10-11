-- ============================================================================
-- Migration: Payment Methods Configuration & Settlement Support
-- Date: 2026-10-06
-- Description:
--   1. Creates centralized `payment_methods` configuration table.
--   2. Seeds initial methods (Cash & UPI enabled; Card, Bank Transfer, Net Banking disabled).
--   3. Relaxes legacy check constraints on payments and expense_transactions.
-- ============================================================================

-- 1. Create payment_methods configuration table
CREATE TABLE IF NOT EXISTS public.payment_methods (
    id            VARCHAR(50)   PRIMARY KEY,
    name          VARCHAR(100)  NOT NULL,
    is_enabled    BOOLEAN       NOT NULL DEFAULT true,
    display_order INT           NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.payment_methods ENABLE ROW LEVEL SECURITY;

-- Allow all authenticated users to read payment methods
CREATE POLICY "Allow authenticated read payment_methods"
    ON public.payment_methods FOR SELECT
    TO authenticated
    USING (true);

-- Allow authenticated (admin/cashier) to update payment_methods
CREATE POLICY "Allow authenticated manage payment_methods"
    ON public.payment_methods FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);

-- Seed initial default payment methods
INSERT INTO public.payment_methods (id, name, is_enabled, display_order)
VALUES
    ('cash', 'Cash', true, 1),
    ('upi', 'UPI', true, 2),
    ('card', 'Card', false, 3),
    ('bank_transfer', 'Bank Transfer', false, 4),
    ('net_banking', 'Net Banking', false, 5)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    display_order = EXCLUDED.display_order;

-- 2. Relax payment_method constraints if present
DO $$
BEGIN
    -- Drop legacy constraint on payments if it restricts to only ('cash', 'upi', 'card')
    IF EXISTS (
        SELECT 1 FROM information_schema.constraint_column_usage
        WHERE table_name = 'payments' AND constraint_name = 'chk_payments_method'
    ) THEN
        ALTER TABLE public.payments DROP CONSTRAINT chk_payments_method;
    END IF;

    -- Drop legacy constraint on expense_transactions if it restricts
    IF EXISTS (
        SELECT 1 FROM information_schema.constraint_column_usage
        WHERE table_name = 'expense_transactions' AND constraint_name = 'chk_expense_transactions_method'
    ) THEN
        ALTER TABLE public.expense_transactions DROP CONSTRAINT chk_expense_transactions_method;
    END IF;
END $$;
