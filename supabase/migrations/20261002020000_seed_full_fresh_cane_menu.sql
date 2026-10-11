-- =============================================================================
-- Migration: Seed Complete Fresh Cane Menu (All 22 Categories & Full Food Items)
-- =============================================================================

-- Ensure image_url column exists in public.categories
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'categories' 
          AND column_name = 'image_url'
    ) THEN
        ALTER TABLE public.categories ADD COLUMN image_url TEXT NULL;
    END IF;
END $$;

-- 1. Insert/Update all 22 Menu Categories
INSERT INTO public.categories (name, slug, display_order, is_active, image_url)
VALUES
    ('Signature',         'signature',         1,  true, 'assets/images/categories/signature.png'),
    ('Rolls',             'rolls',             2,  true, 'assets/images/categories/rolls.png'),
    ('Fries',             'fries',             3,  true, 'assets/images/categories/fries.png'),
    ('Loaded Fries',      'loaded-fries',      4,  true, 'assets/images/categories/loaded-fries.png'),
    ('Nuggets',           'nuggets',           5,  true, 'assets/images/categories/nuggets.png'),
    ('Wrap',              'wrap',              6,  true, 'assets/images/categories/wrap.png'),
    ('Burgers',           'burgers',           7,  true, 'assets/images/categories/burgers.png'),
    ('Fried Items',       'fried-items',       8,  true, 'assets/images/categories/fried-items.png'),
    ('Sandwich',          'sandwich',          9,  true, 'assets/images/categories/sandwich.png'),
    ('Regular Cane',      'regular-cane',      10, true, 'assets/images/categories/regular-cane.png'),
    ('Fruit Cane',        'fruit-cane',        11, true, 'assets/images/categories/fruit-cane.png'),
    ('Lime Items',        'lime-items',        12, true, 'assets/images/categories/lime-items.png'),
    ('Fresh Juice',       'fresh-juice',       13, true, 'assets/images/categories/fresh-juice.png'),
    ('Milk Shake',        'milk-shake',        14, true, 'assets/images/categories/milk-shake.png'),
    ('Ice Cream Shake',   'ice-cream-shake',   15, true, 'assets/images/categories/ice-cream-shake.png'),
    ('Chocolate Shake',   'chocolate-shake',   16, true, 'assets/images/categories/chocolate-shake.png'),
    ('Cold Items',        'cold-items',        17, true, 'assets/images/categories/cold-items.png'),
    ('Falooda',           'falooda',           18, true, 'assets/images/categories/falooda.png'),
    ('Malba',             'malba',             19, true, 'assets/images/categories/malba.png'),
    ('Mojito',            'mojito',            20, true, 'assets/images/categories/mojito.png'),
    ('Healthy',           'healthy',           21, true, 'assets/images/categories/healthy.png'),
    ('Momos',             'momos',             22, true, 'assets/images/categories/momos.png')
ON CONFLICT (slug) DO UPDATE SET
    name = EXCLUDED.name,
    display_order = EXCLUDED.display_order,
    is_active = EXCLUDED.is_active,
    image_url = EXCLUDED.image_url;

-- Helper function to insert menu items cleanly
CREATE OR REPLACE FUNCTION _seed_menu_item(
    p_category_slug TEXT,
    p_name TEXT,
    p_price NUMERIC,
    p_desc TEXT DEFAULT NULL,
    p_order INT DEFAULT 0
) RETURNS VOID AS $$
DECLARE
    v_cat_id UUID;
BEGIN
    SELECT id INTO v_cat_id FROM public.categories WHERE slug = p_category_slug;
    IF v_cat_id IS NOT NULL THEN
        -- Insert or update item by name within the category
        INSERT INTO public.menu_items (category_id, name, description, base_price, is_available, is_active, display_order)
        VALUES (v_cat_id, p_name, p_desc, p_price, true, true, p_order)
        ON CONFLICT (id) DO NOTHING;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Deactivate old placeholder menu items and categories so they don't appear in app while preserving foreign keys
UPDATE public.menu_items SET is_active = false WHERE category_id IN (
    SELECT id FROM public.categories WHERE slug IN ('fresh-juices', 'milkshakes', 'snacks')
);
UPDATE public.categories SET is_active = false WHERE slug IN ('fresh-juices', 'milkshakes', 'snacks');

-- 2. Insert All Food Items for each category
-- 2.1 SIGNATURE
SELECT _seed_menu_item('signature', 'Kannur Cocktail', 90, 'Special cocktail blend', 1);
SELECT _seed_menu_item('signature', 'Black Grape', 90, 'Blackcurrant & grape infusion', 2);
SELECT _seed_menu_item('signature', 'Choco Mango', 90, 'Mango, dates & boost blend', 3);
SELECT _seed_menu_item('signature', 'Mango Smoothie', 90, 'Rich creamy mango smoothie', 4);
SELECT _seed_menu_item('signature', 'Butter Delights', 100, 'Butter & dates fusion', 5);
SELECT _seed_menu_item('signature', 'Mango Delights', 100, 'Mango & dates blend', 6);
SELECT _seed_menu_item('signature', 'Arabian Delights', 100, 'Rich arabian dates shake', 7);
SELECT _seed_menu_item('signature', 'Cloudy', 100, 'Apple & butterscotch blend', 8);
SELECT _seed_menu_item('signature', 'Mango Miracle', 100, 'Mango & fresh mint', 9);
SELECT _seed_menu_item('signature', 'Butter Seetha', 100, 'Butterscotch & seetha custard', 10);
SELECT _seed_menu_item('signature', 'Biscoff Maniac', 120, 'Lotus biscoff & fudge brownie', 11);

-- 2.2 ROLLS
SELECT _seed_menu_item('rolls', 'Veg Roll', 90, 'Crispy spiced vegetable roll', 1);
SELECT _seed_menu_item('rolls', 'Egg Roll', 90, 'Double egg rolled paratha', 2);
SELECT _seed_menu_item('rolls', 'Paneer Roll', 100, 'Marinated spiced paneer roll', 3);
SELECT _seed_menu_item('rolls', 'Chicken Roll', 100, 'Juicy spiced chicken roll', 4);

-- 2.3 FRIES
SELECT _seed_menu_item('fries', 'French Fries', 70, 'Crispy golden salted fries', 1);
SELECT _seed_menu_item('fries', 'Masala Fries', 80, 'Desi spiced seasoned fries', 2);
SELECT _seed_menu_item('fries', 'Peri Peri Fries', 80, 'Hot peri peri dusted fries', 3);

-- 2.4 LOADED FRIES
SELECT _seed_menu_item('loaded-fries', 'Chicken Loaded Fries', 150, 'Fries loaded with tender chicken & cheese', 1);
SELECT _seed_menu_item('loaded-fries', 'Mexican Loaded Fries', 160, 'Jalapenos, salsa & cheddar cheese', 2);
SELECT _seed_menu_item('loaded-fries', 'Turkish Loaded Fries', 180, 'Turkish spiced meat & signature sauce', 3);
SELECT _seed_menu_item('loaded-fries', 'Full Meat Loaded Fries', 230, 'Double portion premium meat loaded fries', 4);

-- 2.5 NUGGETS
SELECT _seed_menu_item('nuggets', 'Chicken Nuggets', 100, 'Golden fried juicy chicken nuggets', 1);
SELECT _seed_menu_item('nuggets', 'Veg Nuggets', 100, 'Crispy golden vegetable nuggets', 2);

-- 2.6 WRAP
SELECT _seed_menu_item('wrap', 'Veg Wrap', 100, 'Fresh seasoned veggie tortilla wrap', 1);
SELECT _seed_menu_item('wrap', 'Tender Wrap', 140, 'Crispy chicken tenders with lettuce & mayo', 2);
SELECT _seed_menu_item('wrap', 'Italian Wrap', 140, 'Herb spiced Italian dressing wrap', 3);
SELECT _seed_menu_item('wrap', 'Afgani Wrap', 140, 'Creamy mildly spiced Afghani chicken wrap', 4);

-- 2.7 BURGERS
SELECT _seed_menu_item('burgers', 'Veg Burger', 80, 'Classic crispy veggie patty burger', 1);
SELECT _seed_menu_item('burgers', 'Chicken Burger', 90, 'Classic juicy chicken patty burger', 2);
SELECT _seed_menu_item('burgers', 'Paneer Burger', 100, 'Grilled marinated paneer steak burger', 3);
SELECT _seed_menu_item('burgers', 'Zinger Burger', 120, 'Extra crispy spiced fried chicken burger', 4);
SELECT _seed_menu_item('burgers', 'Peri Peri Burger', 120, 'Fiery peri peri spiced burger', 5);
SELECT _seed_menu_item('burgers', 'Shezwan Chicken Burger', 130, 'Spicy Schezwan chicken burger', 6);
SELECT _seed_menu_item('burgers', 'Double Decker Burger', 160, 'Double patty loaded signature burger', 7);

-- 2.8 FRIED ITEMS
SELECT _seed_menu_item('fried-items', 'Wings', 130, 'Crispy seasoned chicken wings', 1);
SELECT _seed_menu_item('fried-items', 'Dynamic Wings', 180, 'Tossed in dynamic spicy glaze', 2);
SELECT _seed_menu_item('fried-items', 'Strips', 130, 'Boneless crispy chicken strips', 3);
SELECT _seed_menu_item('fried-items', 'Dynamic Strips', 180, 'Strips tossed in dynamic sauce', 4);
SELECT _seed_menu_item('fried-items', 'Chicken Popcorn', 100, 'Bite-sized crunchy chicken popcorn', 5);
SELECT _seed_menu_item('fried-items', 'Dynamic Popcorn', 150, 'Saucy glazed chicken popcorn', 6);

-- 2.9 SANDWICH
SELECT _seed_menu_item('sandwich', 'Veg Sandwich', 60, 'Fresh tomato, cucumber & mint chutney', 1);
SELECT _seed_menu_item('sandwich', 'Chicken Sandwich', 80, 'Shredded chicken with herbs & mayo', 2);
SELECT _seed_menu_item('sandwich', 'Egg Sandwich', 70, 'Fluffy egg omelette grilled sandwich', 3);
SELECT _seed_menu_item('sandwich', 'Paneer Sandwich', 70, 'Spiced paneer filling sandwich', 4);
SELECT _seed_menu_item('sandwich', 'Chicken Club', 120, 'Triple decker chicken club sandwich', 5);
SELECT _seed_menu_item('sandwich', 'Veg Club', 100, 'Triple decker vegetable club sandwich', 6);
SELECT _seed_menu_item('sandwich', 'Jumbo Club', 160, 'Loaded double meat jumbo club sandwich', 7);

-- 2.10 REGULAR CANE
SELECT _seed_menu_item('regular-cane', 'Sugar Cane', 40, '100% pure cold-pressed natural sugarcane', 1);
SELECT _seed_menu_item('regular-cane', 'Lime Cane', 40, 'Sugarcane freshly squeezed with lemon', 2);
SELECT _seed_menu_item('regular-cane', 'Mint Cane', 40, 'Sugarcane blended with garden mint', 3);
SELECT _seed_menu_item('regular-cane', 'Ginger Cane', 40, 'Sugarcane infused with spicy ginger', 4);

-- 2.11 FRUIT CANE
SELECT _seed_menu_item('fruit-cane', 'Pineapple Cane', 50, 'Sugarcane infused with fresh pineapple', 1);
SELECT _seed_menu_item('fruit-cane', 'Watermelon Cane', 50, 'Sugarcane with crisp watermelon', 2);
SELECT _seed_menu_item('fruit-cane', 'Musk Melon Cane', 50, 'Sugarcane with sweet musk melon', 3);
SELECT _seed_menu_item('fruit-cane', 'Grape Cane', 50, 'Sugarcane with fresh grapes', 4);
SELECT _seed_menu_item('fruit-cane', 'Pomegranate Cane', 60, 'Sugarcane with ruby red pomegranate', 5);
SELECT _seed_menu_item('fruit-cane', 'Mango Cane', 60, 'Sugarcane with seasonal mango pulp', 6);
SELECT _seed_menu_item('fruit-cane', 'Guava Cane', 70, 'Sugarcane with pink guava juice', 7);
SELECT _seed_menu_item('fruit-cane', 'Strawberry Cane', 70, 'Sugarcane with real strawberry pulp', 8);
SELECT _seed_menu_item('fruit-cane', 'Avocado Cane', 70, 'Sugarcane blended with fresh avocado', 9);
SELECT _seed_menu_item('fruit-cane', 'Tender Cane', 70, 'Sugarcane with fresh tender coconut', 10);

-- 2.12 LIME ITEMS
SELECT _seed_menu_item('lime-items', 'Lime', 30, 'Freshly squeezed classic lime juice', 1);
SELECT _seed_menu_item('lime-items', 'Mint Lime', 40, 'Lime with muddled fresh mint leaves', 2);
SELECT _seed_menu_item('lime-items', 'Ginger Lime', 40, 'Lime with crushed fresh ginger', 3);
SELECT _seed_menu_item('lime-items', 'Pineapple Lime', 50, 'Pineapple infused tangy lime juice', 4);
SELECT _seed_menu_item('lime-items', 'Grape Lime', 50, 'Sweet grapes combined with lime', 5);
SELECT _seed_menu_item('lime-items', 'Melon Lime', 50, 'Refreshing musk melon and lime', 6);
SELECT _seed_menu_item('lime-items', 'Mango Lime', 50, 'Sweet mango with tangy lime', 7);

-- 2.13 FRESH JUICE
SELECT _seed_menu_item('fresh-juice', 'Watermelon', 50, 'Hydrating fresh watermelon juice', 1);
SELECT _seed_menu_item('fresh-juice', 'Muskmelon', 50, 'Sweet natural muskmelon juice', 2);
SELECT _seed_menu_item('fresh-juice', 'Grape', 60, 'Freshly pressed black/green grapes', 3);
SELECT _seed_menu_item('fresh-juice', 'Pineapple', 60, 'Tropical pulpy pineapple juice', 4);
SELECT _seed_menu_item('fresh-juice', 'Papaya', 50, 'Ripe papaya rich fruit juice', 5);
SELECT _seed_menu_item('fresh-juice', 'Orange', 70, '100% pure fresh orange juice', 6);
SELECT _seed_menu_item('fresh-juice', 'Mosambi', 70, 'Sweet lime freshly extracted', 7);

-- 2.14 MILK SHAKE
SELECT _seed_menu_item('milk-shake', 'Apple Milkshake', 80, 'Fresh apple milk blend', 1);
SELECT _seed_menu_item('milk-shake', 'Pomegranate Milkshake', 80, 'Fresh pomegranate shake', 2);
SELECT _seed_menu_item('milk-shake', 'Mango Milkshake', 80, 'Thick creamy mango shake', 3);
SELECT _seed_menu_item('milk-shake', 'Musk Melon Milkshake', 80, 'Sweet muskmelon shake', 4);
SELECT _seed_menu_item('milk-shake', 'Papaya Milkshake', 80, 'Healthy papaya milkshake', 5);
SELECT _seed_menu_item('milk-shake', 'Chikku Milkshake', 90, 'Sweet sapota chikku milkshake', 6);
SELECT _seed_menu_item('milk-shake', 'Grape Milkshake', 80, 'Fresh grape milkshake', 7);
SELECT _seed_menu_item('milk-shake', 'Custard Apple Milkshake', 100, 'Seethaphal custard apple shake', 8);
SELECT _seed_menu_item('milk-shake', 'Butter Fruit Milkshake', 100, 'Rich avocado butter fruit shake', 9);
SELECT _seed_menu_item('milk-shake', 'Strawberry Milkshake', 100, 'Creamy strawberry thickshake', 10);
SELECT _seed_menu_item('milk-shake', 'Tender Milkshake', 100, 'Tender coconut pulp shake', 11);
SELECT _seed_menu_item('milk-shake', 'Tender Cashew Milkshake', 120, 'Tender coconut with roasted cashews', 12);
SELECT _seed_menu_item('milk-shake', 'Sharjah Shake', 100, 'Famous Malabar banana boost shake', 13);
SELECT _seed_menu_item('milk-shake', 'Kiwi Milkshake', 100, 'Tangy sweet green kiwi shake', 14);
SELECT _seed_menu_item('milk-shake', 'Dragon Fruit Milkshake', 100, 'Vibrant pink dragon fruit shake', 15);

-- 2.15 ICE CREAM SHAKE
SELECT _seed_menu_item('ice-cream-shake', 'Chocolate Ice Cream Shake', 90, 'Premium chocolate ice cream thickshake', 1);
SELECT _seed_menu_item('ice-cream-shake', 'Strawberry Ice Cream Shake', 80, 'Strawberry ice cream shake', 2);
SELECT _seed_menu_item('ice-cream-shake', 'Black Currant Shake', 80, 'Tangy black currant ice cream shake', 3);
SELECT _seed_menu_item('ice-cream-shake', 'Vanilla Ice Cream Shake', 80, 'Madagascar vanilla ice cream shake', 4);
SELECT _seed_menu_item('ice-cream-shake', 'Pista Shake', 80, 'Pistachio ice cream thickshake', 5);
SELECT _seed_menu_item('ice-cream-shake', 'Butterscotch Shake', 80, 'Crunchy butterscotch ice cream shake', 6);
SELECT _seed_menu_item('ice-cream-shake', 'Blueberry Shake', 80, 'Blueberry ice cream thickshake', 7);
SELECT _seed_menu_item('ice-cream-shake', 'Casatta Shake', 90, 'Multi-layered casatta ice cream shake', 8);
SELECT _seed_menu_item('ice-cream-shake', 'Mango Ice Cream Shake', 80, 'Mango ice cream thickshake', 9);

-- 2.16 CHOCOLATE SHAKE
SELECT _seed_menu_item('chocolate-shake', 'Snickers Shake', 100, 'Snickers bars blended with chocolate', 1);
SELECT _seed_menu_item('chocolate-shake', 'Dairy Milk Shake', 100, 'Cadbury dairy milk thickshake', 2);
SELECT _seed_menu_item('chocolate-shake', 'Kit Kat Shake', 100, 'Crispy kit kat wafer blended shake', 3);
SELECT _seed_menu_item('chocolate-shake', 'Five Star Shake', 100, 'Caramel 5-star chocolate shake', 4);
SELECT _seed_menu_item('chocolate-shake', 'Galaxy Shake', 100, 'Silky smooth galaxy chocolate shake', 5);
SELECT _seed_menu_item('chocolate-shake', 'Munch Shake', 100, 'Crunchy munch chocolate shake', 6);
SELECT _seed_menu_item('chocolate-shake', 'Brownie Shake', 120, 'Fudge chocolate brownie thickshake', 7);

-- 2.17 COLD ITEMS
SELECT _seed_menu_item('cold-items', 'Cold Coffee', 70, 'Classic chilled brewed coffee', 1);
SELECT _seed_menu_item('cold-items', 'Cold Boost', 70, 'Chilled malted boost energy drink', 2);
SELECT _seed_menu_item('cold-items', 'Cold Horlicks', 70, 'Chilled creamy malt horlicks', 3);

-- 2.18 FALOODA
SELECT _seed_menu_item('falooda', 'Fruit Salad', 80, 'Fresh seasonal cut fruits', 1);
SELECT _seed_menu_item('falooda', 'Fruit Salad + Ice Cream', 100, 'Fruit salad topped with vanilla ice cream', 2);
SELECT _seed_menu_item('falooda', 'Royal Falooda', 120, 'Rose syrup, vermicelli, sabja & ice cream', 3);
SELECT _seed_menu_item('falooda', 'Arabian Falooda', 140, 'Dates, nuts, rich cream & dry fruits', 4);

-- 2.19 MALBA
SELECT _seed_menu_item('malba', 'Chikku Malba', 120, 'Thick sapota pulp with cream & ice cream', 1);
SELECT _seed_menu_item('malba', 'Mango Malba', 120, 'Sweet mango chunks with ice cream sundae', 2);
SELECT _seed_menu_item('malba', 'Strawberry Malba', 120, 'Fresh strawberries with cream & scoop', 3);
SELECT _seed_menu_item('malba', 'Tender Malba', 120, 'Tender coconut special malba sundae', 4);

-- 2.20 MOJITO
SELECT _seed_menu_item('mojito', 'Blue Mojito', 90, 'Blue curacao, lemon, mint & sparkling soda', 1);
SELECT _seed_menu_item('mojito', 'Mint Mojito', 90, 'Classic virgin mint mojito', 2);
SELECT _seed_menu_item('mojito', 'Water Melon Mojito', 90, 'Muddled watermelon & mint mojito', 3);
SELECT _seed_menu_item('mojito', 'Strawberry Mojito', 90, 'Fresh strawberry & mint fizz', 4);
SELECT _seed_menu_item('mojito', 'Pineapple Mojito', 90, 'Tropical pineapple & mint cooler', 5);
SELECT _seed_menu_item('mojito', 'Green Apple Mojito', 90, 'Crisp green apple tangy mojito', 6);
SELECT _seed_menu_item('mojito', 'Passion Fruit Mojito', 90, 'Exotic passion fruit sparkling mojito', 7);
SELECT _seed_menu_item('mojito', 'Red Chilli Mojito', 90, 'Spicy sweet red chilli cooler', 8);

-- 2.21 HEALTHY
SELECT _seed_menu_item('healthy', 'ABC', 90, 'Apple, Beetroot & Carrot immunity boost', 1);
SELECT _seed_menu_item('healthy', 'Dry Fruit', 120, 'Almonds, cashews, figs & dates power shake', 2);
SELECT _seed_menu_item('healthy', 'OCG', 100, 'Orange, Carrot & Ginger detox juice', 3);
SELECT _seed_menu_item('healthy', 'Skin Glow', 100, 'Beetroot, Apple & Ginger radiance juice', 4);
SELECT _seed_menu_item('healthy', 'AG', 80, 'Amla & Ginger metabolism booster', 5);

-- 2.22 MOMOS
SELECT _seed_menu_item('momos', 'Fried Momos (Veg)', 90, 'Crispy fried vegetable momos (6 pcs)', 1);
SELECT _seed_menu_item('momos', 'Fried Momos (Chicken)', 100, 'Crispy fried chicken momos (6 pcs)', 2);
SELECT _seed_menu_item('momos', 'Peri Peri Momos (Veg)', 100, 'Peri peri dusted veg momos', 3);
SELECT _seed_menu_item('momos', 'Peri Peri Momos (Chicken)', 110, 'Peri peri dusted chicken momos', 4);
SELECT _seed_menu_item('momos', 'Schezwan Momos (Veg)', 110, 'Tossed in hot Schezwan sauce', 5);
SELECT _seed_menu_item('momos', 'Schezwan Momos (Chicken)', 120, 'Tossed in hot Schezwan sauce', 6);
SELECT _seed_menu_item('momos', 'Dynamic Momos (Veg)', 110, 'Glazed in dynamic signature sauce', 7);
SELECT _seed_menu_item('momos', 'Dynamic Momos (Chicken)', 120, 'Glazed in dynamic signature sauce', 8);
SELECT _seed_menu_item('momos', 'Lemon Pepper Momos (Veg)', 110, 'Zesty lemon pepper tossed veg momos', 9);
SELECT _seed_menu_item('momos', 'Lemon Pepper Momos (Chicken)', 120, 'Zesty lemon pepper chicken momos', 10);
SELECT _seed_menu_item('momos', 'Malai Momos (Veg)', 120, 'Creamy rich malai tossed veg momos', 11);
SELECT _seed_menu_item('momos', 'Malai Momos (Chicken)', 130, 'Creamy rich malai chicken momos', 12);
SELECT _seed_menu_item('momos', 'Honey Chilly Momos (Veg)', 120, 'Sweet & spicy honey chilly veg momos', 13);
SELECT _seed_menu_item('momos', 'Honey Chilly Momos (Chicken)', 130, 'Sweet & spicy honey chilly chicken momos', 14);

-- Clean up helper
DROP FUNCTION IF EXISTS _seed_menu_item(TEXT, TEXT, NUMERIC, TEXT, INT);
