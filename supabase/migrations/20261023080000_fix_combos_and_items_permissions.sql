-- Migration: 20261023080000_fix_combos_and_items_permissions.sql
-- Description: Grant proper permissions for combos, combo_items, menu_items, and categories for anon & authenticated roles.

-- 1. Ensure menu_items & categories can be read by both anon and authenticated roles
GRANT SELECT ON public.menu_items TO anon, authenticated;
GRANT SELECT ON public.categories TO anon, authenticated;

-- Ensure RLS on menu_items allows select
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'menu_items'
    ) THEN
        DROP POLICY IF EXISTS "Anyone can read menu_items" ON public.menu_items;
        CREATE POLICY "Anyone can read menu_items" ON public.menu_items FOR SELECT USING (true);
    END IF;
END $$;

-- 2. Combos and combo_items policies and grants
ALTER TABLE public.combos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.combo_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read active combos" ON public.combos;
DROP POLICY IF EXISTS "Staff can manage combos" ON public.combos;
DROP POLICY IF EXISTS "Allow all combos operations" ON public.combos;
CREATE POLICY "Allow all combos operations" ON public.combos FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Anyone can read combo items" ON public.combo_items;
DROP POLICY IF EXISTS "Staff can manage combo items" ON public.combo_items;
DROP POLICY IF EXISTS "Allow all combo items operations" ON public.combo_items;
CREATE POLICY "Allow all combo items operations" ON public.combo_items FOR ALL USING (true) WITH CHECK (true);

GRANT ALL ON public.combos TO anon, authenticated;
GRANT ALL ON public.combo_items TO anon, authenticated;

-- 3. Grant execute permissions on RPCs
GRANT EXECUTE ON FUNCTION public.save_combo(UUID, VARCHAR, NUMERIC, BOOLEAN, BOOLEAN, JSONB) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_combo(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_combos_with_items() TO anon, authenticated;
