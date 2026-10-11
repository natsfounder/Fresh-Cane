-- Migration: Product-Specific Add-ons
-- Description:
--   1. Add menu_item_id column to public.menu_addons table referencing public.menu_items(id).
--   2. Drop global UNIQUE(name) constraint on menu_addons so different products can have add-ons with similar names.
--   3. Create index on menu_item_id for fast product-specific lookups.
--   4. Ensure RLS policies and permissions allow full management by super_admin and view by all.

ALTER TABLE public.menu_addons 
    ADD COLUMN IF NOT EXISTS menu_item_id UUID REFERENCES public.menu_items(id) ON DELETE CASCADE;

ALTER TABLE public.menu_addons 
    DROP CONSTRAINT IF EXISTS menu_addons_name_key;

CREATE INDEX IF NOT EXISTS idx_menu_addons_menu_item_id 
    ON public.menu_addons (menu_item_id);

GRANT SELECT ON public.menu_addons TO authenticated, anon;
