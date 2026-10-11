-- Diagnostic function to inspect auth.users and auth.identities
CREATE OR REPLACE FUNCTION public.debug_inspect_auth_user(p_email TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
    v_user RECORD;
    v_identity RECORD;
    v_profile RECORD;
BEGIN
    SELECT * INTO v_user FROM auth.users WHERE email = lower(trim(p_email));
    SELECT * INTO v_identity FROM auth.identities WHERE user_id = v_user.id;
    SELECT * INTO v_profile FROM public.user_profiles WHERE id = v_user.id;

    RETURN jsonb_build_object(
        'user_found', v_user IS NOT NULL,
        'user_id', v_user.id,
        'user_email', v_user.email,
        'encrypted_password_len', length(v_user.encrypted_password),
        'email_confirmed_at', v_user.email_confirmed_at,
        'confirmation_token', v_user.confirmation_token,
        'recovery_token', v_user.recovery_token,
        'email_change_token_new', v_user.email_change_token_new,
        'email_change', v_user.email_change,
        'raw_app_meta_data', v_user.raw_app_meta_data,
        'raw_user_meta_data', v_user.raw_user_meta_data,
        'is_super_admin', v_user.is_super_admin,
        'aud', v_user.aud,
        'role', v_user.role,
        'identity_found', v_identity IS NOT NULL,
        'identity_id', v_identity.id,
        'identity_provider_id', v_identity.provider_id,
        'identity_provider', v_identity.provider,
        'identity_data', v_identity.identity_data,
        'profile_found', v_profile IS NOT NULL,
        'profile_role', v_profile.role,
        'profile_assigned_roles', v_profile.assigned_roles
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.debug_inspect_auth_user(TEXT) TO anon, authenticated;
