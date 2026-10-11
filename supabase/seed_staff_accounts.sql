-- Seed script for Fresh Cane staff and administrator accounts
-- Accounts created:
-- 1. Server:  server@freshcane.dev  (role: server, password: server@123)
-- 2. Admin:   admin@freshcane.dev   (role: super_admin, password: Admin@123)
-- 3. Cashier: cashier@freshcane.dev (role: cashier, password: cashier@123)

DO $$
DECLARE
    v_server_id UUID := gen_random_uuid();
    v_admin_id UUID := gen_random_uuid();
    v_cashier_id UUID := gen_random_uuid();
    v_existing_server_id UUID;
    v_existing_admin_id UUID;
    v_existing_cashier_id UUID;
BEGIN
    -- -------------------------------------------------------------------------
    -- 1. SERVER ACCOUNT (server@freshcane.dev)
    -- -------------------------------------------------------------------------
    SELECT id INTO v_existing_server_id FROM auth.users WHERE email = 'server@freshcane.dev';

    IF v_existing_server_id IS NOT NULL THEN
        UPDATE auth.users
        SET encrypted_password = crypt('server@123', gen_salt('bf', 10)),
            email_confirmed_at = COALESCE(email_confirmed_at, now()),
            raw_app_meta_data = '{"provider":"email","providers":["email"]}'::jsonb,
            raw_user_meta_data = '{"full_name":"Fresh Cane Server"}'::jsonb,
            updated_at = now()
        WHERE id = v_existing_server_id;

        INSERT INTO auth.identities (
            id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
        ) VALUES (
            gen_random_uuid(),
            v_existing_server_id::text,
            v_existing_server_id,
            jsonb_build_object('sub', v_existing_server_id::text, 'email', 'server@freshcane.dev'),
            'email',
            now(),
            now(),
            now()
        ) ON CONFLICT (provider_id, provider) DO UPDATE
        SET identity_data = jsonb_build_object('sub', v_existing_server_id::text, 'email', 'server@freshcane.dev'),
            updated_at = now();

        INSERT INTO public.user_profiles (
            id, full_name, role, is_active, created_at, updated_at
        ) VALUES (
            v_existing_server_id, 'Fresh Cane Server', 'server', true, now(), now()
        ) ON CONFLICT (id) DO UPDATE
        SET full_name = 'Fresh Cane Server',
            role = 'server',
            is_active = true,
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
            raw_app_meta_data,
            raw_user_meta_data,
            is_sso_user,
            is_anonymous,
            created_at,
            updated_at
        ) VALUES (
            '00000000-0000-0000-0000-000000000000',
            v_server_id,
            'authenticated',
            'authenticated',
            'server@freshcane.dev',
            crypt('server@123', gen_salt('bf', 10)),
            now(),
            '{"provider":"email","providers":["email"]}'::jsonb,
            '{"full_name":"Fresh Cane Server"}'::jsonb,
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
            v_server_id::text,
            v_server_id,
            jsonb_build_object('sub', v_server_id::text, 'email', 'server@freshcane.dev'),
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
            created_at,
            updated_at
        ) VALUES (
            v_server_id,
            'Fresh Cane Server',
            'server',
            true,
            now(),
            now()
        );
    END IF;

    -- -------------------------------------------------------------------------
    -- 2. ADMIN ACCOUNT (admin@freshcane.dev)
    -- -------------------------------------------------------------------------
    SELECT id INTO v_existing_admin_id FROM auth.users WHERE email = 'admin@freshcane.dev';

    IF v_existing_admin_id IS NOT NULL THEN
        UPDATE auth.users
        SET encrypted_password = crypt('Admin@123', gen_salt('bf', 10)),
            email_confirmed_at = COALESCE(email_confirmed_at, now()),
            raw_app_meta_data = '{"provider":"email","providers":["email"]}'::jsonb,
            raw_user_meta_data = '{"full_name":"Fresh Cane Admin"}'::jsonb,
            updated_at = now()
        WHERE id = v_existing_admin_id;

        INSERT INTO auth.identities (
            id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
        ) VALUES (
            gen_random_uuid(),
            v_existing_admin_id::text,
            v_existing_admin_id,
            jsonb_build_object('sub', v_existing_admin_id::text, 'email', 'admin@freshcane.dev'),
            'email',
            now(),
            now(),
            now()
        ) ON CONFLICT (provider_id, provider) DO UPDATE
        SET identity_data = jsonb_build_object('sub', v_existing_admin_id::text, 'email', 'admin@freshcane.dev'),
            updated_at = now();

        INSERT INTO public.user_profiles (
            id, full_name, role, is_active, created_at, updated_at
        ) VALUES (
            v_existing_admin_id, 'Fresh Cane Admin', 'super_admin', true, now(), now()
        ) ON CONFLICT (id) DO UPDATE
        SET full_name = 'Fresh Cane Admin',
            role = 'super_admin',
            is_active = true,
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
            raw_app_meta_data,
            raw_user_meta_data,
            is_sso_user,
            is_anonymous,
            created_at,
            updated_at
        ) VALUES (
            '00000000-0000-0000-0000-000000000000',
            v_admin_id,
            'authenticated',
            'authenticated',
            'admin@freshcane.dev',
            crypt('Admin@123', gen_salt('bf', 10)),
            now(),
            '{"provider":"email","providers":["email"]}'::jsonb,
            '{"full_name":"Fresh Cane Admin"}'::jsonb,
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
            v_admin_id::text,
            v_admin_id,
            jsonb_build_object('sub', v_admin_id::text, 'email', 'admin@freshcane.dev'),
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
            created_at,
            updated_at
        ) VALUES (
            v_admin_id,
            'Fresh Cane Admin',
            'super_admin',
            true,
            now(),
            now()
        );
    END IF;

    -- -------------------------------------------------------------------------
    -- 3. CASHIER ACCOUNT (cashier@freshcane.dev)
    -- -------------------------------------------------------------------------
    SELECT id INTO v_existing_cashier_id FROM auth.users WHERE email = 'cashier@freshcane.dev';

    IF v_existing_cashier_id IS NOT NULL THEN
        UPDATE auth.users
        SET encrypted_password = crypt('cashier@123', gen_salt('bf', 10)),
            email_confirmed_at = COALESCE(email_confirmed_at, now()),
            raw_app_meta_data = '{"provider":"email","providers":["email"]}'::jsonb,
            raw_user_meta_data = '{"full_name":"Fresh Cane Cashier"}'::jsonb,
            updated_at = now()
        WHERE id = v_existing_cashier_id;

        INSERT INTO auth.identities (
            id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
        ) VALUES (
            gen_random_uuid(),
            v_existing_cashier_id::text,
            v_existing_cashier_id,
            jsonb_build_object('sub', v_existing_cashier_id::text, 'email', 'cashier@freshcane.dev'),
            'email',
            now(),
            now(),
            now()
        ) ON CONFLICT (provider_id, provider) DO UPDATE
        SET identity_data = jsonb_build_object('sub', v_existing_cashier_id::text, 'email', 'cashier@freshcane.dev'),
            updated_at = now();

        INSERT INTO public.user_profiles (
            id, full_name, role, is_active, created_at, updated_at
        ) VALUES (
            v_existing_cashier_id, 'Fresh Cane Cashier', 'cashier', true, now(), now()
        ) ON CONFLICT (id) DO UPDATE
        SET full_name = 'Fresh Cane Cashier',
            role = 'cashier',
            is_active = true,
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
            raw_app_meta_data,
            raw_user_meta_data,
            is_sso_user,
            is_anonymous,
            created_at,
            updated_at
        ) VALUES (
            '00000000-0000-0000-0000-000000000000',
            v_cashier_id,
            'authenticated',
            'authenticated',
            'cashier@freshcane.dev',
            crypt('cashier@123', gen_salt('bf', 10)),
            now(),
            '{"provider":"email","providers":["email"]}'::jsonb,
            '{"full_name":"Fresh Cane Cashier"}'::jsonb,
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
            v_cashier_id::text,
            v_cashier_id,
            jsonb_build_object('sub', v_cashier_id::text, 'email', 'cashier@freshcane.dev'),
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
            created_at,
            updated_at
        ) VALUES (
            v_cashier_id,
            'Fresh Cane Cashier',
            'cashier',
            true,
            now(),
            now()
        );
    END IF;
END $$;
