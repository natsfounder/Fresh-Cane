-- Helper to list all users in auth.users
CREATE OR REPLACE FUNCTION public.debug_list_auth_users()
RETURNS TABLE (
    id UUID,
    email VARCHAR(255),
    confirmed_at TIMESTAMPTZ,
    email_confirmed_at TIMESTAMPTZ,
    confirmation_token VARCHAR(255),
    recovery_token VARCHAR(255),
    email_change VARCHAR(255),
    email_change_token_new VARCHAR(255),
    raw_app_meta_data JSONB,
    raw_user_meta_data JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.id,
        u.email,
        u.confirmed_at,
        u.email_confirmed_at,
        u.confirmation_token,
        u.recovery_token,
        u.email_change,
        u.email_change_token_new,
        u.raw_app_meta_data,
        u.raw_user_meta_data
    FROM auth.users u;
END;
$$;

GRANT EXECUTE ON FUNCTION public.debug_list_auth_users() TO anon, authenticated;
