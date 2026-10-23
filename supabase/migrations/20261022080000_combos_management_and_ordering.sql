-- Migration: 20261022080000_combos_management_and_ordering.sql
-- Description: Implement Combos management with atomic synchronization to menu_items and categories.

-- 1. Ensure 'Combos' category exists in public.categories
INSERT INTO public.categories (name, slug, display_order, is_active)
VALUES ('Combos', 'combos', 99, true)
ON CONFLICT (slug) DO UPDATE SET is_active = true, name = 'Combos';

-- 2. Create public.combos table
CREATE TABLE IF NOT EXISTS public.combos (
    id             UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    name           VARCHAR(150)  NOT NULL,
    description    TEXT          NULL,
    price          NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    is_available   BOOLEAN       NOT NULL DEFAULT true,
    is_active      BOOLEAN       NOT NULL DEFAULT true,
    display_order  INTEGER       NOT NULL DEFAULT 0,
    menu_item_id   UUID          NULL REFERENCES public.menu_items(id) ON DELETE SET NULL,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- 3. Create public.combo_items table
CREATE TABLE IF NOT EXISTS public.combo_items (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    combo_id      UUID        NOT NULL REFERENCES public.combos(id) ON DELETE CASCADE,
    menu_item_id  UUID        NOT NULL REFERENCES public.menu_items(id) ON DELETE RESTRICT,
    quantity      INTEGER     NOT NULL DEFAULT 1 CHECK (quantity > 0),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_combo_items_combo_id ON public.combo_items (combo_id);
CREATE INDEX IF NOT EXISTS idx_combos_active ON public.combos (is_active, display_order);

-- 4. Enable RLS and permissions
ALTER TABLE public.combos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.combo_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read active combos" ON public.combos;
CREATE POLICY "Anyone can read active combos" ON public.combos
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Staff can manage combos" ON public.combos;
CREATE POLICY "Staff can manage combos" ON public.combos
    FOR ALL USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Anyone can read combo items" ON public.combo_items;
CREATE POLICY "Anyone can read combo items" ON public.combo_items
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Staff can manage combo items" ON public.combo_items;
CREATE POLICY "Staff can manage combo items" ON public.combo_items
    FOR ALL USING (auth.uid() IS NOT NULL);

GRANT ALL ON public.combos TO authenticated;
GRANT SELECT ON public.combos TO anon;
GRANT ALL ON public.combo_items TO authenticated;
GRANT SELECT ON public.combo_items TO anon;

-- 5. RPC: save_combo
-- Transactionally saves combo metadata, combo_items, and synchronizes to menu_items under 'Combos' category.
CREATE OR REPLACE FUNCTION public.save_combo(
    p_id UUID,
    p_name VARCHAR(150),
    p_price NUMERIC(10,2),
    p_is_available BOOLEAN DEFAULT true,
    p_is_active BOOLEAN DEFAULT true,
    p_items JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_combo_id UUID := p_id;
    v_combos_cat_id UUID;
    v_menu_item_id UUID;
    v_desc_parts TEXT[] := ARRAY[]::TEXT[];
    v_item JSONB;
    v_m_id UUID;
    v_qty INT;
    v_m_name TEXT;
    v_final_desc TEXT;
BEGIN
    -- 1. Ensure Combos category exists
    SELECT id INTO v_combos_cat_id FROM public.categories WHERE slug = 'combos' LIMIT 1;
    IF v_combos_cat_id IS NULL THEN
        INSERT INTO public.categories (name, slug, display_order, is_active)
        VALUES ('Combos', 'combos', 99, true)
        RETURNING id INTO v_combos_cat_id;
    END IF;

    -- 2. Build items description string e.g. "Includes: 2x Item A, 1x Item B"
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_m_id := (v_item->>'menu_item_id')::UUID;
        v_qty := COALESCE((v_item->>'quantity')::INT, 1);
        SELECT name INTO v_m_name FROM public.menu_items WHERE id = v_m_id;
        IF v_m_name IS NOT NULL THEN
            v_desc_parts := array_append(v_desc_parts, v_qty || 'x ' || v_m_name);
        END IF;
    END LOOP;

    IF array_length(v_desc_parts, 1) > 0 THEN
        v_final_desc := 'Includes: ' || array_to_string(v_desc_parts, ', ');
    ELSE
        v_final_desc := 'Combo Special';
    END IF;

    -- 3. Upsert combo header
    IF v_combo_id IS NOT NULL THEN
        SELECT menu_item_id INTO v_menu_item_id FROM public.combos WHERE id = v_combo_id;

        UPDATE public.combos
        SET name = trim(p_name),
            description = v_final_desc,
            price = p_price,
            is_available = p_is_available,
            is_active = p_is_active,
            updated_at = now()
        WHERE id = v_combo_id;
    ELSE
        v_combo_id := gen_random_uuid();

        INSERT INTO public.combos (id, name, description, price, is_available, is_active)
        VALUES (v_combo_id, trim(p_name), v_final_desc, p_price, p_is_available, p_is_active);
    END IF;

    -- 4. Sync to menu_items so order-taking, billing, and reports work seamlessly
    IF v_menu_item_id IS NOT NULL THEN
        UPDATE public.menu_items
        SET name = trim(p_name),
            category_id = v_combos_cat_id,
            base_price = p_price,
            description = v_final_desc,
            is_available = p_is_available,
            is_active = p_is_active,
            updated_at = now()
        WHERE id = v_menu_item_id;
    ELSE
        v_menu_item_id := gen_random_uuid();
        INSERT INTO public.menu_items (
            id, category_id, name, description, base_price, is_available, is_active, display_order
        )
        VALUES (
            v_menu_item_id, v_combos_cat_id, trim(p_name), v_final_desc, p_price, p_is_available, p_is_active, 999
        );

        UPDATE public.combos SET menu_item_id = v_menu_item_id WHERE id = v_combo_id;
    END IF;

    -- 5. Atomic replacement of combo_items
    DELETE FROM public.combo_items WHERE combo_id = v_combo_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_m_id := (v_item->>'menu_item_id')::UUID;
        v_qty := COALESCE((v_item->>'quantity')::INT, 1);
        IF v_qty > 0 AND v_m_id IS NOT NULL THEN
            INSERT INTO public.combo_items (combo_id, menu_item_id, quantity)
            VALUES (v_combo_id, v_m_id, v_qty);
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'combo_id', v_combo_id,
        'menu_item_id', v_menu_item_id,
        'name', trim(p_name),
        'description', v_final_desc
    );
END;
$$;

-- 6. RPC: delete_combo
CREATE OR REPLACE FUNCTION public.delete_combo(p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_menu_item_id UUID;
BEGIN
    SELECT menu_item_id INTO v_menu_item_id FROM public.combos WHERE id = p_id;

    -- If referenced by orders, soft-delete menu_item so order history remains intact
    IF v_menu_item_id IS NOT NULL THEN
        UPDATE public.menu_items SET is_active = false, is_available = false WHERE id = v_menu_item_id;
    END IF;

    DELETE FROM public.combo_items WHERE combo_id = p_id;
    DELETE FROM public.combos WHERE id = p_id;

    RETURN jsonb_build_object('success', true, 'deleted_id', p_id);
END;
$$;

-- 7. RPC: fetch_combos_with_items
CREATE OR REPLACE FUNCTION public.fetch_combos_with_items()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', c.id,
            'name', c.name,
            'description', c.description,
            'price', c.price,
            'is_available', c.is_available,
            'is_active', c.is_active,
            'display_order', c.display_order,
            'menu_item_id', c.menu_item_id,
            'created_at', c.created_at,
            'items_count', COALESCE((SELECT SUM(ci.quantity) FROM public.combo_items ci WHERE ci.combo_id = c.id), 0),
            'items', COALESCE((
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', ci.id,
                        'menu_item_id', ci.menu_item_id,
                        'quantity', ci.quantity,
                        'item_name', m.name,
                        'base_price', m.base_price
                    )
                )
                FROM public.combo_items ci
                JOIN public.menu_items m ON m.id = ci.menu_item_id
                WHERE ci.combo_id = c.id
            ), '[]'::jsonb)
        ) ORDER BY c.created_at DESC
    ), '[]'::jsonb) INTO v_result
    FROM public.combos c;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.save_combo(UUID, VARCHAR, NUMERIC, BOOLEAN, BOOLEAN, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_combo(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_combos_with_items() TO authenticated, anon;
