-- Get complete jsonb of any auth user
CREATE OR REPLACE FUNCTION public.debug_get_full_auth_user(p_email TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
    v_user RECORD;
    v_identity RECORD;
BEGIN
    SELECT * INTO v_user FROM auth.users WHERE email = lower(trim(p_email));
    SELECT * INTO v_identity FROM auth.identities WHERE user_id = v_user.id LIMIT 1;

    RETURN jsonb_build_object(
        'user', to_jsonb(v_user),
        'identity', to_jsonb(v_identity)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.debug_get_full_auth_user(TEXT) TO anon, authenticated;
