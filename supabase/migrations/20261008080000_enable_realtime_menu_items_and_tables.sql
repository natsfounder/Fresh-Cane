-- ============================================================================
-- Migration: 20261008080000_enable_realtime_menu_items_and_tables.sql
-- Description: Adds menu_items and restaurant_tables to supabase_realtime publication
--              so changes (e.g. out-of-stock toggle, table active toggle) broadcast
--              instantly to all cashier and server devices.
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'menu_items'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.menu_items;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'restaurant_tables'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.restaurant_tables;
    END IF;
END $$;

ALTER TABLE public.menu_items REPLICA IDENTITY FULL;
ALTER TABLE public.restaurant_tables REPLICA IDENTITY FULL;
