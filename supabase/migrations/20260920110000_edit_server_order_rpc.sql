-- Migration: 20260920110000_edit_server_order_rpc.sql
-- Description: RPC functions to fetch order line items and edit existing server orders in-place.

-- 1. RPC get_server_order_details: Retrieve an active order's details & line items
CREATE OR REPLACE FUNCTION public.get_server_order_details(p_order_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order RECORD;
    v_items JSONB := '[]'::jsonb;
BEGIN
    SELECT 
        o.id,
        o.order_number,
        o.status,
        o.notes,
        o.table_id,
        o.session_id,
        o.session_customer_id,
        o.customer_name,
        o.subtotal,
        o.total_amount,
        o.created_at
    INTO v_order
    FROM public.orders o
    WHERE o.id = p_order_id;

    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order not found';
    END IF;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', oi.id,
                'menu_item_id', oi.menu_item_id,
                'item_name', oi.item_name_snapshot,
                'category_name', oi.category_name_snapshot,
                'unit_price', oi.unit_price_snapshot,
                'quantity', oi.quantity,
                'subtotal', (oi.unit_price_snapshot * oi.quantity),
                'special_instructions', oi.special_instructions
            )
            ORDER BY oi.created_at ASC
        ),
        '[]'::jsonb
    )
    INTO v_items
    FROM public.order_items oi
    WHERE oi.order_id = p_order_id AND oi.status <> 'cancelled';

    RETURN jsonb_build_object(
        'order_id', v_order.id,
        'order_number', v_order.order_number,
        'status', v_order.status,
        'notes', v_order.notes,
        'table_id', v_order.table_id,
        'session_id', v_order.session_id,
        'session_customer_id', v_order.session_customer_id,
        'customer_name', v_order.customer_name,
        'subtotal', v_order.subtotal,
        'total_amount', v_order.total_amount,
        'created_at', v_order.created_at,
        'items', v_items
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_server_order_details(UUID) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_server_order_details(UUID) TO authenticated;


-- 2. RPC update_server_order: Atomically update an existing server order's line items and notes in-place
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
    v_instructions TEXT;
    v_subtotal NUMERIC(10,2) := 0.00;
    v_total NUMERIC(10,2) := 0.00;
    v_item_subtotal NUMERIC(10,2) := 0.00;
    v_items_count INTEGER := 0;
BEGIN
    -- Verify order exists
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

    -- Delete existing active order items for this order to replace with updated list
    DELETE FROM public.order_items
    WHERE order_id = p_order_id;

    -- Re-insert updated order items
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
        menu_item_id UUID,
        quantity INTEGER,
        special_instructions TEXT
    ) LOOP
        v_item_qty := v_item.quantity;
        IF v_item_qty IS NULL OR v_item_qty <= 0 THEN
            CONTINUE; -- Skip items with zero or negative quantity
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

        v_item_subtotal := round((v_menu_item.price * v_item_qty)::numeric, 2);
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
            v_menu_item.price,
            v_item_qty,
            v_instructions,
            'ordered'
        );
    END LOOP;

    IF v_items_count = 0 THEN
        RAISE EXCEPTION 'Order must contain at least one item with valid quantity';
    END IF;

    v_total := v_subtotal; -- Additional tax/discount rules can be applied if configured

    -- Update order header
    UPDATE public.orders
    SET subtotal = v_subtotal,
        total_amount = v_total,
        notes = NULLIF(trim(p_notes), ''),
        updated_at = now()
    WHERE id = p_order_id;

    -- Audit Log
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (
        v_actor,
        'ORDER_EDITED',
        'order',
        p_order_id::text,
        jsonb_build_object(
            'order_number', v_order.order_number,
            'table_id', v_order.table_id,
            'session_id', v_order.session_id,
            'items_count', v_items_count,
            'total_amount', v_total
        )
    );

    RETURN jsonb_build_object(
        'order_id', p_order_id,
        'order_number', v_order.order_number,
        'status', v_order.status,
        'total_amount', v_total,
        'items_count', v_items_count
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_server_order(UUID, JSONB, TEXT) FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_server_order(UUID, JSONB, TEXT) TO authenticated;
