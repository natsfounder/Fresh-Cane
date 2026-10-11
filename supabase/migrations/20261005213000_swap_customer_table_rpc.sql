-- =============================================================================
-- Migration: 20261005213000_swap_customer_table_rpc.sql
-- Description: Implement swap_customer_table RPC to transfer a customer
--              and all their active orders from their current table to a target table.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.swap_customer_table(
    p_customer_id UUID,
    p_target_table_id UUID
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
    v_customer RECORD;
    v_source_session RECORD;
    v_source_table_id UUID;
    v_source_table_num VARCHAR(20);
    v_target_table RECORD;
    v_target_session RECORD;
    v_target_session_id UUID;
    v_remaining_source_customers INTEGER;
    v_remaining_source_orders INTEGER;
    v_active_source_customers INTEGER;
    v_max_cust_num INTEGER := 0;
    v_new_customer_label VARCHAR(100);
    v_target_active_count INTEGER;
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

    -- 1. Lock and validate the customer record
    SELECT * INTO v_customer
    FROM public.table_session_customers
    WHERE id = p_customer_id
    FOR UPDATE;

    IF v_customer IS NULL THEN
        RAISE EXCEPTION 'Customer not found';
    END IF;

    IF v_customer.status NOT IN ('active', 'finished') THEN
        RAISE EXCEPTION 'Cannot swap customer with status %', v_customer.status;
    END IF;

    -- 2. Lock and retrieve source session
    SELECT * INTO v_source_session
    FROM public.table_sessions
    WHERE id = v_customer.session_id
    FOR UPDATE;

    IF v_source_session IS NULL THEN
        RAISE EXCEPTION 'Source table session not found';
    END IF;

    v_source_table_id := v_source_session.table_id;

    IF v_source_table_id = p_target_table_id THEN
        RAISE EXCEPTION 'Target table is the same as current table';
    END IF;

    SELECT table_number INTO v_source_table_num
    FROM public.restaurant_tables
    WHERE id = v_source_table_id;

    -- 3. Lock and validate target table
    SELECT * INTO v_target_table
    FROM public.restaurant_tables
    WHERE id = p_target_table_id AND is_active = true
    FOR UPDATE;

    IF v_target_table IS NULL THEN
        RAISE EXCEPTION 'Target table not found or inactive';
    END IF;

    -- 4. Find or create target session
    SELECT * INTO v_target_session
    FROM public.table_sessions
    WHERE table_id = p_target_table_id AND status IN ('active', 'billing')
    LIMIT 1
    FOR UPDATE;

    IF v_target_session IS NULL THEN
        -- Create a new active session on target table
        INSERT INTO public.table_sessions (
            table_id,
            status,
            opened_at,
            opened_by,
            created_at,
            updated_at
        ) VALUES (
            p_target_table_id,
            CASE WHEN v_customer.status = 'finished' THEN 'billing' ELSE 'active' END,
            now(),
            v_actor,
            now(),
            now()
        )
        RETURNING * INTO v_target_session;

        v_target_session_id := v_target_session.id;

        -- Target table is now occupied
        UPDATE public.restaurant_tables
        SET status = 'occupied', updated_at = now()
        WHERE id = p_target_table_id;
    ELSE
        v_target_session_id := v_target_session.id;

        -- Ensure target table marked occupied
        UPDATE public.restaurant_tables
        SET status = 'occupied', updated_at = now()
        WHERE id = p_target_table_id;
    END IF;

    -- 5. Calculate new customer label if needed (avoid label conflict e.g. Customer 1 with existing Customer 1)
    IF v_customer.customer_name IS NULL OR TRIM(v_customer.customer_name) = '' THEN
        IF v_customer.customer_label ~ '^Customer [0-9]+$' THEN
            SELECT COALESCE(MAX(
                CASE 
                    WHEN customer_label ~ '^Customer [0-9]+$' 
                    THEN SUBSTRING(customer_label FROM '^Customer ([0-9]+)$')::INTEGER 
                    ELSE 0 
                END
            ), 0) INTO v_max_cust_num
            FROM public.table_session_customers
            WHERE session_id = v_target_session_id;

            v_new_customer_label := 'Customer ' || (v_max_cust_num + 1);
        ELSE
            v_new_customer_label := v_customer.customer_label;
        END IF;
    ELSE
        v_new_customer_label := v_customer.customer_label;
    END IF;

    -- 6. Move customer record to target session
    UPDATE public.table_session_customers
    SET session_id = v_target_session_id,
        customer_label = v_new_customer_label,
        updated_at = now()
    WHERE id = p_customer_id;

    -- 7. Move all orders for this customer to target session & table
    UPDATE public.orders
    SET session_id = v_target_session_id,
        table_id = p_target_table_id,
        updated_at = now()
    WHERE session_customer_id = p_customer_id;

    -- 8. Re-evaluate source session & table
    SELECT count(*) INTO v_remaining_source_customers
    FROM public.table_session_customers
    WHERE session_id = v_source_session.id
      AND id <> p_customer_id
      AND status IN ('active', 'finished');

    SELECT count(*) INTO v_remaining_source_orders
    FROM public.orders
    WHERE session_id = v_source_session.id
      AND status IN ('open', 'served');

    IF v_remaining_source_customers = 0 THEN
        -- If no active or finished customers remain at source table, close source session
        UPDATE public.table_sessions
        SET status = 'completed',
            closed_at = now(),
            closed_by = v_actor,
            updated_at = now()
        WHERE id = v_source_session.id;

        -- Set source table to available
        UPDATE public.restaurant_tables
        SET status = 'available',
            updated_at = now()
        WHERE id = v_source_table_id;
    ELSE
        -- Source table still has other customers
        SELECT count(*) INTO v_active_source_customers
        FROM public.table_session_customers
        WHERE session_id = v_source_session.id
          AND status = 'active';

        IF v_active_source_customers = 0 THEN
            -- All remaining customers are finished -> billing
            UPDATE public.table_sessions
            SET status = 'billing', updated_at = now()
            WHERE id = v_source_session.id;
        ELSE
            UPDATE public.table_sessions
            SET status = 'active', updated_at = now()
            WHERE id = v_source_session.id;
        END IF;

        -- Source table remains occupied
        UPDATE public.restaurant_tables
        SET status = 'occupied', updated_at = now()
        WHERE id = v_source_table_id;
    END IF;

    -- 9. Re-evaluate target session status
    SELECT count(*) INTO v_target_active_count
    FROM public.table_session_customers
    WHERE session_id = v_target_session_id
      AND status = 'active';

    IF v_target_active_count > 0 THEN
        UPDATE public.table_sessions
        SET status = 'active', updated_at = now()
        WHERE id = v_target_session_id;
    ELSE
        UPDATE public.table_sessions
        SET status = 'billing', updated_at = now()
        WHERE id = v_target_session_id;
    END IF;

    -- 10. Audit log entry
    INSERT INTO public.audit_logs (
        table_name,
        operation,
        record_id,
        user_id,
        severity,
        details
    ) VALUES (
        'table_session_customers',
        'CUSTOMER_TABLE_SWAPPED',
        p_customer_id,
        v_actor,
        'info',
        jsonb_build_object(
            'customer_id', p_customer_id,
            'customer_name', COALESCE(v_customer.customer_name, v_new_customer_label),
            'source_table_id', v_source_table_id,
            'source_table_number', v_source_table_num,
            'target_table_id', p_target_table_id,
            'target_table_number', v_target_table.table_number,
            'source_session_id', v_source_session.id,
            'target_session_id', v_target_session_id,
            'source_table_freed', (v_remaining_source_customers = 0)
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'customer_id', p_customer_id,
        'customer_label', v_new_customer_label,
        'source_table_id', v_source_table_id,
        'source_table_number', v_source_table_num,
        'target_table_id', p_target_table_id,
        'target_table_number', v_target_table.table_number,
        'source_session_id', v_source_session.id,
        'target_session_id', v_target_session_id,
        'source_table_freed', (v_remaining_source_customers = 0)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.swap_customer_table(UUID, UUID) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.swap_customer_table(UUID, UUID) TO authenticated;
