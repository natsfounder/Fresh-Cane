-- Migration: 20261023081500_grant_helper_functions_and_menu_select.sql
-- Description: Allow is_staff and helper functions to be executed by anon/authenticated to avoid 42501 errors on public reads.

GRANT EXECUTE ON FUNCTION public.is_staff() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_cashier_or_admin() TO anon, authenticated;

-- Ensure categories and menu_items can be read
DROP POLICY IF EXISTS "Anyone can read categories" ON public.categories;
CREATE POLICY "Anyone can read categories" ON public.categories FOR SELECT USING (true);

DROP POLICY IF EXISTS "Anyone can read menu_items" ON public.menu_items;
CREATE POLICY "Anyone can read menu_items" ON public.menu_items FOR SELECT USING (true);
