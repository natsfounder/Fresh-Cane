-- Migration: 20261010160000_admin_reset_staff_password.sql
-- Description: Implement secure admin_reset_staff_password RPC for store administrator

CREATE OR REPLACE FUNCTION public.admin_reset_staff_password(
    p_staff_user_id UUID,
    p_new_password TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, auth, extensions, pg_temp
AS $$
DECLARE
    v_admin_id UUID := auth.uid();
    v_target_profile RECORD;
    v_encrypted_pw TEXT;
BEGIN
    -- 1. Ensure caller is authenticated
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    -- 2. Validate password length
    IF length(trim(p_new_password)) < 6 THEN
        RAISE EXCEPTION 'Password must be at least 6 characters.';
    END IF;

    -- 3. Verify target staff profile
    SELECT * INTO v_target_profile
    FROM public.user_profiles
    WHERE id = p_staff_user_id;

    IF v_target_profile IS NULL THEN
        RAISE EXCEPTION 'Staff member profile not found.';
    END IF;

    -- 4. Protection: Cannot reset master superAdmin account
    IF COALESCE(v_target_profile.is_master_superadmin, false) = true THEN
        RAISE EXCEPTION 'Unauthorized: SuperAdmin credentials cannot be reset from store admin console.';
    END IF;

    -- 5. Encrypt new password using extensions.crypt
    v_encrypted_pw := extensions.crypt(p_new_password, extensions.gen_salt('bf', 10));

    -- 6. Update auth.users with empty tokens for GoTrue compliance
    UPDATE auth.users
    SET encrypted_password = v_encrypted_pw,
        confirmation_token = COALESCE(confirmation_token, ''),
        recovery_token = COALESCE(recovery_token, ''),
        email_change = COALESCE(email_change, ''),
        email_change_token_new = COALESCE(email_change_token_new, ''),
        email_change_token_current = COALESCE(email_change_token_current, ''),
        phone_change = COALESCE(phone_change, ''),
        phone_change_token = COALESCE(phone_change_token, ''),
        reauthentication_token = COALESCE(reauthentication_token, ''),
        email_change_confirm_status = COALESCE(email_change_confirm_status, 0),
        email_confirmed_at = COALESCE(email_confirmed_at, now()),
        updated_at = now()
    WHERE id = p_staff_user_id;

    -- 7. Audit log
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (
        v_admin_id,
        'STAFF_PASSWORD_RESET',
        'user_profiles',
        p_staff_user_id,
        jsonb_build_object(
            'target_name', v_target_profile.full_name,
            'target_role', v_target_profile.role,
            'reset_by', v_admin_id,
            'reset_at', now()
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Password updated successfully.',
        'staff_id', p_staff_user_id,
        'staff_name', v_target_profile.full_name
    );
END $$;

GRANT EXECUTE ON FUNCTION public.admin_reset_staff_password(UUID, TEXT) TO authenticated;
