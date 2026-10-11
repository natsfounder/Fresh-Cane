-- ============================================================================
-- Migration: 20261008084500_fix_edit_parcel_bill_payments_and_categories.sql
-- Description: Fix edit_parcel_bill RPC
--   1. Fix UPDATE public.payments: remove non-existent `updated_at` column.
--   2. Maintain chk_payments_cash constraint on payments for cash orders.
--   3. Automatically resolve category_name_snapshot from menu_items.
--   4. Update public.orders total_amount and subtotal.
--   5. Support cashier, super_admin, and server staff roles.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.edit_parcel_bill(
    p_bill_id UUID,
    p_items JSONB -- Array of: [{"order_item_id": UUID, "menu_item_id": UUID, "item_name": TEXT, "category_name": TEXT, "quantity": INT, "unit_price": NUMERIC}]
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
    v_settings RECORD;
    v_item RECORD;
    v_item_id UUID;
    v_menu_item_id UUID;
    v_qty INTEGER;
    v_unit_price NUMERIC(10,2);
    v_item_name VARCHAR(150);
    v_cat_name VARCHAR(100);
    v_new_subtotal NUMERIC(10,2) := 0;
    v_tax_amount NUMERIC(10,2) := 0;
    v_final_amount NUMERIC(10,2) := 0;
    v_round_off NUMERIC(10,2) := 0;
    v_raw_total NUMERIC(10,2);
BEGIN
    -- Verify staff privileges
    IF v_actor IS NOT NULL THEN
        SELECT role, assigned_roles INTO v_role, v_assigned_roles
        FROM public.user_profiles 
        WHERE id = v_actor AND is_active = true;

        IF v_role IS NULL OR (
            v_role NOT IN ('cashier', 'super_admin', 'server') 
            AND NOT ('cashier' = ANY(v_assigned_roles) OR 'super_admin' = ANY(v_assigned_roles))
        ) THEN
            RAISE EXCEPTION 'Unauthorized: only cashier or super_admin can edit bills';
        END IF;
    END IF;

    -- Lock bill
    SELECT * INTO v_bill FROM public.bills WHERE id = p_bill_id FOR UPDATE;
    IF v_bill IS NULL THEN
        RAISE EXCEPTION 'Bill not found';
    END IF;

    IF v_bill.status = 'voided' THEN
        RAISE EXCEPTION 'Cannot edit a voided bill';
    END IF;

    -- Lock order
    SELECT * INTO v_order FROM public.orders WHERE id = v_bill.order_id FOR UPDATE;
    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order not found';
    END IF;

    -- Process each item entry
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
        order_item_id UUID,
        menu_item_id UUID,
        item_name TEXT,
        category_name TEXT,
        quantity INTEGER,
        unit_price NUMERIC(10,2)
    )
    LOOP
        v_item_id := v_item.order_item_id;
        v_menu_item_id := v_item.menu_item_id;
        v_qty := v_item.quantity;
        v_unit_price := v_item.unit_price;
        v_item_name := v_item.item_name;
        v_cat_name := COALESCE(v_item.category_name, 'General');

        -- If menu_item_id is provided, resolve real category name
        IF v_menu_item_id IS NOT NULL THEN
            SELECT COALESCE(c.name, 'General') INTO v_cat_name
            FROM public.menu_items mi
            LEFT JOIN public.categories c ON c.id = mi.category_id
            WHERE mi.id = v_menu_item_id;
        END IF;

        IF v_item_id IS NOT NULL THEN
            -- Existing order item
            IF v_qty <= 0 THEN
                -- Mark item as cancelled
                UPDATE public.order_items
                SET status = 'cancelled', updated_at = now()
                WHERE id = v_item_id AND order_id = v_order.id;
            ELSE
                -- Update item (supports item replacement if menu_item_id is provided)
                IF v_menu_item_id IS NOT NULL AND v_item_name IS NOT NULL THEN
                    UPDATE public.order_items
                    SET menu_item_id = v_menu_item_id,
                        item_name_snapshot = v_item_name,
                        category_name_snapshot = v_cat_name,
                        unit_price_snapshot = v_unit_price,
                        quantity = v_qty,
                        status = 'ordered',
                        updated_at = now()
                    WHERE id = v_item_id AND order_id = v_order.id;
                ELSE
                    UPDATE public.order_items
                    SET quantity = v_qty,
                        unit_price_snapshot = COALESCE(v_unit_price, unit_price_snapshot),
                        status = 'ordered',
                        updated_at = now()
                    WHERE id = v_item_id AND order_id = v_order.id;
                END IF;
            END IF;
        ELSE
            -- New item added / replaced as new
            IF v_qty > 0 AND v_menu_item_id IS NOT NULL THEN
                INSERT INTO public.order_items (
                    order_id,
                    menu_item_id,
                    item_name_snapshot,
                    category_name_snapshot,
                    unit_price_snapshot,
                    quantity,
                    status
                )
                VALUES (
                    v_order.id,
                    v_menu_item_id,
                    COALESCE(v_item_name, 'Item'),
                    v_cat_name,
                    v_unit_price,
                    v_qty,
                    'ordered'
                );
            END IF;
        END IF;
    END LOOP;

    -- Compute new subtotal from non-cancelled items
    SELECT COALESCE(SUM(unit_price_snapshot * quantity), 0)
    INTO v_new_subtotal
    FROM public.order_items
    WHERE order_id = v_order.id AND status <> 'cancelled';

    IF v_new_subtotal <= 0 THEN
        RAISE EXCEPTION 'Order cannot have 0 active items';
    END IF;

    -- Update parent order
    UPDATE public.orders
    SET subtotal = v_new_subtotal,
        total_amount = v_new_subtotal,
        notes = CASE 
            WHEN notes IS NULL OR notes NOT LIKE '%[EDITED]%' 
            THEN COALESCE(notes || ' ', '') || '[EDITED]'
            ELSE notes 
        END,
        updated_at = now()
    WHERE id = v_order.id;

    -- Read store settings for tax calculation (column is tax_rate_percentage)
    SELECT * INTO v_settings FROM public.store_settings LIMIT 1 FOR SHARE;
    IF v_settings IS NOT NULL AND v_settings.tax_rate_percentage > 0 THEN
        IF v_settings.is_tax_inclusive THEN
            v_tax_amount := round(v_new_subtotal - (v_new_subtotal / (1 + (v_settings.tax_rate_percentage / 100.0))), 2);
            v_raw_total := v_new_subtotal;
        ELSE
            v_tax_amount := round(v_new_subtotal * (v_settings.tax_rate_percentage / 100.0), 2);
            v_raw_total := v_new_subtotal + v_tax_amount;
        END IF;
    ELSE
        v_tax_amount := 0;
        v_raw_total := v_new_subtotal;
    END IF;

    v_final_amount := round(v_raw_total);
    v_round_off := v_final_amount - v_raw_total;

    -- Update bill
    UPDATE public.bills
    SET subtotal_amount = v_new_subtotal,
        tax_amount = v_tax_amount,
        round_off_amount = v_round_off,
        final_amount = v_final_amount,
        updated_at = now()
    WHERE id = p_bill_id;

    -- Update payment row if present (payments does NOT have updated_at column!)
    -- And handle cash_tendered / change_returned constraints
    UPDATE public.payments
    SET amount = v_final_amount,
        cash_tendered = CASE 
            WHEN payment_method = 'cash' 
            THEN GREATEST(COALESCE(cash_tendered, v_final_amount), v_final_amount) 
            ELSE NULL 
        END,
        change_returned = CASE 
            WHEN payment_method = 'cash' 
            THEN (GREATEST(COALESCE(cash_tendered, v_final_amount), v_final_amount) - v_final_amount) 
            ELSE NULL 
        END
    WHERE bill_id = p_bill_id;

    -- Audit log
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (
        v_actor,
        'PARCEL_BILL_EDITED',
        'bill',
        p_bill_id::text,
        jsonb_build_object(
            'bill_number', v_bill.bill_number,
            'old_amount', v_bill.final_amount,
            'new_amount', v_final_amount
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'bill_id', p_bill_id,
        'new_amount', v_final_amount,
        'message', 'Parcel bill updated successfully'
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.edit_parcel_bill(UUID, JSONB) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.edit_parcel_bill(UUID, JSONB) TO authenticated;
