-- Migration: 20261019131500_fix_audit_logs_columns_in_swap_payment.sql
-- Description: Fix audit_logs column names in swap_bill_payment_method (entity_type, entity_id instead of table_name, record_id).

CREATE OR REPLACE FUNCTION public.swap_bill_payment_method(
    p_bill_id UUID,
    p_new_payments JSONB,
    p_reason TEXT DEFAULT 'Payment method swapped by cashier'
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
    v_old_payments JSONB;
    v_payment_record JSONB;
    v_method VARCHAR(20);
    v_amount NUMERIC(10,2);
    v_cash_tendered NUMERIC(10,2);
    v_change_returned NUMERIC(10,2);
    v_tx_ref VARCHAR(100);
    v_total_paid NUMERIC(10,2) := 0;
    v_new_methods_summary TEXT := '';
    v_method_count INT := 0;
    v_current_local_date DATE;
BEGIN
    -- 1. Authorization: cashier or super_admin
    SELECT role, assigned_roles INTO v_role, v_assigned_roles
    FROM public.user_profiles
    WHERE id = v_actor AND is_active = true;

    IF v_role IS NULL OR (
        v_role NOT IN ('cashier', 'super_admin') 
        AND NOT ('cashier' = ANY(v_assigned_roles) OR 'super_admin' = ANY(v_assigned_roles))
    ) THEN
        RAISE EXCEPTION 'Unauthorized: only cashier or super_admin can swap payment methods';
    END IF;

    -- 2. Lock bill
    SELECT * INTO v_bill FROM public.bills WHERE id = p_bill_id FOR UPDATE;
    IF v_bill IS NULL THEN
        RAISE EXCEPTION 'Bill not found';
    END IF;

    -- 3. Verify bill is paid (cannot swap unpaid or voided bills)
    IF v_bill.status <> 'paid' THEN
        RAISE EXCEPTION 'Only paid bills can have payment method swapped (current status: %).', v_bill.status;
    END IF;

    -- 4. Same-Day Restriction: only allow swapping on the day the bill was generated
    v_current_local_date := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
    IF (v_bill.created_at AT TIME ZONE 'Asia/Kolkata')::DATE < v_current_local_date 
       AND (v_bill.business_date IS NULL OR v_bill.business_date < v_current_local_date) THEN
        RAISE EXCEPTION 'Payment method swap is strictly restricted to same-day bills (generated today).';
    END IF;

    -- 5. Validate new payment array
    IF p_new_payments IS NULL OR jsonb_array_length(p_new_payments) = 0 THEN
        RAISE EXCEPTION 'At least one new payment entry is required';
    END IF;

    -- 6. Lock parent order
    SELECT * INTO v_order FROM public.orders WHERE id = v_bill.order_id FOR UPDATE;

    -- 7. Snapshot old payments for audit log
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', p.id,
            'payment_method', p.payment_method,
            'amount', p.amount,
            'cash_tendered', p.cash_tendered,
            'transaction_reference', p.transaction_reference,
            'status', p.status
        )
    ) INTO v_old_payments
    FROM public.payments p
    WHERE p.bill_id = p_bill_id;

    -- 8. Validate and sum new payment entries
    FOR v_payment_record IN SELECT * FROM jsonb_array_elements(p_new_payments)
    LOOP
        v_method := LOWER(TRIM(COALESCE(v_payment_record->>'method', v_payment_record->>'payment_method', '')));
        v_amount := (v_payment_record->>'amount')::NUMERIC;
        v_cash_tendered := (v_payment_record->>'cash_tendered')::NUMERIC;
        v_tx_ref := COALESCE(v_payment_record->>'transaction_reference', v_payment_record->>'tx_ref');

        IF v_method IS NULL OR v_method NOT IN ('cash', 'upi', 'card') THEN
            RAISE EXCEPTION 'Invalid payment method: %. Must be cash, upi, or card', v_method;
        END IF;

        IF v_amount IS NULL OR v_amount <= 0 THEN
            RAISE EXCEPTION 'Payment amount must be greater than zero';
        END IF;

        v_total_paid := v_total_paid + v_amount;

        IF v_method_count > 0 THEN
            v_new_methods_summary := v_new_methods_summary || ' + ';
        END IF;
        v_new_methods_summary := v_new_methods_summary || UPPER(v_method) || ' (₹' || v_amount::TEXT || ')';
        v_method_count := v_method_count + 1;
    END LOOP;

    -- 9. Strict Amount Check: Total of new payments MUST equal bill final_amount
    IF ROUND(v_total_paid, 2) <> ROUND(v_bill.final_amount, 2) THEN
        RAISE EXCEPTION 'New payments sum (₹%) does not match bill final amount (₹%)',
            ROUND(v_total_paid, 2), ROUND(v_bill.final_amount, 2);
    END IF;

    -- 10. Atomic replacement of payment rows
    DELETE FROM public.payments WHERE bill_id = p_bill_id;

    FOR v_payment_record IN SELECT * FROM jsonb_array_elements(p_new_payments)
    LOOP
        v_method := LOWER(TRIM(COALESCE(v_payment_record->>'method', v_payment_record->>'payment_method', '')));
        v_amount := (v_payment_record->>'amount')::NUMERIC;
        v_cash_tendered := (v_payment_record->>'cash_tendered')::NUMERIC;
        v_tx_ref := COALESCE(v_payment_record->>'transaction_reference', v_payment_record->>'tx_ref');

        IF v_method = 'cash' THEN
            IF v_cash_tendered IS NULL OR v_cash_tendered < v_amount THEN
                v_cash_tendered := v_amount;
            END IF;
            v_change_returned := v_cash_tendered - v_amount;
        ELSE
            v_cash_tendered := NULL;
            v_change_returned := NULL;
        END IF;

        INSERT INTO public.payments (
            id,
            bill_id,
            payment_method,
            amount,
            cash_tendered,
            change_returned,
            transaction_reference,
            received_by,
            status,
            created_at
        )
        VALUES (
            gen_random_uuid(),
            p_bill_id,
            v_method,
            v_amount,
            v_cash_tendered,
            v_change_returned,
            v_tx_ref,
            COALESCE(v_actor, v_bill.cashier_id),
            'completed',
            v_bill.created_at
        );
    END LOOP;

    -- 11. Append [EDITED] and payment swap note to parent order notes
    IF v_order.id IS NOT NULL THEN
        UPDATE public.orders
        SET notes = CASE
            WHEN notes IS NULL OR TRIM(notes) = '' THEN
                '[EDITED] (Payment swapped to ' || v_new_methods_summary || ')'
            WHEN notes NOT LIKE '%[EDITED]%' THEN
                notes || ' | [EDITED] (Payment swapped to ' || v_new_methods_summary || ')'
            ELSE
                notes || ' | (Payment swapped to ' || v_new_methods_summary || ')'
        END,
        updated_at = now()
        WHERE id = v_order.id;
    END IF;

    -- 12. Record audit log using correct schema (entity_type, entity_id)
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
        'SWAP_PAYMENT_METHOD',
        'bills',
        p_bill_id::text,
        jsonb_build_object(
            'bill_number', v_bill.bill_number,
            'final_amount', v_bill.final_amount,
            'old_payments', v_old_payments
        ),
        jsonb_build_object(
            'bill_number', v_bill.bill_number,
            'final_amount', v_bill.final_amount,
            'new_payments', p_new_payments,
            'methods_summary', v_new_methods_summary,
            'reason', p_reason
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'bill_id', p_bill_id,
        'bill_number', v_bill.bill_number,
        'final_amount', v_bill.final_amount,
        'methods_summary', v_new_methods_summary
    );
END;
$$;
