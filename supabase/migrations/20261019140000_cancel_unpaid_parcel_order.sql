-- Migration: 20261019140000_cancel_unpaid_parcel_order.sql
-- Description: RPC to safely cancel an unpaid parcel order before settlement.

CREATE OR REPLACE FUNCTION public.cancel_unpaid_parcel_order(
    p_bill_id UUID,
    p_reason TEXT DEFAULT 'Customer cancelled parcel before payment'
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
    v_bill RECORD;
    v_order RECORD;
BEGIN
    -- 1. Authorization: cashier or super_admin
    SELECT role, assigned_roles INTO v_role, v_assigned_roles
    FROM public.user_profiles 
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR (
        v_role NOT IN ('cashier', 'super_admin') 
        AND NOT ('cashier' = ANY(v_assigned_roles) OR 'super_admin' = ANY(v_assigned_roles))
    ) THEN
        RAISE EXCEPTION 'Unauthorized: only cashier or super_admin can cancel parcel orders';
    END IF;

    -- 2. Verify bill
    SELECT * INTO v_bill FROM public.bills WHERE id = p_bill_id FOR UPDATE;
    IF v_bill IS NULL THEN
        RAISE EXCEPTION 'Bill not found';
    END IF;

    IF v_bill.status <> 'unpaid' THEN
        RAISE EXCEPTION 'Only unpaid bills can be cancelled (current status: %)', v_bill.status;
    END IF;

    -- 3. Verify order
    SELECT * INTO v_order FROM public.orders WHERE id = v_bill.order_id FOR UPDATE;
    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Parent order not found';
    END IF;

    IF v_order.order_type NOT IN ('takeaway', 'parcel') THEN
        RAISE EXCEPTION 'Only parcel/takeaway orders can be cancelled with this operation';
    END IF;

    -- 4. Mark bill as voided
    UPDATE public.bills 
    SET status = 'voided',
        void_reason = p_reason,
        voided_by = v_actor,
        voided_at = now(),
        updated_at = now()
    WHERE id = p_bill_id;

    -- 5. Mark items as cancelled
    UPDATE public.order_items 
    SET status = 'cancelled',
        cancellation_reason = p_reason,
        cancelled_by = v_actor,
        cancelled_at = now(),
        updated_at = now()
    WHERE order_id = v_order.id AND status <> 'cancelled';

    -- 6. Mark order as cancelled
    UPDATE public.orders 
    SET status = 'cancelled',
        notes = CASE 
            WHEN notes IS NULL OR TRIM(notes) = '' THEN '[CANCELLED: ' || p_reason || ']'
            ELSE notes || ' | [CANCELLED: ' || p_reason || ']'
        END,
        updated_at = now()
    WHERE id = v_order.id;

    -- 7. Audit log
    INSERT INTO public.audit_logs (
        user_id,
        action,
        entity_type,
        entity_id,
        old_data,
        new_data
    )
    VALUES (
        v_actor,
        'CANCEL_UNPAID_PARCEL',
        'bills',
        p_bill_id::text,
        jsonb_build_object(
            'bill_number', v_bill.bill_number,
            'order_number', v_order.order_number,
            'status', v_bill.status,
            'final_amount', v_bill.final_amount
        ),
        jsonb_build_object(
            'bill_number', v_bill.bill_number,
            'order_number', v_order.order_number,
            'status', 'voided',
            'reason', p_reason
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'bill_id', p_bill_id,
        'order_id', v_order.id,
        'bill_number', v_bill.bill_number
    );
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_unpaid_parcel_order(UUID, TEXT) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_unpaid_parcel_order(UUID, TEXT) TO authenticated;
