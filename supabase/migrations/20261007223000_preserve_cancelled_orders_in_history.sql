-- =============================================================================
-- Migration: 20261007223000_preserve_cancelled_orders_in_history.sql
-- Description:
--   Preserve cancelled orders and their line items when removing a customer
--   from an active dining session.
--   Instead of executing DELETE FROM orders / order_items, safely dissociate
--   session_customer_id to NULL so that:
--   1. Order records remain intact with status = 'cancelled'
--   2. Cancelled orders appear in Server's Today's Orders feed and audit history
--   3. Cancelled orders count is correctly recorded instead of showing 0
-- =============================================================================

CREATE OR REPLACE FUNCTION public.delete_session_customer(
    p_customer_id UUID
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
    v_active_orders_count INTEGER;
    v_session_id UUID;
    v_table_id UUID;
    v_remaining_customers_count INTEGER;
    v_remaining_active_orders INTEGER;
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

    -- Lock customer record
    SELECT * INTO v_customer
    FROM public.table_session_customers
    WHERE id = p_customer_id
    FOR UPDATE;

    IF v_customer IS NULL THEN
        RAISE EXCEPTION 'Customer not found';
    END IF;

    v_session_id := v_customer.session_id;

    -- Check if customer has active (non-cancelled) orders
    SELECT count(*) INTO v_active_orders_count
    FROM public.orders
    WHERE session_customer_id = p_customer_id AND status NOT IN ('cancelled');

    IF v_active_orders_count > 0 THEN
        RAISE EXCEPTION 'Cannot delete customer with active orders. Cancel orders first.';
    END IF;

    -- Preserve cancelled order history for reporting and audit trail:
    -- Dissociate customer reference rather than deleting order/items rows.
    UPDATE public.orders
    SET session_customer_id = NULL
    WHERE session_customer_id = p_customer_id;

    -- Delete customer record from active dining session
    DELETE FROM public.table_session_customers
    WHERE id = p_customer_id;

    -- Get associated table ID
    SELECT table_id INTO v_table_id
    FROM public.table_sessions
    WHERE id = v_session_id;

    -- Check remaining customers count
    SELECT count(*) INTO v_remaining_customers_count
    FROM public.table_session_customers
    WHERE session_id = v_session_id;

    -- Check remaining active orders in the entire table session
    SELECT count(*) INTO v_remaining_active_orders
    FROM public.orders
    WHERE session_id = v_session_id AND status NOT IN ('cancelled');

    -- If no active orders exist or no customers remain, table is available
    IF v_remaining_customers_count = 0 OR v_remaining_active_orders = 0 THEN
        IF v_table_id IS NOT NULL THEN
            UPDATE public.restaurant_tables
            SET status = 'available', updated_at = now()
            WHERE id = v_table_id;
        END IF;
    END IF;

    -- If 0 customers remain in session, complete/close the empty session
    IF v_remaining_customers_count = 0 THEN
        UPDATE public.table_sessions
        SET status = 'completed', closed_at = now(), updated_at = now()
        WHERE id = v_session_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'deleted_customer_id', p_customer_id,
        'session_id', v_session_id,
        'remaining_customers', v_remaining_customers_count,
        'table_available', (v_remaining_customers_count = 0 OR v_remaining_active_orders = 0)
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.delete_session_customer(UUID) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_session_customer(UUID) TO authenticated;
