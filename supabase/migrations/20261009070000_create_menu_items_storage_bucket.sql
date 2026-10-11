-- Migration: 20261009070000_create_menu_items_storage_bucket.sql
-- Description: Create public storage bucket 'menu-items' for product photos,
-- and establish RLS policies allowing authenticated staff to upload/update/delete
-- and public access to read/download images.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'menu-items',
    'menu-items',
    true,
    5242880, -- 5MB limit
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE SET
    public = true,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif'];

-- Storage RLS Policies for menu-items bucket
-- Drop existing policies if they already exist to be idempotent
DO $$
BEGIN
    DROP POLICY IF EXISTS "Public Read Access for Menu Items" ON storage.objects;
    DROP POLICY IF EXISTS "Staff Upload Menu Items" ON storage.objects;
    DROP POLICY IF EXISTS "Staff Update Menu Items" ON storage.objects;
    DROP POLICY IF EXISTS "Staff Delete Menu Items" ON storage.objects;
END $$;

-- 1. Public read access
CREATE POLICY "Public Read Access for Menu Items"
ON storage.objects FOR SELECT
USING (bucket_id = 'menu-items');

-- 2. Authenticated staff insert/upload access
CREATE POLICY "Staff Upload Menu Items"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'menu-items'
    AND EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE id = auth.uid()
          AND is_active = true
          AND (role IN ('super_admin', 'cashier') OR 'super_admin' = ANY(assigned_roles) OR 'cashier' = ANY(assigned_roles))
    )
);

-- 3. Authenticated staff update access
CREATE POLICY "Staff Update Menu Items"
ON storage.objects FOR UPDATE
TO authenticated
USING (
    bucket_id = 'menu-items'
    AND EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE id = auth.uid()
          AND is_active = true
          AND (role IN ('super_admin', 'cashier') OR 'super_admin' = ANY(assigned_roles) OR 'cashier' = ANY(assigned_roles))
    )
);

-- 4. Authenticated staff delete access
CREATE POLICY "Staff Delete Menu Items"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'menu-items'
    AND EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE id = auth.uid()
          AND is_active = true
          AND (role IN ('super_admin', 'cashier') OR 'super_admin' = ANY(assigned_roles) OR 'cashier' = ANY(assigned_roles))
    )
);
