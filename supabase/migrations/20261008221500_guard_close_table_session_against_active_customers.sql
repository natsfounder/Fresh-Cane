-- =============================================================================
-- Migration: 20261008221500_guard_close_table_session_against_active_customers.sql
-- Description:
--   Guard close_table_session RPC against auto-closing tables where active
--   dining customers still have open or served orders.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.close_table_session(
    p_table_id UUID,
    p_reason TEXT DEFAULT 'Session closed'
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
    v_assigned_roles TEXT[];
    v_session RECORD;
    v_unpaid_bill RECORD;
    v_active_customers_count INTEGER := 0;
BEGIN
    -- 1. Authorization: cashier or super_admin (including assigned_roles)
    SELECT role, assigned_roles INTO v_role, v_assigned_roles
    FROM public.user_profiles 
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR (
        v_role NOT IN ('cashier', 'super_admin') 
        AND NOT ('cashier' = ANY(v_assigned_roles) OR 'super_admin' = ANY(v_assigned_roles))
    ) THEN
        RAISE EXCEPTION 'Unauthorized: only cashier or super_admin can close table sessions';
    END IF;

    SELECT * INTO v_session FROM public.table_sessions
    WHERE table_id = p_table_id AND status IN ('active', 'billing')
    FOR UPDATE;

    IF v_session IS NULL THEN
        UPDATE public.restaurant_tables SET status = 'available', updated_at = now() WHERE id = p_table_id;
        RETURN jsonb_build_object('success', true);
    END IF;

    -- 2. Guard: verify no unpaid bills exist for this table session
    SELECT b.bill_number, b.final_amount INTO v_unpaid_bill
    FROM public.bills b
    JOIN public.orders o ON o.id = b.order_id
    WHERE o.session_id = v_session.id AND b.status = 'unpaid'
    LIMIT 1;

    IF v_unpaid_bill.bill_number IS NOT NULL THEN
        RAISE EXCEPTION 'Cannot close table: Bill "%" (₹%) is unpaid. Please settle payment first.',
            v_unpaid_bill.bill_number, v_unpaid_bill.final_amount;
    END IF;

    -- 2.1 Guard: verify no active dining customers with orders exist at this table
    SELECT COUNT(*) INTO v_active_customers_count
    FROM public.table_session_customers sc
    WHERE sc.session_id = v_session.id
      AND sc.status = 'active'
      AND EXISTS (
          SELECT 1 FROM public.orders o
          WHERE o.session_customer_id = sc.id
            AND o.status IN ('open', 'served')
      );

    IF v_active_customers_count > 0 AND p_reason NOT LIKE '%force%' THEN
        RAISE EXCEPTION 'Cannot close table: % active customer(s) are still dining with unbilled orders.',
            v_active_customers_count;
    END IF;

    -- 3. Auto-complete all orders whose bill is settled / paid
    UPDATE public.orders o
    SET status = 'completed', updated_at = now()
    WHERE o.session_id = v_session.id
      AND o.status NOT IN ('completed', 'cancelled')
      AND EXISTS (
          SELECT 1 FROM public.bills b
          WHERE b.order_id = o.id AND b.status = 'paid'
      );

    -- 4. Cancel any remaining unbilled open/served orders (e.g. abandoned items on full closure)
    UPDATE public.orders o
    SET status = 'cancelled', 
        cancellation_reason = COALESCE(p_reason, 'Session closed without bill'),
        updated_at = now()
    WHERE o.session_id = v_session.id
      AND o.status NOT IN ('completed', 'cancelled')
      AND NOT EXISTS (
          SELECT 1 FROM public.bills b WHERE b.order_id = o.id
      );

    -- 5. Mark table session completed
    UPDATE public.table_sessions
    SET status = 'completed', closed_at = now(), closed_by = v_actor, updated_at = now()
    WHERE id = v_session.id;

    -- 6. Release table to available
    UPDATE public.restaurant_tables
    SET status = 'available', updated_at = now()
    WHERE id = p_table_id;

    -- 7. Mark session customers closed (satisfies chk_table_session_customers_status)
    UPDATE public.table_session_customers
    SET status = 'closed', updated_at = now()
    WHERE session_id = v_session.id AND status NOT IN ('closed', 'cancelled');

    RETURN jsonb_build_object(
        'success', true,
        'table_id', p_table_id,
        'session_id', v_session.id,
        'reason', p_reason
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.close_table_session(UUID, TEXT) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.close_table_session(UUID, TEXT) TO authenticated;
