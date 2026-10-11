-- =============================================================================
-- Migration: 20260919131000_update_add_customer_rpc.sql
-- Description: Update add_customer_to_table_session to support table sessions
--              in 'billing' status (reactivating session to 'active' when a new customer joins)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.add_customer_to_table_session(
    p_session_id UUID,
    p_name TEXT DEFAULT NULL,
    p_phone TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_session RECORD;
    v_count INTEGER;
    v_label VARCHAR(100);
    v_canonical_customer_id UUID := NULL;
    v_normalized_phone VARCHAR(10) := NULL;
    v_new_id UUID;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: authentication required';
    END IF;

    SELECT role INTO v_role
    FROM public.user_profiles
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR v_role NOT IN ('server', 'cashier', 'super_admin') THEN
        RAISE EXCEPTION 'Unauthorized: caller does not possess staff privileges';
    END IF;

    -- Verify session is active or billing
    SELECT * INTO v_session
    FROM public.table_sessions
    WHERE id = p_session_id AND status IN ('active', 'billing');

    IF v_session IS NULL THEN
        RAISE EXCEPTION 'Table session not found or not active';
    END IF;

    -- If session was in billing, reactivate it since an active customer is joining
    IF v_session.status = 'billing' THEN
        UPDATE public.table_sessions
        SET status = 'active', updated_at = now()
        WHERE id = p_session_id;
    END IF;

    -- Phone handling (optional)
    IF p_phone IS NOT NULL AND trim(p_phone) <> '' THEN
        v_normalized_phone := public.normalize_indian_phone(p_phone);

        INSERT INTO public.customers (phone, name)
        VALUES (v_normalized_phone, NULLIF(trim(p_name), ''))
        ON CONFLICT (phone) DO UPDATE SET
            name = COALESCE(NULLIF(trim(EXCLUDED.name), ''), public.customers.name),
            updated_at = now()
        RETURNING id INTO v_canonical_customer_id;
    END IF;

    -- Determine label
    IF p_name IS NOT NULL AND trim(p_name) <> '' THEN
        v_label := trim(p_name);
    ELSE
        SELECT count(*) INTO v_count
        FROM public.table_session_customers
        WHERE session_id = p_session_id;

        v_label := 'Customer ' || (v_count + 1);
    END IF;

    INSERT INTO public.table_session_customers (
        session_id,
        customer_id,
        customer_label,
        customer_name,
        customer_phone,
        status
    )
    VALUES (
        p_session_id,
        v_canonical_customer_id,
        v_label,
        NULLIF(trim(p_name), ''),
        v_normalized_phone,
        'active'
    )
    RETURNING id INTO v_new_id;

    RETURN jsonb_build_object(
        'id', v_new_id,
        'session_id', p_session_id,
        'customer_label', v_label,
        'customer_name', NULLIF(trim(p_name), ''),
        'customer_phone', v_normalized_phone,
        'status', 'active',
        'finished_at', NULL,
        'finished_by', NULL
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.add_customer_to_table_session(UUID, TEXT, TEXT) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_customer_to_table_session(UUID, TEXT, TEXT) TO authenticated;
