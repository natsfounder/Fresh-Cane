-- Migration: 20261010150000_software_subscription_freeze_control.sql
-- Description: 
--   1. Add is_software_frozen flag to public.store_settings (default: false).
--   2. Add is_master_superadmin flag to public.user_profiles (default: false).
--   3. Create or update master SuperAdmin account (superadmin@freshcane.com / Superadmin@123).
--   4. Implement RPCs set_software_frozen and get_software_freeze_status.

-- 1. Add is_software_frozen column to store_settings
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'store_settings' 
          AND column_name = 'is_software_frozen'
    ) THEN
        ALTER TABLE public.store_settings 
        ADD COLUMN is_software_frozen BOOLEAN NOT NULL DEFAULT false;
    END IF;
END $$;

-- 2. Add is_master_superadmin column to user_profiles
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'user_profiles' 
          AND column_name = 'is_master_superadmin'
    ) THEN
        ALTER TABLE public.user_profiles 
        ADD COLUMN is_master_superadmin BOOLEAN NOT NULL DEFAULT false;
    END IF;
END $$;

-- 3. Idempotently create or update the master SuperAdmin account
DO $$
DECLARE
    v_super_id UUID := gen_random_uuid();
    v_existing_super_id UUID;
    v_encrypted_pw TEXT;
BEGIN
    -- Ensure pgcrypto extension is available
    CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
    v_encrypted_pw := extensions.crypt('Superadmin@123', extensions.gen_salt('bf', 10));

    SELECT id INTO v_existing_super_id FROM auth.users WHERE email = 'superadmin@freshcane.com';

    IF v_existing_super_id IS NOT NULL THEN
        UPDATE auth.users
        SET encrypted_password = v_encrypted_pw,
            email_confirmed_at = COALESCE(email_confirmed_at, now()),
            raw_app_meta_data = '{"provider":"email","providers":["email"]}'::jsonb,
            raw_user_meta_data = '{"full_name":"Super Administrator"}'::jsonb,
            updated_at = now()
        WHERE id = v_existing_super_id;

        INSERT INTO auth.identities (
            id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
        ) VALUES (
            gen_random_uuid(),
            v_existing_super_id::text,
            v_existing_super_id,
            jsonb_build_object('sub', v_existing_super_id::text, 'email', 'superadmin@freshcane.com'),
            'email',
            now(),
            now(),
            now()
        ) ON CONFLICT (provider_id, provider) DO UPDATE
        SET identity_data = jsonb_build_object('sub', v_existing_super_id::text, 'email', 'superadmin@freshcane.com'),
            updated_at = now();

        INSERT INTO public.user_profiles (
            id, full_name, role, is_active, is_master_superadmin, created_at, updated_at
        ) VALUES (
            v_existing_super_id, 'Super Administrator', 'super_admin', true, true, now(), now()
        ) ON CONFLICT (id) DO UPDATE
        SET full_name = 'Super Administrator',
            role = 'super_admin',
            is_active = true,
            is_master_superadmin = true,
            updated_at = now();
    ELSE
        INSERT INTO auth.users (
            instance_id,
            id,
            aud,
            role,
            email,
            encrypted_password,
            email_confirmed_at,
            confirmation_token,
            recovery_token,
            email_change,
            email_change_token_new,
            email_change_token_current,
            phone_change,
            phone_change_token,
            reauthentication_token,
            email_change_confirm_status,
            raw_app_meta_data,
            raw_user_meta_data,
            is_sso_user,
            is_anonymous,
            created_at,
            updated_at
        ) VALUES (
            '00000000-0000-0000-0000-000000000000',
            v_super_id,
            'authenticated',
            'authenticated',
            'superadmin@freshcane.com',
            v_encrypted_pw,
            now(),
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            0,
            '{"provider":"email","providers":["email"]}'::jsonb,
            '{"full_name":"Super Administrator"}'::jsonb,
            false,
            false,
            now(),
            now()
        );

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
            v_super_id::text,
            v_super_id,
            jsonb_build_object('sub', v_super_id::text, 'email', 'superadmin@freshcane.com'),
            'email',
            now(),
            now(),
            now()
        );

        INSERT INTO public.user_profiles (
            id,
            full_name,
            role,
            is_active,
            is_master_superadmin,
            created_at,
            updated_at
        ) VALUES (
            v_super_id,
            'Super Administrator',
            'super_admin',
            true,
            true,
            now(),
            now()
        );
    END IF;
END $$;

-- 4. RPC to get software freeze status (callable by public & authenticated)
CREATE OR REPLACE FUNCTION public.get_software_freeze_status()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
    SELECT COALESCE(is_software_frozen, false)
    FROM public.store_settings
    LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_software_freeze_status() TO anon, authenticated;

-- 5. RPC to set software freeze status
CREATE OR REPLACE FUNCTION public.set_software_frozen(p_frozen BOOLEAN)
RETURNS BOOLEAN
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_updated BOOLEAN;
BEGIN
    UPDATE public.store_settings
    SET is_software_frozen = p_frozen,
        updated_at = now()
    WHERE id = '00000000-0000-0000-0000-000000000001'::uuid
    RETURNING is_software_frozen INTO v_updated;

    -- If no row updated, update any row
    IF v_updated IS NULL THEN
        UPDATE public.store_settings
        SET is_software_frozen = p_frozen,
            updated_at = now()
        RETURNING is_software_frozen INTO v_updated;
    END IF;

    RETURN COALESCE(v_updated, p_frozen);
END $$;

GRANT EXECUTE ON FUNCTION public.set_software_frozen(BOOLEAN) TO anon, authenticated;
