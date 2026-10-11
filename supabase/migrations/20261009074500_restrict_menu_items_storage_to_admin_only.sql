-- Migration: 20261009074500_restrict_menu_items_storage_to_admin_only.sql
-- Description: Restrict INSERT, UPDATE, and DELETE policies on menu-items storage bucket
-- strictly to super_admin (Admin only). Cashiers and servers cannot modify photos.

DO $$
BEGIN
    DROP POLICY IF EXISTS "Staff Upload Menu Items" ON storage.objects;
    DROP POLICY IF EXISTS "Staff Update Menu Items" ON storage.objects;
    DROP POLICY IF EXISTS "Staff Delete Menu Items" ON storage.objects;
    DROP POLICY IF EXISTS "Admin Upload Menu Items" ON storage.objects;
    DROP POLICY IF EXISTS "Admin Update Menu Items" ON storage.objects;
    DROP POLICY IF EXISTS "Admin Delete Menu Items" ON storage.objects;
END $$;

-- 1. Admin ONLY upload access
CREATE POLICY "Admin Upload Menu Items"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'menu-items'
    AND EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE id = auth.uid()
          AND is_active = true
          AND (role = 'super_admin' OR 'super_admin' = ANY(assigned_roles))
    )
);

-- 2. Admin ONLY update access
CREATE POLICY "Admin Update Menu Items"
ON storage.objects FOR UPDATE
TO authenticated
USING (
    bucket_id = 'menu-items'
    AND EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE id = auth.uid()
          AND is_active = true
          AND (role = 'super_admin' OR 'super_admin' = ANY(assigned_roles))
    )
);

-- 3. Admin ONLY delete access
CREATE POLICY "Admin Delete Menu Items"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'menu-items'
    AND EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE id = auth.uid()
          AND is_active = true
          AND (role = 'super_admin' OR 'super_admin' = ANY(assigned_roles))
    )
);
