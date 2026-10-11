-- Migration: 20261010091000_enhanced_product_offers_and_discounts.sql
-- Description: Supports product-specific offers, BOGO deals, and seamless name/title compatibility.

-- 1. Modify discount_type check to allow 'bogo'
ALTER TABLE public.offers
    DROP CONSTRAINT IF EXISTS offers_discount_type_check;

ALTER TABLE public.offers
    ADD CONSTRAINT offers_discount_type_check
    CHECK (discount_type IN ('percentage', 'flat', 'bogo'));

-- 2. Add applicable_product_ids, buy_quantity, get_quantity, and compatibility fields
ALTER TABLE public.offers
    ADD COLUMN IF NOT EXISTS applicable_product_ids UUID[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS buy_quantity INTEGER NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS get_quantity INTEGER NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS title VARCHAR(150),
    ADD COLUMN IF NOT EXISTS start_date TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS end_date TIMESTAMPTZ;

-- 3. Sync title <-> name and dates automatically with a trigger
CREATE OR REPLACE FUNCTION public.fn_sync_offers_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Synchronize title and name
    IF NEW.title IS NOT NULL AND (NEW.name IS NULL OR NEW.name = '') THEN
        NEW.name := NEW.title;
    ELSIF NEW.name IS NOT NULL AND (NEW.title IS NULL OR NEW.title = '') THEN
        NEW.title := NEW.name;
    ELSIF NEW.title IS NOT NULL AND NEW.name IS NOT NULL THEN
        NEW.name := NEW.title;
    END IF;

    -- Synchronize dates
    IF NEW.start_date IS NOT NULL AND NEW.valid_from IS NULL THEN
        NEW.valid_from := NEW.start_date::DATE;
    ELSIF NEW.valid_from IS NOT NULL AND NEW.start_date IS NULL THEN
        NEW.start_date := NEW.valid_from::TIMESTAMPTZ;
    END IF;

    IF NEW.end_date IS NOT NULL AND NEW.valid_until IS NULL THEN
        NEW.valid_until := NEW.end_date::DATE;
    ELSIF NEW.valid_until IS NOT NULL AND NEW.end_date IS NULL THEN
        NEW.end_date := NEW.valid_until::TIMESTAMPTZ;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_offers_columns ON public.offers;
CREATE TRIGGER trg_sync_offers_columns
    BEFORE INSERT OR UPDATE
    ON public.offers
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_sync_offers_columns();

-- 4. Backfill title, start_date, end_date for existing rows
UPDATE public.offers
SET 
    title = COALESCE(title, name),
    start_date = COALESCE(start_date, valid_from::TIMESTAMPTZ),
    end_date = COALESCE(end_date, valid_until::TIMESTAMPTZ)
WHERE title IS NULL OR start_date IS NULL;
