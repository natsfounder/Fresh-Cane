-- =============================================================================
-- Migration: 20261002100000_add_assigned_roles_to_user_profiles.sql
-- Description:
--   1. Add `assigned_roles TEXT[]` column to `public.user_profiles` to support
--      multiple access privileges for a single staff account.
--   2. Backfill existing profiles so assigned_roles contains their current role.
--   3. Update `admin_create_staff_user` RPC to accept `p_roles TEXT[]` for multi-access.
-- =============================================================================

-- 1. Add assigned_roles array column to public.user_profiles
ALTER TABLE public.user_profiles
    ADD COLUMN IF NOT EXISTS assigned_roles TEXT[] NOT NULL DEFAULT '{}';

-- 2. Backfill existing profiles
UPDATE public.user_profiles
SET assigned_roles = ARRAY[role]
WHERE assigned_roles = '{}' OR assigned_roles IS NULL;

-- 3. Replace admin_create_staff_user to support multiple roles
DROP FUNCTION IF EXISTS public.admin_create_staff_user(TEXT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.admin_create_staff_user(TEXT, TEXT, TEXT, TEXT[], TEXT);

CREATE OR REPLACE FUNCTION public.admin_create_staff_user(
    p_email TEXT,
    p_password TEXT,
    p_full_name TEXT,
    p_roles TEXT[],
    p_phone TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, auth, extensions, pg_temp
AS $$
DECLARE
    v_admin_id UUID := auth.uid();
    v_admin_role VARCHAR(20);
    v_new_user_id UUID;
    v_clean_email TEXT := lower(trim(p_email));
    v_clean_name TEXT := trim(p_full_name);
    v_clean_phone TEXT := NULLIF(trim(p_phone), '');
    v_primary_role VARCHAR(20);
    v_encrypted_pw TEXT;
    v_r TEXT;
    v_valid_roles TEXT[] := ARRAY['server', 'cashier', 'super_admin'];
    v_clean_roles TEXT[] := '{}';
BEGIN
    -- 1. Authorization: Only super_admin can create users
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: authentication required';
    END IF;

    SELECT role INTO v_admin_role
    FROM public.user_profiles
    WHERE id = v_admin_id AND is_active = true;

    IF v_admin_role IS NULL OR v_admin_role <> 'super_admin' THEN
        RAISE EXCEPTION 'Unauthorized: only Super Admin can create staff accounts';
    END IF;

    -- 2. Validation
    IF v_clean_email IS NULL OR v_clean_email = '' OR v_clean_email NOT LIKE '%_@__%.__%' THEN
        RAISE EXCEPTION 'Invalid email address';
    END IF;

    IF p_password IS NULL OR length(p_password) < 6 THEN
        RAISE EXCEPTION 'Password must be at least 6 characters long';
    END IF;

    IF v_clean_name IS NULL OR v_clean_name = '' THEN
        RAISE EXCEPTION 'Full name is required';
    END IF;

    IF p_roles IS NULL OR array_length(p_roles, 1) IS NULL OR array_length(p_roles, 1) = 0 THEN
        RAISE EXCEPTION 'At least one role must be assigned';
    END IF;

    -- Validate and clean roles
    FOREACH v_r IN ARRAY p_roles LOOP
        v_r := lower(trim(v_r));
        IF v_r = ANY(v_valid_roles) THEN
            IF NOT (v_r = ANY(v_clean_roles)) THEN
                v_clean_roles := array_append(v_clean_roles, v_r);
            END IF;
        ELSE
            RAISE EXCEPTION 'Invalid role "%". Allowed roles: server, cashier, super_admin', v_r;
        END IF;
    END LOOP;

    IF array_length(v_clean_roles, 1) = 0 THEN
        RAISE EXCEPTION 'No valid roles specified';
    END IF;

    -- Primary role is the first assigned role
    v_primary_role := v_clean_roles[1];

    -- Check if email already exists
    IF EXISTS (SELECT 1 FROM auth.users WHERE email = v_clean_email) THEN
        RAISE EXCEPTION 'A user with email "%" already exists', v_clean_email;
    END IF;

    -- 3. Create user in auth.users
    v_new_user_id := gen_random_uuid();
    v_encrypted_pw := crypt(p_password, gen_salt('bf', 10));

    INSERT INTO auth.users (
        instance_id,
        id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        raw_app_meta_data,
        raw_user_meta_data,
        is_sso_user,
        is_anonymous,
        created_at,
        updated_at
    ) VALUES (
        '00000000-0000-0000-0000-000000000000',
        v_new_user_id,
        'authenticated',
        'authenticated',
        v_clean_email,
        v_encrypted_pw,
        now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object(
            'full_name', v_clean_name,
            'roles', v_clean_roles
        ),
        false,
        false,
        now(),
        now()
    );

    -- 4. Create identity in auth.identities
    INSERT INTO auth.identities (
        id,
        provider_id,
        user_id,
        identity_data,
        provider,
        last_sign_in_at,
        created_at,
        updated_at
    ) VALUES (
        gen_random_uuid(),
        v_new_user_id::text,
        v_new_user_id,
        jsonb_build_object('sub', v_new_user_id::text, 'email', v_clean_email),
        'email',
        now(),
        now(),
        now()
    );

    -- 5. Create profile in public.user_profiles with assigned_roles
    INSERT INTO public.user_profiles (
        id,
        full_name,
        role,
        assigned_roles,
        phone,
        is_active,
        created_at,
        updated_at
    ) VALUES (
        v_new_user_id,
        v_clean_name,
        v_primary_role,
        v_clean_roles,
        v_clean_phone,
        true,
        now(),
        now()
    )
    ON CONFLICT (id) DO UPDATE SET
        full_name = EXCLUDED.full_name,
        role = EXCLUDED.role,
        assigned_roles = EXCLUDED.assigned_roles,
        phone = EXCLUDED.phone,
        is_active = true,
        updated_at = now();

    -- 6. Write audit log
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (
        v_admin_id,
        'STAFF_USER_CREATED',
        'user_profile',
        v_new_user_id::text,
        jsonb_build_object(
            'email', v_clean_email,
            'full_name', v_clean_name,
            'primary_role', v_primary_role,
            'assigned_roles', v_clean_roles,
            'created_by', v_admin_id
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'user_id', v_new_user_id,
        'email', v_clean_email,
        'full_name', v_clean_name,
        'primary_role', v_primary_role,
        'assigned_roles', v_clean_roles
    );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_staff_user(TEXT, TEXT, TEXT, TEXT[], TEXT) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_staff_user(TEXT, TEXT, TEXT, TEXT[], TEXT) TO authenticated;
