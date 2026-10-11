-- Migration: 20261009083000_storage_bucket_webp_and_3mb_limit.sql
-- Description:
-- 1. Create SECURITY DEFINER helper function is_admin_for_storage() to reliably check
--    super_admin privileges from the storage schema context.
-- 2. Update 'menu-items' storage bucket file_size_limit to 3MB (3145728 bytes).
-- 3. Ensure storage policies for INSERT, UPDATE (with WITH CHECK), and DELETE
--    use is_admin_for_storage().

-- 1. Helper function
CREATE OR REPLACE FUNCTION public.is_admin_for_storage()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE id = auth.uid()
          AND is_active = true
          AND (role = 'super_admin' OR 'super_admin' = ANY(assigned_roles))
    );
END;
$$;

REVOKE ALL ON FUNCTION public.is_admin_for_storage() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin_for_storage() TO authenticated;

-- 2. Update bucket settings (3MB limit, webp allowed)
UPDATE storage.buckets
SET file_size_limit = 3145728, -- 3MB exact limit
    allowed_mime_types = ARRAY['image/webp', 'image/jpeg', 'image/png']
WHERE id = 'menu-items';

-- 3. Robust Storage RLS Policies
DO $$
BEGIN
    DROP POLICY IF EXISTS "Admin Upload Menu Items" ON storage.objects;
    DROP POLICY IF EXISTS "Admin Update Menu Items" ON storage.objects;
    DROP POLICY IF EXISTS "Admin Delete Menu Items" ON storage.objects;
END $$;

CREATE POLICY "Admin Upload Menu Items"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'menu-items'
    AND public.is_admin_for_storage()
);

CREATE POLICY "Admin Update Menu Items"
ON storage.objects FOR UPDATE
TO authenticated
USING (
    bucket_id = 'menu-items'
    AND public.is_admin_for_storage()
)
WITH CHECK (
    bucket_id = 'menu-items'
    AND public.is_admin_for_storage()
);

CREATE POLICY "Admin Delete Menu Items"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'menu-items'
    AND public.is_admin_for_storage()
);
