-- ============================================================================
-- Migration: Add Sub-Expenses Support to Expense Definitions & Transactions
-- Date: 2026-10-06
-- Description:
--   Adds optional JSONB columns `sub_expenses` to `expense_definitions` and
--   `expense_transactions` to natively store itemized sub-expenses
--   (e.g., Category: "Fruit" with sub-items: "Apple", "Banana", "Watermelon").
--   The application layer also handles backward-compatible metadata tags
--   in `description` and `notes` so no downtime occurs even before this
--   migration is executed.
-- ============================================================================

-- 1. Add sub_expenses JSONB column to expense_definitions (if not exists)
ALTER TABLE public.expense_definitions 
ADD COLUMN IF NOT EXISTS sub_expenses JSONB DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.expense_definitions.sub_expenses IS 
'Pre-defined default sub-expense items (e.g. ["Apple", "Banana", "Watermelon"]) configured by Admin.';

-- 2. Add sub_expenses JSONB column to expense_transactions (if not exists)
ALTER TABLE public.expense_transactions 
ADD COLUMN IF NOT EXISTS sub_expenses JSONB DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.expense_transactions.sub_expenses IS 
'Recorded itemized sub-expense items with individual amounts: [{"name": "Apple", "amount": 50.0}, ...]';

-- 3. Update existing records with default empty array if NULL
UPDATE public.expense_definitions 
SET sub_expenses = '[]'::jsonb 
WHERE sub_expenses IS NULL;

UPDATE public.expense_transactions 
SET sub_expenses = '[]'::jsonb 
WHERE sub_expenses IS NULL;
