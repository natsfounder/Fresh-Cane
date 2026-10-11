-- =============================================================================
-- Migration: 20261002060000_delete_session_customer_and_cascade_cancel.sql
-- Description: 
--   1. Create public.delete_session_customer(p_customer_id UUID) RPC
--   2. Update public.cancel_server_order to automatically delete the customer
--      if they have no remaining active orders.
--   3. Automatically set table status to 'available' when session has no active orders.
-- =============================================================================

-- 1. Function: delete_session_customer
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
        RETURN jsonb_build_object('success', true, 'message', 'Customer already deleted');
    END IF;

    v_session_id := v_customer.session_id;

    -- Check if customer has active (non-cancelled) orders
    SELECT count(*) INTO v_active_orders_count
    FROM public.orders
    WHERE session_customer_id = p_customer_id AND status NOT IN ('cancelled');

    IF v_active_orders_count > 0 THEN
        RAISE EXCEPTION 'Cannot delete customer with active orders. Cancel orders first.';
    END IF;

    -- Delete any cancelled order line items and orders for this customer to prevent orphan rows
    DELETE FROM public.order_items
    WHERE order_id IN (
        SELECT id FROM public.orders WHERE session_customer_id = p_customer_id
    );

    DELETE FROM public.orders
    WHERE session_customer_id = p_customer_id;

    -- Delete customer record
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

-- 2. Update cancel_server_order to automatically delete the customer if no orders remain
CREATE OR REPLACE FUNCTION public.cancel_server_order(
    p_order_id UUID,
    p_reason TEXT DEFAULT 'Cancelled by server'
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
    v_order RECORD;
    v_session_customer_id UUID;
    v_remaining_cust_orders INTEGER;
    v_customer_was_deleted BOOLEAN := false;
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

    -- Lock order row
    SELECT * INTO v_order
    FROM public.orders
    WHERE id = p_order_id
    FOR UPDATE;

    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order not found';
    END IF;

    IF v_order.status = 'cancelled' THEN
        RAISE EXCEPTION 'Order is already cancelled';
    END IF;

    IF v_order.status = 'completed' THEN
        RAISE EXCEPTION 'Cannot cancel completed/settled order';
    END IF;

    v_session_customer_id := v_order.session_customer_id;

    -- Update order status to cancelled
    UPDATE public.orders
    SET status = 'cancelled',
        cancelled_at = now(),
        cancelled_by = v_actor,
        cancellation_reason = COALESCE(NULLIF(trim(p_reason), ''), 'Cancelled by server'),
        updated_at = now()
    WHERE id = p_order_id;

    -- Update order line items
    UPDATE public.order_items
    SET status = 'cancelled',
        updated_at = now()
    WHERE order_id = p_order_id;

    -- Audit log
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (
        v_actor,
        'ORDER_CANCELLED',
        'order',
        p_order_id::text,
        jsonb_build_object(
            'order_number', v_order.order_number,
            'table_id', v_order.table_id,
            'session_id', v_order.session_id,
            'reason', p_reason
        )
    );

    -- Check if this customer now has 0 remaining active orders
    IF v_session_customer_id IS NOT NULL THEN
        SELECT count(*) INTO v_remaining_cust_orders
        FROM public.orders
        WHERE session_customer_id = v_session_customer_id AND status NOT IN ('cancelled');

        IF v_remaining_cust_orders = 0 THEN
            -- Delete customer instantly as requested by user
            PERFORM public.delete_session_customer(v_session_customer_id);
            v_customer_was_deleted := true;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'order_id', p_order_id,
        'order_number', v_order.order_number,
        'status', 'cancelled',
        'customer_deleted', v_customer_was_deleted
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cancel_server_order(UUID, TEXT) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_server_order(UUID, TEXT) TO authenticated;

-- Allow authenticated staff to delete table_session_customers directly if needed
DROP POLICY IF EXISTS "Staff can delete session customers" ON public.table_session_customers;
CREATE POLICY "Staff can delete session customers"
    ON public.table_session_customers FOR DELETE
    TO authenticated
    USING (public.is_staff());
