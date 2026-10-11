-- =============================================================================
-- Migration: 20261002081000_fix_update_server_order_price.sql
-- Description:
--   Fix update_server_order RPC to properly use v_menu_item.base_price
--   (not v_menu_item.price) for add-on and base price calculations.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.update_server_order(
    p_order_id UUID,
    p_items JSONB,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_order RECORD;
    v_item RECORD;
    v_menu_item RECORD;
    v_item_qty INTEGER;
    v_unit_price NUMERIC(10,2);
    v_instructions TEXT;
    v_subtotal NUMERIC(10,2) := 0.00;
    v_total NUMERIC(10,2) := 0.00;
    v_item_subtotal NUMERIC(10,2) := 0.00;
    v_items_count INTEGER := 0;
BEGIN
    SELECT * INTO v_order
    FROM public.orders
    WHERE id = p_order_id
    FOR UPDATE;

    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order not found';
    END IF;

    IF v_order.status = 'cancelled' THEN
        RAISE EXCEPTION 'Cannot edit a cancelled order';
    END IF;

    IF v_order.status = 'completed' THEN
        RAISE EXCEPTION 'Cannot edit a completed/settled order';
    END IF;

    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Order must contain at least one item. To cancel an order, use Cancel Order.';
    END IF;

    DELETE FROM public.order_items
    WHERE order_id = p_order_id;

    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
        menu_item_id UUID,
        quantity INTEGER,
        special_instructions TEXT,
        unit_price NUMERIC
    ) LOOP
        v_item_qty := v_item.quantity;
        IF v_item_qty IS NULL OR v_item_qty <= 0 THEN
            CONTINUE;
        END IF;

        SELECT m.*, c.name AS cat_name
        INTO v_menu_item
        FROM public.menu_items m
        JOIN public.categories c ON c.id = m.category_id
        WHERE m.id = v_item.menu_item_id;

        IF v_menu_item IS NULL THEN
            RAISE EXCEPTION 'Menu item % not found', v_item.menu_item_id;
        END IF;

        v_instructions := NULLIF(trim(v_item.special_instructions), '');
        IF length(v_instructions) > 200 THEN
            v_instructions := substr(v_instructions, 1, 200);
        END IF;

        -- Use provided unit_price (base price + add-ons) if >= base_price
        v_unit_price := COALESCE(v_item.unit_price, v_menu_item.base_price);
        IF v_unit_price < v_menu_item.base_price THEN
            v_unit_price := v_menu_item.base_price;
        END IF;

        v_item_subtotal := round((v_unit_price * v_item_qty)::numeric, 2);
        v_subtotal := v_subtotal + v_item_subtotal;
        v_items_count := v_items_count + v_item_qty;

        INSERT INTO public.order_items (
            order_id,
            menu_item_id,
            item_name_snapshot,
            category_name_snapshot,
            unit_price_snapshot,
            quantity,
            special_instructions,
            status
        )
        VALUES (
            p_order_id,
            v_menu_item.id,
            v_menu_item.name,
            v_menu_item.cat_name,
            v_unit_price,
            v_item_qty,
            v_instructions,
            'ordered'
        );
    END LOOP;

    IF v_items_count = 0 THEN
        RAISE EXCEPTION 'Order must contain at least one item with valid quantity';
    END IF;

    v_total := v_subtotal;

    UPDATE public.orders
    SET subtotal = v_subtotal,
        total_amount = v_total,
        notes = NULLIF(trim(p_notes), ''),
        updated_at = now()
    WHERE id = p_order_id;

    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (
        v_actor,
        'ORDER_EDITED',
        'order',
        p_order_id::text,
        jsonb_build_object(
            'order_number', v_order.order_number,
            'table_id', v_order.table_id,
            'subtotal', v_subtotal,
            'items_count', v_items_count
        )
    );

    RETURN jsonb_build_object(
        'order_id', p_order_id,
        'order_number', v_order.order_number,
        'subtotal', v_subtotal,
        'total_amount', v_total,
        'items_count', v_items_count,
        'status', v_order.status
    );
END;
$$;

REVOKE ALL ON FUNCTION public.update_server_order(UUID, JSONB, TEXT) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_server_order(UUID, JSONB, TEXT) TO authenticated;
