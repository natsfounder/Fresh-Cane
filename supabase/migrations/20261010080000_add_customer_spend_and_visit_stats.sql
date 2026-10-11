-- Migration: 20261010080000_add_customer_spend_and_visit_stats.sql
-- Description: Adds total_spend and visit_count columns to public.customers,
--              backfills historical customer spending from paid bills,
--              and sets up automatic trigger to keep customer stats synced.

-- 1. Add columns to public.customers
ALTER TABLE public.customers
    ADD COLUMN IF NOT EXISTS total_spend NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS visit_count INTEGER NOT NULL DEFAULT 0;

-- 2. Index for sorting customers by spend and visits
CREATE INDEX IF NOT EXISTS idx_customers_total_spend ON public.customers (total_spend DESC);
CREATE INDEX IF NOT EXISTS idx_customers_visit_count ON public.customers (visit_count DESC);

-- 3. Backfill total_spend and visit_count from paid bills
DO $$
BEGIN
    WITH customer_stats AS (
        SELECT 
            c.id,
            COALESCE(COUNT(DISTINCT b.id), 0)::INTEGER AS calc_visits,
            COALESCE(SUM(b.final_amount), 0.00)::NUMERIC(10,2) AS calc_spend
        FROM public.customers c
        LEFT JOIN public.bills b ON (
            (b.customer_phone_snapshot IS NOT NULL AND b.customer_phone_snapshot = c.phone)
            OR b.order_id IN (SELECT o.id FROM public.orders o WHERE o.customer_id = c.id)
        ) AND b.status = 'paid'
        GROUP BY c.id
    )
    UPDATE public.customers cust
    SET 
        visit_count = cs.calc_visits,
        total_spend = cs.calc_spend
    FROM customer_stats cs
    WHERE cust.id = cs.id;
END;
$$;

-- 4. Trigger function to keep customer stats in sync with bill settlements
CREATE OR REPLACE FUNCTION public.fn_sync_customer_bill_stats()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_phone VARCHAR(10);
    v_cust_id UUID;
BEGIN
    -- Bill transitioned to paid or created as paid
    IF (TG_OP = 'INSERT' AND NEW.status = 'paid') OR
       (TG_OP = 'UPDATE' AND NEW.status = 'paid' AND (OLD.status IS DISTINCT FROM 'paid')) THEN
       
        v_phone := NEW.customer_phone_snapshot;
        IF v_phone IS NULL THEN
            SELECT customer_phone, customer_id
            INTO v_phone, v_cust_id
            FROM public.orders
            WHERE id = NEW.order_id;
        END IF;

        IF v_phone IS NOT NULL AND length(trim(v_phone)) = 10 THEN
            UPDATE public.customers
            SET 
                total_spend = total_spend + NEW.final_amount,
                visit_count = visit_count + 1,
                updated_at = now()
            WHERE phone = v_phone;
        ELSIF v_cust_id IS NOT NULL THEN
            UPDATE public.customers
            SET 
                total_spend = total_spend + NEW.final_amount,
                visit_count = visit_count + 1,
                updated_at = now()
            WHERE id = v_cust_id;
        END IF;
    END IF;

    -- Bill was paid but has now been voided / reverted
    IF (TG_OP = 'UPDATE' AND OLD.status = 'paid' AND NEW.status = 'voided') THEN
        v_phone := NEW.customer_phone_snapshot;
        IF v_phone IS NULL THEN
            SELECT customer_phone, customer_id
            INTO v_phone, v_cust_id
            FROM public.orders
            WHERE id = NEW.order_id;
        END IF;

        IF v_phone IS NOT NULL AND length(trim(v_phone)) = 10 THEN
            UPDATE public.customers
            SET 
                total_spend = GREATEST(0.00, total_spend - OLD.final_amount),
                visit_count = GREATEST(0, visit_count - 1),
                updated_at = now()
            WHERE phone = v_phone;
        ELSIF v_cust_id IS NOT NULL THEN
            UPDATE public.customers
            SET 
                total_spend = GREATEST(0.00, total_spend - OLD.final_amount),
                visit_count = GREATEST(0, visit_count - 1),
                updated_at = now()
            WHERE id = v_cust_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_customer_bill_stats ON public.bills;
CREATE TRIGGER trg_sync_customer_bill_stats
    AFTER INSERT OR UPDATE OF status, final_amount
    ON public.bills
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_sync_customer_bill_stats();
