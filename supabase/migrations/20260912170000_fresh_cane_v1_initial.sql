-- =============================================================================
-- FRESH CANE V1 — INITIAL PRODUCTION MIGRATION
-- =============================================================================
-- Architecture: Fresh Cane Database Architecture V2.2.3
-- Target: PostgreSQL 17 (Supabase Managed)
-- Application: Fresh Cane Café POS & Billing System
-- Organization: Noor Al Tech Solutions (NATS)
-- Generated: 2026-09-12
-- =============================================================================
-- IMPORTANT: This migration does NOT execute destructive operations on
-- existing Supabase-managed objects. It creates Fresh Cane application
-- objects only.
-- =============================================================================

-- *****************************************************************************
-- SECTION 1: EXTENSIONS
-- *****************************************************************************
-- pgcrypto is required for gen_random_bytes() used in order number generation.
-- On Supabase, pgcrypto is typically pre-installed. This is a safe no-op if
-- already enabled.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- *****************************************************************************
-- SECTION 2: TABLES (dependency order)
-- *****************************************************************************

-- ---------------------------------------------------------------------------
-- 2.1 user_profiles — Staff roles, linked 1:1 to auth.users
-- ---------------------------------------------------------------------------
CREATE TABLE public.user_profiles (
    id              UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name       VARCHAR(100) NOT NULL,
    phone           VARCHAR(20)  NULL,
    role            VARCHAR(20)  NOT NULL DEFAULT 'server',
    is_active       BOOLEAN      NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_user_profiles_role CHECK (role IN ('super_admin', 'cashier', 'server'))
);

CREATE INDEX idx_user_profiles_role ON public.user_profiles (role);
CREATE INDEX idx_user_profiles_active ON public.user_profiles (is_active);

-- ---------------------------------------------------------------------------
-- 2.2 store_settings — Singleton café configuration
-- ---------------------------------------------------------------------------
CREATE TABLE public.store_settings (
    id                              UUID          PRIMARY KEY DEFAULT '00000000-0000-0000-0000-000000000001'::uuid,
    store_name                      VARCHAR(100)  NOT NULL DEFAULT 'Fresh Cane',
    tagline                         VARCHAR(150)  NULL DEFAULT 'Pure & Natural Sugarcane Juice',
    address                         TEXT          NULL,
    phone                           VARCHAR(20)   NULL,
    email                           VARCHAR(100)  NULL,
    gstin                           VARCHAR(30)   NULL,
    tax_rate_percentage             NUMERIC(5,2)  NOT NULL DEFAULT 0.00,
    is_tax_inclusive                 BOOLEAN       NOT NULL DEFAULT true,
    currency_code                   VARCHAR(10)   NOT NULL DEFAULT 'INR',
    currency_symbol                 VARCHAR(5)    NOT NULL DEFAULT '₹',
    receipt_header                  TEXT          NULL,
    receipt_footer                  TEXT          NULL DEFAULT 'Thank you for visiting Fresh Cane!',
    bill_prefix                     VARCHAR(10)   NOT NULL DEFAULT 'FC-',
    order_prefix                    VARCHAR(10)   NOT NULL DEFAULT 'ORD-',
    max_cashier_discount_percentage NUMERIC(5,2)  NOT NULL DEFAULT 10.00,
    max_cashier_discount_amount     NUMERIC(10,2) NOT NULL DEFAULT 100.00,
    updated_by                      UUID          NULL REFERENCES public.user_profiles(id),
    updated_at                      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT chk_store_settings_singleton   CHECK (id = '00000000-0000-0000-0000-000000000001'::uuid),
    CONSTRAINT chk_store_settings_tax_rate    CHECK (tax_rate_percentage >= 0 AND tax_rate_percentage <= 100),
    CONSTRAINT chk_store_settings_disc_pct    CHECK (max_cashier_discount_percentage >= 0 AND max_cashier_discount_percentage <= 100),
    CONSTRAINT chk_store_settings_disc_amt    CHECK (max_cashier_discount_amount >= 0)
);

-- ---------------------------------------------------------------------------
-- 2.3 categories — Menu categories
-- ---------------------------------------------------------------------------
CREATE TABLE public.categories (
    id            UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    name          VARCHAR(100)  NOT NULL UNIQUE,
    slug          VARCHAR(100)  NOT NULL UNIQUE,
    display_order INTEGER       NOT NULL DEFAULT 0,
    is_active     BOOLEAN       NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX idx_categories_active_order ON public.categories (is_active, display_order);

-- ---------------------------------------------------------------------------
-- 2.4 menu_items — Products with pricing
-- ---------------------------------------------------------------------------
CREATE TABLE public.menu_items (
    id            UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id   UUID          NOT NULL REFERENCES public.categories(id) ON DELETE RESTRICT,
    name          VARCHAR(150)  NOT NULL,
    description   TEXT          NULL,
    base_price    NUMERIC(10,2) NOT NULL,
    is_available  BOOLEAN       NOT NULL DEFAULT true,
    is_active     BOOLEAN       NOT NULL DEFAULT true,
    display_order INTEGER       NOT NULL DEFAULT 0,
    image_url     TEXT          NULL,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT chk_menu_items_price CHECK (base_price >= 0)
);

CREATE INDEX idx_menu_items_category ON public.menu_items (category_id, display_order);
CREATE INDEX idx_menu_items_available ON public.menu_items (is_available) WHERE is_active = true;

-- ---------------------------------------------------------------------------
-- 2.5 restaurant_tables — Physical dining tables
-- ---------------------------------------------------------------------------
CREATE TABLE public.restaurant_tables (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    table_number     VARCHAR(20)  NOT NULL UNIQUE,
    seating_capacity INTEGER      NOT NULL DEFAULT 4,
    status           VARCHAR(20)  NOT NULL DEFAULT 'available',
    is_active        BOOLEAN      NOT NULL DEFAULT true,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_tables_status   CHECK (status IN ('available', 'occupied')),
    CONSTRAINT chk_tables_capacity CHECK (seating_capacity > 0)
);

CREATE INDEX idx_tables_status ON public.restaurant_tables (status) WHERE is_active = true;

-- ---------------------------------------------------------------------------
-- 2.6 customers — Canonical customer registry (phone-required)
-- ---------------------------------------------------------------------------
CREATE TABLE public.customers (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    phone      VARCHAR(10)  NOT NULL UNIQUE,
    name       VARCHAR(100) NULL,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_customers_phone CHECK (phone ~ '^[6-9][0-9]{9}$')
);

CREATE INDEX idx_customers_phone ON public.customers (phone);

-- ---------------------------------------------------------------------------
-- 2.7 orders — Transaction header
-- ---------------------------------------------------------------------------
CREATE TABLE public.orders (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    order_number   VARCHAR(35)  NOT NULL UNIQUE,
    order_type     VARCHAR(20)  NOT NULL,
    table_id       UUID         NULL REFERENCES public.restaurant_tables(id) ON DELETE RESTRICT,
    customer_id    UUID         NULL REFERENCES public.customers(id) ON DELETE SET NULL,
    customer_name  VARCHAR(100) NULL,
    customer_phone VARCHAR(10)  NULL,
    server_id      UUID         NOT NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
    status         VARCHAR(20)  NOT NULL DEFAULT 'open',
    notes          TEXT         NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_orders_type   CHECK (order_type IN ('dine_in', 'takeaway')),
    CONSTRAINT chk_orders_status CHECK (status IN ('open', 'served', 'completed', 'cancelled')),
    CONSTRAINT chk_orders_dine_in_table CHECK (
        (order_type = 'dine_in' AND table_id IS NOT NULL) OR (order_type = 'takeaway')
    ),
    CONSTRAINT chk_orders_customer_phone CHECK (
        customer_phone IS NULL OR customer_phone ~ '^[6-9][0-9]{9}$'
    )
);

-- Partial unique index: prevents multiple active dine-in orders on same table
CREATE UNIQUE INDEX idx_unique_active_dine_in_table
    ON public.orders (table_id)
    WHERE order_type = 'dine_in' AND status IN ('open', 'served');

CREATE INDEX idx_orders_status_created ON public.orders (status, created_at DESC);
CREATE INDEX idx_orders_server ON public.orders (server_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 2.8 order_items — Line items with immutable snapshots
-- ---------------------------------------------------------------------------
CREATE TABLE public.order_items (
    id                     UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id               UUID          NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    menu_item_id           UUID          NOT NULL REFERENCES public.menu_items(id) ON DELETE RESTRICT,
    item_name_snapshot     VARCHAR(150)  NOT NULL,
    category_name_snapshot VARCHAR(100)  NOT NULL,
    unit_price_snapshot    NUMERIC(10,2) NOT NULL,
    quantity               INTEGER       NOT NULL DEFAULT 1,
    item_total             NUMERIC(10,2) GENERATED ALWAYS AS (quantity * unit_price_snapshot) STORED,
    special_instructions   VARCHAR(200)  NULL,
    status                 VARCHAR(20)   NOT NULL DEFAULT 'ordered',
    created_at             TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT chk_order_items_quantity CHECK (quantity > 0),
    CONSTRAINT chk_order_items_price    CHECK (unit_price_snapshot >= 0),
    CONSTRAINT chk_order_items_status   CHECK (status IN ('ordered', 'served', 'cancelled'))
);

CREATE INDEX idx_order_items_order ON public.order_items (order_id);
CREATE INDEX idx_order_items_menu_item ON public.order_items (menu_item_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 2.9 bills — Tax invoice and financial settlement
-- ---------------------------------------------------------------------------
CREATE TABLE public.bills (
    id                       UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    bill_number              VARCHAR(50)   NOT NULL UNIQUE,
    order_id                 UUID          NOT NULL UNIQUE REFERENCES public.orders(id) ON DELETE RESTRICT,
    cashier_id               UUID          NOT NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
    settled_by               UUID          NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
    business_date            DATE          NOT NULL,
    subtotal_amount          NUMERIC(10,2) NOT NULL,
    discount_type            VARCHAR(20)   NULL,
    discount_rate            NUMERIC(5,2)  NOT NULL DEFAULT 0.00,
    discount_amount          NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    discount_reason          VARCHAR(150)  NULL,
    tax_rate_snapshot        NUMERIC(5,2)  NOT NULL DEFAULT 0.00,
    is_tax_inclusive_snapshot BOOLEAN       NOT NULL,
    tax_amount               NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    round_off_amount         NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    final_amount             NUMERIC(10,2) NOT NULL,
    store_name_snapshot      VARCHAR(100)  NOT NULL,
    store_address_snapshot   TEXT          NULL,
    store_gstin_snapshot     VARCHAR(30)   NULL,
    customer_name_snapshot   VARCHAR(100)  NULL,
    customer_phone_snapshot  VARCHAR(10)   NULL,
    status                   VARCHAR(20)   NOT NULL DEFAULT 'unpaid',
    void_reason              TEXT          NULL,
    voided_by                UUID          NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
    voided_at                TIMESTAMPTZ   NULL,
    created_at               TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at               TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT chk_bills_subtotal      CHECK (subtotal_amount >= 0),
    CONSTRAINT chk_bills_disc_rate     CHECK (discount_rate >= 0 AND discount_rate <= 100),
    CONSTRAINT chk_bills_disc_amt      CHECK (discount_amount >= 0 AND discount_amount <= subtotal_amount),
    CONSTRAINT chk_bills_disc_reason   CHECK (
        discount_amount = 0 OR (discount_amount > 0 AND discount_reason IS NOT NULL AND length(trim(discount_reason)) >= 3)
    ),
    CONSTRAINT chk_bills_disc_type     CHECK (discount_type IS NULL OR discount_type IN ('percentage', 'flat')),
    CONSTRAINT chk_bills_tax           CHECK (tax_amount >= 0),
    CONSTRAINT chk_bills_final         CHECK (final_amount >= 0),
    CONSTRAINT chk_bills_status        CHECK (status IN ('unpaid', 'paid', 'voided')),
    CONSTRAINT chk_bills_void_fields   CHECK (
        (status = 'voided' AND void_reason IS NOT NULL AND voided_by IS NOT NULL AND voided_at IS NOT NULL)
        OR (status <> 'voided')
    ),
    CONSTRAINT chk_bills_settled_by    CHECK (
        (status = 'paid' AND settled_by IS NOT NULL) OR (status <> 'paid')
    )
);

CREATE INDEX idx_bills_business_date ON public.bills (business_date, status);
CREATE INDEX idx_bills_status ON public.bills (status, created_at DESC);
CREATE INDEX idx_bills_bill_number ON public.bills (bill_number);

-- ---------------------------------------------------------------------------
-- 2.10 payments — Multi-tender payment ledger
-- ---------------------------------------------------------------------------
CREATE TABLE public.payments (
    id                    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    bill_id               UUID          NOT NULL REFERENCES public.bills(id) ON DELETE RESTRICT,
    payment_method        VARCHAR(20)   NOT NULL,
    amount                NUMERIC(10,2) NOT NULL,
    transaction_reference VARCHAR(100)  NULL,
    cash_tendered         NUMERIC(10,2) NULL,
    change_returned       NUMERIC(10,2) NULL,
    received_by           UUID          NOT NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
    status                VARCHAR(20)   NOT NULL DEFAULT 'completed',
    refunded_at           TIMESTAMPTZ   NULL,
    refunded_by           UUID          NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
    refund_reason         TEXT          NULL,
    created_at            TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT chk_payments_amount  CHECK (amount > 0),
    CONSTRAINT chk_payments_method  CHECK (payment_method IN ('cash', 'upi', 'card')),
    CONSTRAINT chk_payments_status  CHECK (status IN ('completed', 'refunded')),
    CONSTRAINT chk_payments_cash    CHECK (
        (payment_method = 'cash' AND cash_tendered IS NOT NULL AND cash_tendered >= amount
         AND change_returned IS NOT NULL AND change_returned = (cash_tendered - amount))
        OR (payment_method <> 'cash' AND cash_tendered IS NULL AND change_returned IS NULL)
    ),
    CONSTRAINT chk_payments_refund  CHECK (
        (status = 'refunded' AND refunded_at IS NOT NULL AND refunded_by IS NOT NULL AND refund_reason IS NOT NULL)
        OR (status = 'completed')
    )
);

CREATE INDEX idx_payments_bill ON public.payments (bill_id);
CREATE INDEX idx_payments_method ON public.payments (payment_method, created_at DESC);
CREATE INDEX idx_payments_received_by ON public.payments (received_by, created_at DESC);

-- ---------------------------------------------------------------------------
-- 2.11 bill_sequences — Atomic daily bill number counter
-- ---------------------------------------------------------------------------
CREATE TABLE public.bill_sequences (
    sequence_date DATE        PRIMARY KEY,
    last_number   INTEGER     NOT NULL DEFAULT 0,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 2.12 audit_logs — Append-only audit trail
-- ---------------------------------------------------------------------------
CREATE TABLE public.audit_logs (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID         NULL REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    action      VARCHAR(50)  NOT NULL,
    entity_type VARCHAR(50)  NOT NULL,
    entity_id   VARCHAR(50)  NOT NULL,
    old_data    JSONB        NULL,
    new_data    JSONB        NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_logs_entity ON public.audit_logs (entity_type, entity_id, created_at DESC);
CREATE INDEX idx_audit_logs_user ON public.audit_logs (user_id, created_at DESC);


-- *****************************************************************************
-- SECTION 3: INTERNAL HELPER FUNCTIONS
-- *****************************************************************************

-- ---------------------------------------------------------------------------
-- 3.1 RLS Security Helpers (EXECUTE granted to authenticated)
-- ---------------------------------------------------------------------------

-- is_staff: returns true if caller is any active staff member
CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE id = auth.uid() AND is_active = true
    );
$$;

-- is_super_admin: returns true if caller is active super_admin
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE id = auth.uid() AND is_active = true AND role = 'super_admin'
    );
$$;

-- is_cashier_or_admin: returns true if caller is active cashier or super_admin
CREATE OR REPLACE FUNCTION public.is_cashier_or_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE id = auth.uid() AND is_active = true AND role IN ('cashier', 'super_admin')
    );
$$;

-- ---------------------------------------------------------------------------
-- 3.2 Internal Implementation Helpers (EXECUTE revoked from clients)
-- ---------------------------------------------------------------------------

-- get_current_user_role: returns verified active role for auth.uid()
CREATE OR REPLACE FUNCTION public.get_current_user_role()
RETURNS VARCHAR(20)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_role VARCHAR(20);
BEGIN
    SELECT role INTO v_role
    FROM public.user_profiles
    WHERE id = auth.uid() AND is_active = true;

    IF v_role IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: caller is not an active staff member';
    END IF;

    RETURN v_role;
END;
$$;

-- normalize_indian_phone: validates and normalizes Indian mobile numbers
CREATE OR REPLACE FUNCTION public.normalize_indian_phone(p_raw TEXT)
RETURNS VARCHAR(10)
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_digits TEXT;
BEGIN
    -- Strip all non-digit characters
    v_digits := regexp_replace(p_raw, '\D', '', 'g');

    -- 12 digits starting with 91 → strip country code
    IF length(v_digits) = 12 AND v_digits LIKE '91%' THEN
        v_digits := substring(v_digits FROM 3);
    END IF;

    -- 11 digits starting with 0 → strip trunk prefix
    IF length(v_digits) = 11 AND v_digits LIKE '0%' THEN
        v_digits := substring(v_digits FROM 2);
    END IF;

    -- Must be exactly 10 digits starting with 6-9
    IF length(v_digits) <> 10 OR v_digits !~ '^[6-9][0-9]{9}$' THEN
        RAISE EXCEPTION 'Invalid Indian mobile number: %', p_raw;
    END IF;

    RETURN v_digits::VARCHAR(10);
END;
$$;

-- generate_order_number: crypto-random order number with collision retry
CREATE OR REPLACE FUNCTION public.generate_order_number(p_prefix VARCHAR DEFAULT 'ORD-')
RETURNS VARCHAR(35)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_date_part TEXT;
    v_random_part TEXT;
    v_order_number VARCHAR(35);
    v_attempt INTEGER := 0;
    v_max_attempts CONSTANT INTEGER := 3;
BEGIN
    v_date_part := to_char(now() AT TIME ZONE 'Asia/Kolkata', 'YYYYMMDD');

    LOOP
        v_attempt := v_attempt + 1;
        v_random_part := encode(gen_random_bytes(2), 'hex');
        v_order_number := p_prefix || v_date_part || '-' || v_random_part;

        -- Check if this number already exists
        IF NOT EXISTS (SELECT 1 FROM public.orders WHERE order_number = v_order_number) THEN
            RETURN v_order_number;
        END IF;

        IF v_attempt >= v_max_attempts THEN
            RAISE EXCEPTION 'Failed to generate unique order number after % attempts', v_max_attempts;
        END IF;
    END LOOP;
END;
$$;

-- get_next_bill_number: atomic daily sequential bill number allocation
CREATE OR REPLACE FUNCTION public.get_next_bill_number(p_prefix VARCHAR DEFAULT 'FC-')
RETURNS VARCHAR(50)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_business_date DATE;
    v_next_number INTEGER;
    v_date_part TEXT;
BEGIN
    v_business_date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
    v_date_part := to_char(v_business_date, 'YYYYMMDD');

    -- Atomic upsert: INSERT new date row or INCREMENT existing
    INSERT INTO public.bill_sequences (sequence_date, last_number, updated_at)
    VALUES (v_business_date, 1, now())
    ON CONFLICT (sequence_date)
    DO UPDATE SET
        last_number = public.bill_sequences.last_number + 1,
        updated_at = now()
    RETURNING last_number INTO v_next_number;

    RETURN p_prefix || v_date_part || '-' || lpad(v_next_number::text, 4, '0');
END;
$$;


-- *****************************************************************************
-- SECTION 4: AUDIT TRIGGER FUNCTIONS
-- *****************************************************************************

-- Trigger: audit user_profiles changes (role/active status via direct updates from RPCs)
CREATE OR REPLACE FUNCTION public.trg_audit_user_profiles()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- Audit role changes
    IF OLD.role IS DISTINCT FROM NEW.role THEN
        INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, old_data, new_data)
        VALUES (
            auth.uid(),
            'USER_ROLE_CHANGED',
            'user_profile',
            NEW.id::text,
            jsonb_build_object('role', OLD.role),
            jsonb_build_object('role', NEW.role, 'target_user_id', NEW.id)
        );
    END IF;

    -- Audit active status changes
    IF OLD.is_active IS DISTINCT FROM NEW.is_active THEN
        INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, old_data, new_data)
        VALUES (
            auth.uid(),
            'USER_STATUS_CHANGED',
            'user_profile',
            NEW.id::text,
            jsonb_build_object('is_active', OLD.is_active),
            jsonb_build_object('is_active', NEW.is_active, 'target_user_id', NEW.id)
        );
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_user_profiles_audit
    AFTER UPDATE ON public.user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_audit_user_profiles();

-- Trigger: audit store_settings changes
CREATE OR REPLACE FUNCTION public.trg_audit_store_settings()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, old_data, new_data)
    VALUES (
        auth.uid(),
        'SETTINGS_UPDATED',
        'store_setting',
        NEW.id::text,
        jsonb_build_object(
            'store_name', OLD.store_name,
            'tax_rate_percentage', OLD.tax_rate_percentage,
            'is_tax_inclusive', OLD.is_tax_inclusive,
            'max_cashier_discount_percentage', OLD.max_cashier_discount_percentage,
            'max_cashier_discount_amount', OLD.max_cashier_discount_amount
        ),
        jsonb_build_object(
            'store_name', NEW.store_name,
            'tax_rate_percentage', NEW.tax_rate_percentage,
            'is_tax_inclusive', NEW.is_tax_inclusive,
            'max_cashier_discount_percentage', NEW.max_cashier_discount_percentage,
            'max_cashier_discount_amount', NEW.max_cashier_discount_amount
        )
    );
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_store_settings_audit
    AFTER UPDATE ON public.store_settings
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_audit_store_settings();

-- Trigger: audit menu_items price changes
CREATE OR REPLACE FUNCTION public.trg_audit_menu_items()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF OLD.base_price IS DISTINCT FROM NEW.base_price THEN
        INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, old_data, new_data)
        VALUES (
            auth.uid(),
            'MENU_ITEM_PRICE_CHANGED',
            'menu_item',
            NEW.id::text,
            jsonb_build_object('base_price', OLD.base_price),
            jsonb_build_object('base_price', NEW.base_price)
        );
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_menu_items_audit
    AFTER UPDATE ON public.menu_items
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_audit_menu_items();

-- Updated_at auto-update trigger (reusable)
CREATE OR REPLACE FUNCTION public.trg_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

-- Apply updated_at triggers to all tables with updated_at column
CREATE TRIGGER trg_user_profiles_updated_at BEFORE UPDATE ON public.user_profiles
    FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();
CREATE TRIGGER trg_categories_updated_at BEFORE UPDATE ON public.categories
    FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();
CREATE TRIGGER trg_menu_items_updated_at BEFORE UPDATE ON public.menu_items
    FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();
CREATE TRIGGER trg_restaurant_tables_updated_at BEFORE UPDATE ON public.restaurant_tables
    FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();
CREATE TRIGGER trg_customers_updated_at BEFORE UPDATE ON public.customers
    FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();
CREATE TRIGGER trg_orders_updated_at BEFORE UPDATE ON public.orders
    FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();
CREATE TRIGGER trg_order_items_updated_at BEFORE UPDATE ON public.order_items
    FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();
CREATE TRIGGER trg_bills_updated_at BEFORE UPDATE ON public.bills
    FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();


-- *****************************************************************************
-- SECTION 5: CLIENT-CALLABLE BUSINESS RPCs (19 Functions)
-- *****************************************************************************

-- =====================================================================
-- RPC 1: create_dine_in_order
-- =====================================================================
CREATE OR REPLACE FUNCTION public.create_dine_in_order(
    p_table_id UUID,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_table RECORD;
    v_order_number VARCHAR(35);
    v_order_id UUID;
    v_settings RECORD;
    v_attempt INTEGER;
BEGIN
    -- 1. Verify actor authorization
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: caller is not an active staff member';
    END IF;

    -- 2. Lock and verify table
    SELECT * INTO v_table FROM public.restaurant_tables
    WHERE id = p_table_id AND is_active = true FOR UPDATE;

    IF v_table IS NULL THEN
        RAISE EXCEPTION 'Table not found or inactive';
    END IF;

    IF v_table.status <> 'available' THEN
        RAISE EXCEPTION 'Table % is not available (current status: %)', v_table.table_number, v_table.status;
    END IF;

    -- 3. Get order prefix from settings
    SELECT order_prefix INTO v_settings FROM public.store_settings LIMIT 1;

    -- 4. Generate order number and insert with concurrency-safe collision retry (max 3 attempts)
    FOR v_attempt IN 1..3 LOOP
        v_order_number := public.generate_order_number(COALESCE(v_settings.order_prefix, 'ORD-'));
        BEGIN
            INSERT INTO public.orders (id, order_number, order_type, table_id, server_id, status, notes)
            VALUES (gen_random_uuid(), v_order_number, 'dine_in', p_table_id, v_actor, 'open', p_notes)
            RETURNING id INTO v_order_id;
            EXIT; -- Success, exit retry loop
        EXCEPTION WHEN unique_violation THEN
            IF v_attempt = 3 THEN
                RAISE EXCEPTION 'Failed to allocate unique order number after 3 attempts due to concurrent collisions';
            END IF;
            -- Concurrency collision detected: retry with newly generated order number
        END;
    END LOOP;

    -- 5. Mark table as occupied
    UPDATE public.restaurant_tables SET status = 'occupied' WHERE id = p_table_id;

    -- 6. Audit
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (v_actor, 'ORDER_CREATED', 'order', v_order_id::text,
        jsonb_build_object('order_number', v_order_number, 'order_type', 'dine_in', 'table_id', p_table_id));

    RETURN jsonb_build_object('order_id', v_order_id, 'order_number', v_order_number);
END;
$$;

-- =====================================================================
-- RPC 2: create_takeaway_order
-- =====================================================================
CREATE OR REPLACE FUNCTION public.create_takeaway_order(
    p_customer_name TEXT DEFAULT NULL,
    p_customer_phone TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_normalized_phone VARCHAR(10);
    v_customer_id UUID;
    v_order_number VARCHAR(35);
    v_order_id UUID;
    v_settings RECORD;
    v_attempt INTEGER;
BEGIN
    -- 1. Verify actor authorization
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: caller is not an active staff member';
    END IF;

    -- 2. Handle customer
    IF p_customer_phone IS NOT NULL AND trim(p_customer_phone) <> '' THEN
        -- Normalize phone
        v_normalized_phone := public.normalize_indian_phone(p_customer_phone);

        -- Upsert customer
        INSERT INTO public.customers (phone, name)
        VALUES (v_normalized_phone, p_customer_name)
        ON CONFLICT (phone) DO UPDATE SET
            name = COALESCE(EXCLUDED.name, public.customers.name),
            updated_at = now()
        RETURNING id INTO v_customer_id;
    END IF;

    -- 3. Get order prefix
    SELECT order_prefix INTO v_settings FROM public.store_settings LIMIT 1;

    -- 4. Generate order number and insert with concurrency-safe collision retry (max 3 attempts)
    FOR v_attempt IN 1..3 LOOP
        v_order_number := public.generate_order_number(COALESCE(v_settings.order_prefix, 'ORD-'));
        BEGIN
            INSERT INTO public.orders (
                id, order_number, order_type, customer_id, customer_name, customer_phone,
                server_id, status, notes
            )
            VALUES (
                gen_random_uuid(), v_order_number, 'takeaway', v_customer_id,
                p_customer_name, v_normalized_phone, v_actor, 'open', p_notes
            )
            RETURNING id INTO v_order_id;
            EXIT; -- Success, exit retry loop
        EXCEPTION WHEN unique_violation THEN
            IF v_attempt = 3 THEN
                RAISE EXCEPTION 'Failed to allocate unique order number after 3 attempts due to concurrent collisions';
            END IF;
            -- Concurrency collision detected: retry with newly generated order number
        END;
    END LOOP;

    -- 5. Audit
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (v_actor, 'ORDER_CREATED', 'order', v_order_id::text,
        jsonb_build_object('order_number', v_order_number, 'order_type', 'takeaway',
            'customer_name', p_customer_name, 'customer_phone', v_normalized_phone));

    RETURN jsonb_build_object('order_id', v_order_id, 'order_number', v_order_number);
END;
$$;

-- =====================================================================
-- RPC 3: add_order_item
-- =====================================================================
CREATE OR REPLACE FUNCTION public.add_order_item(
    p_order_id UUID,
    p_menu_item_id UUID,
    p_quantity INTEGER DEFAULT 1,
    p_special_instructions VARCHAR DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_order RECORD;
    v_menu_item RECORD;
    v_category RECORD;
    v_order_item_id UUID;
BEGIN
    -- 1. Verify actor
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: caller is not an active staff member';
    END IF;

    -- 2. Validate quantity
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Quantity must be positive';
    END IF;

    -- 3. Lock parent order
    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order not found';
    END IF;

    -- 4. Verify order is editable (no bill exists)
    IF v_order.status NOT IN ('open', 'served') THEN
        RAISE EXCEPTION 'Order is not editable (status: %)', v_order.status;
    END IF;
    IF EXISTS (SELECT 1 FROM public.bills WHERE order_id = p_order_id) THEN
        RAISE EXCEPTION 'Order is sealed — a bill already exists';
    END IF;

    -- 5. Verify menu item availability
    SELECT * INTO v_menu_item FROM public.menu_items WHERE id = p_menu_item_id AND is_active = true;
    IF v_menu_item IS NULL THEN
        RAISE EXCEPTION 'Menu item not found or inactive';
    END IF;
    IF NOT v_menu_item.is_available THEN
        RAISE EXCEPTION 'Menu item "%" is currently unavailable', v_menu_item.name;
    END IF;

    -- 6. Get category name for snapshot
    SELECT name INTO v_category FROM public.categories WHERE id = v_menu_item.category_id;

    -- 7. Insert order item with immutable snapshots
    INSERT INTO public.order_items (
        order_id, menu_item_id, item_name_snapshot, category_name_snapshot,
        unit_price_snapshot, quantity, special_instructions, status
    )
    VALUES (
        p_order_id, p_menu_item_id, v_menu_item.name, v_category.name,
        v_menu_item.base_price, p_quantity, p_special_instructions, 'ordered'
    )
    RETURNING id INTO v_order_item_id;

    -- 8. If order was 'served', revert to 'open' (new item needs serving)
    IF v_order.status = 'served' THEN
        UPDATE public.orders SET status = 'open' WHERE id = p_order_id;
    END IF;

    -- 9. Audit
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (v_actor, 'ORDER_ITEM_ADDED', 'order_item', v_order_item_id::text,
        jsonb_build_object('order_id', p_order_id, 'menu_item_id', p_menu_item_id,
            'quantity', p_quantity, 'unit_price', v_menu_item.base_price));

    RETURN jsonb_build_object('order_item_id', v_order_item_id);
END;
$$;

-- =====================================================================
-- RPC 4: update_order_item_quantity
-- =====================================================================
CREATE OR REPLACE FUNCTION public.update_order_item_quantity(
    p_order_item_id UUID,
    p_new_quantity INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_item RECORD;
    v_order RECORD;
    v_old_quantity INTEGER;
BEGIN
    -- 1. Verify actor
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: caller is not an active staff member';
    END IF;

    -- 2. Validate new quantity
    IF p_new_quantity IS NULL OR p_new_quantity <= 0 THEN
        RAISE EXCEPTION 'Quantity must be positive';
    END IF;

    -- 3. Get item
    SELECT * INTO v_item FROM public.order_items WHERE id = p_order_item_id;
    IF v_item IS NULL THEN
        RAISE EXCEPTION 'Order item not found';
    END IF;

    -- 4. Lock parent order
    SELECT * INTO v_order FROM public.orders WHERE id = v_item.order_id FOR UPDATE;

    -- 5. Verify order is editable
    IF v_order.status NOT IN ('open', 'served') THEN
        RAISE EXCEPTION 'Order is not editable (status: %)', v_order.status;
    END IF;
    IF EXISTS (SELECT 1 FROM public.bills WHERE order_id = v_item.order_id) THEN
        RAISE EXCEPTION 'Order is sealed — a bill already exists';
    END IF;

    -- 6. Verify item is modifiable
    IF v_item.status = 'cancelled' THEN
        RAISE EXCEPTION 'Cannot modify a cancelled item';
    END IF;

    -- 7. Update quantity
    v_old_quantity := v_item.quantity;
    UPDATE public.order_items SET quantity = p_new_quantity WHERE id = p_order_item_id;

    -- 8. Audit
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, old_data, new_data)
    VALUES (v_actor, 'ORDER_ITEM_QUANTITY_CHANGED', 'order_item', p_order_item_id::text,
        jsonb_build_object('quantity', v_old_quantity),
        jsonb_build_object('quantity', p_new_quantity, 'order_id', v_item.order_id));

    RETURN jsonb_build_object('success', true, 'old_quantity', v_old_quantity, 'new_quantity', p_new_quantity);
END;
$$;

-- =====================================================================
-- RPC 5: cancel_order_item
-- =====================================================================
CREATE OR REPLACE FUNCTION public.cancel_order_item(
    p_order_item_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_item RECORD;
    v_order RECORD;
BEGIN
    -- 1. Verify actor
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: caller is not an active staff member';
    END IF;

    -- 2. Get item
    SELECT * INTO v_item FROM public.order_items WHERE id = p_order_item_id;
    IF v_item IS NULL THEN
        RAISE EXCEPTION 'Order item not found';
    END IF;

    -- 3. Lock parent order
    SELECT * INTO v_order FROM public.orders WHERE id = v_item.order_id FOR UPDATE;

    -- 4. Verify order is editable and has no bill
    IF v_order.status NOT IN ('open', 'served') THEN
        RAISE EXCEPTION 'Order is not editable (status: %)', v_order.status;
    END IF;
    IF EXISTS (SELECT 1 FROM public.bills WHERE order_id = v_item.order_id) THEN
        RAISE EXCEPTION 'Order is sealed — a bill already exists';
    END IF;

    -- 5. Verify item can be cancelled (ordered or served → cancelled)
    IF v_item.status = 'cancelled' THEN
        RAISE EXCEPTION 'Item is already cancelled';
    END IF;

    -- 6. Cancel item (soft cancel)
    UPDATE public.order_items SET status = 'cancelled' WHERE id = p_order_item_id;

    -- 7. Audit
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, old_data, new_data)
    VALUES (v_actor, 'ORDER_ITEM_CANCELLED', 'order_item', p_order_item_id::text,
        jsonb_build_object('status', v_item.status, 'item_name', v_item.item_name_snapshot),
        jsonb_build_object('cancel_reason', p_reason, 'order_id', v_item.order_id));

    RETURN jsonb_build_object('success', true);
END;
$$;

-- =====================================================================
-- RPC 6: transfer_table
-- =====================================================================
CREATE OR REPLACE FUNCTION public.transfer_table(
    p_order_id UUID,
    p_new_table_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_order RECORD;
    v_old_table_id UUID;
    v_tables RECORD;
BEGIN
    -- 1. Verify actor
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: caller is not an active staff member';
    END IF;

    -- 2. Lock parent order first
    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order not found';
    END IF;

    -- 3. Verify order is active dine-in with no bill
    IF v_order.order_type <> 'dine_in' THEN
        RAISE EXCEPTION 'Only dine-in orders can transfer tables';
    END IF;
    IF v_order.status NOT IN ('open', 'served') THEN
        RAISE EXCEPTION 'Order is not active (status: %)', v_order.status;
    END IF;
    IF EXISTS (SELECT 1 FROM public.bills WHERE order_id = p_order_id) THEN
        RAISE EXCEPTION 'Order is sealed — a bill already exists';
    END IF;

    v_old_table_id := v_order.table_id;

    IF v_old_table_id = p_new_table_id THEN
        RAISE EXCEPTION 'Source and destination tables are the same';
    END IF;

    -- 4. Lock source and destination tables in ascending UUID order to prevent deadlocks
    PERFORM 1 FROM public.restaurant_tables
    WHERE id IN (v_old_table_id, p_new_table_id) AND is_active = true
    ORDER BY id FOR UPDATE;

    -- 5. Verify destination table is available
    IF NOT EXISTS (
        SELECT 1 FROM public.restaurant_tables
        WHERE id = p_new_table_id AND is_active = true AND status = 'available'
    ) THEN
        RAISE EXCEPTION 'Destination table is not available';
    END IF;

    -- 6. Move order to new table
    UPDATE public.orders SET table_id = p_new_table_id WHERE id = p_order_id;

    -- 7. Release old table
    UPDATE public.restaurant_tables SET status = 'available' WHERE id = v_old_table_id;

    -- 8. Occupy new table
    UPDATE public.restaurant_tables SET status = 'occupied' WHERE id = p_new_table_id;

    -- 9. Audit
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, old_data, new_data)
    VALUES (v_actor, 'TABLE_TRANSFERRED', 'order', p_order_id::text,
        jsonb_build_object('old_table_id', v_old_table_id),
        jsonb_build_object('new_table_id', p_new_table_id));

    RETURN jsonb_build_object('success', true, 'old_table_id', v_old_table_id, 'new_table_id', p_new_table_id);
END;
$$;

-- =====================================================================
-- RPC 7: mark_order_served
-- =====================================================================
CREATE OR REPLACE FUNCTION public.mark_order_served(p_order_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_order RECORD;
    v_items_updated INTEGER;
BEGIN
    -- 1. Verify actor
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: caller is not an active staff member';
    END IF;

    -- 2. Lock parent order
    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order not found';
    END IF;

    -- 3. Verify order is in a servable state
    IF v_order.status NOT IN ('open', 'served') THEN
        RAISE EXCEPTION 'Order cannot be served (status: %)', v_order.status;
    END IF;

    -- 4. Mark only 'ordered' items as 'served' (leave served/cancelled items untouched)
    UPDATE public.order_items
    SET status = 'served'
    WHERE order_id = p_order_id AND status = 'ordered';

    GET DIAGNOSTICS v_items_updated = ROW_COUNT;

    -- 5. Verify at least one non-cancelled item exists
    IF NOT EXISTS (SELECT 1 FROM public.order_items WHERE order_id = p_order_id AND status <> 'cancelled') THEN
        RAISE EXCEPTION 'No active items to serve';
    END IF;

    -- 6. Set order status to 'served'
    UPDATE public.orders SET status = 'served' WHERE id = p_order_id;

    -- 7. Audit
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, old_data, new_data)
    VALUES (v_actor, 'ORDER_SERVED', 'order', p_order_id::text,
        jsonb_build_object('status', v_order.status),
        jsonb_build_object('status', 'served', 'items_marked_served', v_items_updated));

    RETURN jsonb_build_object('success', true, 'items_marked_served', v_items_updated);
END;
$$;

-- =====================================================================
-- RPC 8: cancel_order
-- =====================================================================
CREATE OR REPLACE FUNCTION public.cancel_order(
    p_order_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_order RECORD;
BEGIN
    -- 1. Verify actor — only cashier or super_admin can cancel orders
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL OR v_role NOT IN ('cashier', 'super_admin') THEN
        RAISE EXCEPTION 'Unauthorized: only cashier or super_admin can cancel orders';
    END IF;

    -- 2. Lock parent order
    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order not found';
    END IF;

    -- 3. Verify order can be cancelled (not terminal, no bill)
    IF v_order.status NOT IN ('open', 'served') THEN
        RAISE EXCEPTION 'Order cannot be cancelled (status: %)', v_order.status;
    END IF;
    IF EXISTS (SELECT 1 FROM public.bills WHERE order_id = p_order_id) THEN
        RAISE EXCEPTION 'Order has a bill — use void_bill() to cancel a billed order';
    END IF;

    -- 4. Cancel all non-cancelled items
    UPDATE public.order_items SET status = 'cancelled'
    WHERE order_id = p_order_id AND status <> 'cancelled';

    -- 5. Cancel order
    UPDATE public.orders SET status = 'cancelled' WHERE id = p_order_id;

    -- 6. Release table if dine-in
    IF v_order.order_type = 'dine_in' AND v_order.table_id IS NOT NULL THEN
        UPDATE public.restaurant_tables SET status = 'available'
        WHERE id = v_order.table_id;
    END IF;

    -- 7. Audit
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, old_data, new_data)
    VALUES (v_actor, 'ORDER_CANCELLED', 'order', p_order_id::text,
        jsonb_build_object('status', v_order.status, 'order_number', v_order.order_number),
        jsonb_build_object('cancel_reason', p_reason));

    RETURN jsonb_build_object('success', true);
END;
$$;

-- =====================================================================
-- RPC 9: generate_bill_for_order
-- =====================================================================
CREATE OR REPLACE FUNCTION public.generate_bill_for_order(
    p_order_id UUID,
    p_discount_type VARCHAR DEFAULT NULL,
    p_discount_value NUMERIC DEFAULT 0,
    p_discount_reason VARCHAR DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_order RECORD;
    v_settings RECORD;
    v_subtotal NUMERIC(10,2);
    v_discount_amount NUMERIC(10,2) := 0;
    v_discount_rate NUMERIC(5,2) := 0;
    v_discounted_subtotal NUMERIC(10,2);
    v_tax_amount NUMERIC(10,2) := 0;
    v_raw_total NUMERIC(10,2);
    v_final_amount NUMERIC(10,2);
    v_round_off NUMERIC(10,2);
    v_bill_number VARCHAR(50);
    v_bill_id UUID;
    v_business_date DATE;
BEGIN
    -- 1. Verify actor — cashier or super_admin only
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL OR v_role NOT IN ('cashier', 'super_admin') THEN
        RAISE EXCEPTION 'Unauthorized: only cashier or super_admin can generate bills';
    END IF;

    -- 2. Lock parent order
    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order not found';
    END IF;

    -- 3. Verify order is billable (must be in 'served' state)
    IF v_order.status <> 'served' THEN
        RAISE EXCEPTION 'Order is not billable: order status must be ''served'' before generating a bill (current status: %)', v_order.status;
    END IF;

    -- 4. Verify no existing bill
    IF EXISTS (SELECT 1 FROM public.bills WHERE order_id = p_order_id) THEN
        RAISE EXCEPTION 'A bill already exists for this order';
    END IF;

    -- 5. Verify at least one non-cancelled item
    IF NOT EXISTS (SELECT 1 FROM public.order_items WHERE order_id = p_order_id AND status <> 'cancelled') THEN
        RAISE EXCEPTION 'Order has no active items to bill';
    END IF;

    -- 6. Lock and read store settings
    SELECT * INTO v_settings FROM public.store_settings LIMIT 1 FOR SHARE;
    IF v_settings IS NULL THEN
        RAISE EXCEPTION 'Store settings not found';
    END IF;

    -- 7. Calculate subtotal from active items (server-side calculation)
    SELECT COALESCE(SUM(item_total), 0) INTO v_subtotal
    FROM public.order_items
    WHERE order_id = p_order_id AND status <> 'cancelled';

    -- 8. Apply discount rules
    IF p_discount_value < 0 THEN
        RAISE EXCEPTION 'Discount value cannot be negative: %', p_discount_value;
    END IF;

    IF p_discount_value > 0 THEN
        IF p_discount_type IS NULL THEN
            RAISE EXCEPTION 'Discount type is required when discount value is greater than 0';
        END IF;

        -- Validate discount type
        IF p_discount_type NOT IN ('percentage', 'flat') THEN
            RAISE EXCEPTION 'Invalid discount type: %. Must be percentage or flat', p_discount_type;
        END IF;

        -- Calculate discount amount
        IF p_discount_type = 'percentage' THEN
            v_discount_rate := p_discount_value;
            v_discount_amount := ROUND(v_subtotal * p_discount_value / 100, 2);
        ELSE -- flat
            v_discount_amount := ROUND(p_discount_value, 2);
            IF v_subtotal > 0 THEN
                v_discount_rate := ROUND(v_discount_amount / v_subtotal * 100, 2);
            END IF;
        END IF;

        -- Enforce cashier limits (super_admin bypasses caps)
        IF v_role = 'cashier' THEN
            IF p_discount_type = 'percentage' AND p_discount_value > v_settings.max_cashier_discount_percentage THEN
                RAISE EXCEPTION 'Cashier discount percentage (%) exceeds limit (%)',
                    p_discount_value, v_settings.max_cashier_discount_percentage;
            END IF;
            IF v_discount_amount > v_settings.max_cashier_discount_amount THEN
                RAISE EXCEPTION 'Cashier discount amount (₹%) exceeds limit (₹%)',
                    v_discount_amount, v_settings.max_cashier_discount_amount;
            END IF;
        END IF;

        -- Discount cannot exceed subtotal
        IF v_discount_amount > v_subtotal THEN
            v_discount_amount := v_subtotal;
        END IF;

        -- Validate discount reason
        IF p_discount_reason IS NULL OR length(trim(p_discount_reason)) < 3 THEN
            RAISE EXCEPTION 'Discount reason is required (minimum 3 characters)';
        END IF;
    ELSE
        -- p_discount_value is 0 or NULL: No discount applied
        p_discount_type := NULL;
        v_discount_rate := 0;
        v_discount_amount := 0;
    END IF;

    -- 9. Tax calculation
    v_discounted_subtotal := v_subtotal - v_discount_amount;

    IF v_settings.tax_rate_percentage > 0 THEN
        IF v_settings.is_tax_inclusive THEN
            -- Tax-inclusive: extract tax from the subtotal. DO NOT add it back.
            v_tax_amount := ROUND(
                v_discounted_subtotal - (v_discounted_subtotal / (1 + v_settings.tax_rate_percentage / 100)),
                2
            );
            v_raw_total := v_discounted_subtotal;
        ELSE
            -- Tax-exclusive: compute and add tax
            v_tax_amount := ROUND(v_discounted_subtotal * v_settings.tax_rate_percentage / 100, 2);
            v_raw_total := v_discounted_subtotal + v_tax_amount;
        END IF;
    ELSE
        v_tax_amount := 0;
        v_raw_total := v_discounted_subtotal;
    END IF;

    -- 10. Rounding: nearest integer rupee
    v_final_amount := ROUND(v_raw_total, 0);
    v_round_off := v_final_amount - v_raw_total;

    -- 11. Business date (Asia/Kolkata)
    v_business_date := (now() AT TIME ZONE 'Asia/Kolkata')::date;

    -- 12. Allocate bill number atomically
    v_bill_number := public.get_next_bill_number(v_settings.bill_prefix);

    -- 13. Create bill with immutable snapshots
    INSERT INTO public.bills (
        id, bill_number, order_id, cashier_id, business_date,
        subtotal_amount, discount_type, discount_rate, discount_amount, discount_reason,
        tax_rate_snapshot, is_tax_inclusive_snapshot, tax_amount,
        round_off_amount, final_amount,
        store_name_snapshot, store_address_snapshot, store_gstin_snapshot,
        customer_name_snapshot, customer_phone_snapshot,
        status
    )
    VALUES (
        gen_random_uuid(), v_bill_number, p_order_id, v_actor, v_business_date,
        v_subtotal, p_discount_type, v_discount_rate, v_discount_amount, p_discount_reason,
        v_settings.tax_rate_percentage, v_settings.is_tax_inclusive, v_tax_amount,
        v_round_off, v_final_amount,
        v_settings.store_name, v_settings.address, v_settings.gstin,
        v_order.customer_name, v_order.customer_phone,
        'unpaid'
    )
    RETURNING id INTO v_bill_id;

    -- 14. Note: order remains 'served' while bill is unpaid; transitioned to 'completed' upon settle_bill()

    -- 15. Audit: BILL_GENERATED
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (v_actor, 'BILL_GENERATED', 'bill', v_bill_id::text,
        jsonb_build_object('bill_number', v_bill_number, 'order_id', p_order_id,
            'subtotal', v_subtotal, 'tax_amount', v_tax_amount, 'final_amount', v_final_amount));

    -- 16. Audit: DISCOUNT_APPLIED (if applicable)
    IF v_discount_amount > 0 THEN
        INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
        VALUES (v_actor, 'DISCOUNT_APPLIED', 'bill', v_bill_id::text,
            jsonb_build_object('discount_type', p_discount_type, 'discount_rate', v_discount_rate,
                'discount_amount', v_discount_amount, 'discount_reason', p_discount_reason));
    END IF;

    RETURN jsonb_build_object(
        'bill_id', v_bill_id,
        'bill_number', v_bill_number,
        'subtotal', v_subtotal,
        'discount_amount', v_discount_amount,
        'tax_amount', v_tax_amount,
        'round_off', v_round_off,
        'final_amount', v_final_amount
    );
END;
$$;

-- =====================================================================
-- RPC 10: settle_bill
-- =====================================================================
CREATE OR REPLACE FUNCTION public.settle_bill(
    p_bill_id UUID,
    p_payments JSONB  -- Array: [{"method": "cash", "amount": 100, "cash_tendered": 100, "transaction_reference": null}, ...]
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_bill RECORD;
    v_order RECORD;
    v_payment JSONB;
    v_payment_total NUMERIC(10,2) := 0;
    v_method VARCHAR(20);
    v_amount NUMERIC(10,2);
    v_cash_tendered NUMERIC(10,2);
    v_change_returned NUMERIC(10,2);
    v_transaction_ref VARCHAR(100);
    v_payment_ids JSONB := '[]'::jsonb;
    v_payment_id UUID;
BEGIN
    -- 1. Verify actor — cashier or super_admin
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL OR v_role NOT IN ('cashier', 'super_admin') THEN
        RAISE EXCEPTION 'Unauthorized: only cashier or super_admin can settle bills';
    END IF;

    -- 2. Lock bill
    SELECT * INTO v_bill FROM public.bills WHERE id = p_bill_id FOR UPDATE;
    IF v_bill IS NULL THEN
        RAISE EXCEPTION 'Bill not found';
    END IF;

    -- 3. Verify bill is unpaid (duplicate-safe idempotency guard)
    IF v_bill.status <> 'unpaid' THEN
        RAISE EXCEPTION 'Bill is not unpaid (status: %). Settlement rejected.', v_bill.status;
    END IF;

    -- 4. Lock parent order
    SELECT * INTO v_order FROM public.orders WHERE id = v_bill.order_id FOR UPDATE;
    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Parent order not found';
    END IF;

    -- 5. Verify order is not terminal
    IF v_order.status IN ('completed', 'cancelled') THEN
        RAISE EXCEPTION 'Parent order is in terminal state (status: %)', v_order.status;
    END IF;

    -- 6. Validate payment array
    IF p_payments IS NULL OR jsonb_array_length(p_payments) = 0 THEN
        RAISE EXCEPTION 'At least one payment entry is required';
    END IF;

    -- 7. Validate and insert each payment
    FOR v_payment IN SELECT * FROM jsonb_array_elements(p_payments)
    LOOP
        v_method := v_payment->>'method';
        v_amount := (v_payment->>'amount')::NUMERIC(10,2);
        v_cash_tendered := (v_payment->>'cash_tendered')::NUMERIC(10,2);
        v_transaction_ref := v_payment->>'transaction_reference';

        -- Validate method
        IF v_method IS NULL OR v_method NOT IN ('cash', 'upi', 'card') THEN
            RAISE EXCEPTION 'Invalid payment method: %', v_method;
        END IF;

        -- Validate amount
        IF v_amount IS NULL OR v_amount <= 0 THEN
            RAISE EXCEPTION 'Payment amount must be positive';
        END IF;

        -- Validate cash-specific fields
        IF v_method = 'cash' THEN
            IF v_cash_tendered IS NULL THEN
                RAISE EXCEPTION 'Cash tendered is required for cash payments';
            END IF;
            IF v_cash_tendered < v_amount THEN
                RAISE EXCEPTION 'Cash tendered (%) is less than payment amount (%)', v_cash_tendered, v_amount;
            END IF;
            v_change_returned := v_cash_tendered - v_amount;
        ELSE
            -- Non-cash: ensure cash fields are NULL
            v_cash_tendered := NULL;
            v_change_returned := NULL;
        END IF;

        v_payment_total := v_payment_total + v_amount;

        -- Insert payment record
        INSERT INTO public.payments (
            bill_id, payment_method, amount, transaction_reference,
            cash_tendered, change_returned, received_by, status
        )
        VALUES (
            p_bill_id, v_method, v_amount, v_transaction_ref,
            v_cash_tendered, v_change_returned, v_actor, 'completed'
        )
        RETURNING id INTO v_payment_id;

        v_payment_ids := v_payment_ids || jsonb_build_array(v_payment_id);
    END LOOP;

    -- 8. Validate exact payment total
    IF v_payment_total <> v_bill.final_amount THEN
        RAISE EXCEPTION 'Payment total (₹%) does not match bill final amount (₹%)',
            v_payment_total, v_bill.final_amount;
    END IF;

    -- 9. Mark bill as paid
    UPDATE public.bills SET
        status = 'paid',
        settled_by = v_actor
    WHERE id = p_bill_id;

    -- 10. Complete parent order
    UPDATE public.orders SET status = 'completed' WHERE id = v_bill.order_id;

    -- 11. Release table if dine-in
    IF v_order.order_type = 'dine_in' AND v_order.table_id IS NOT NULL THEN
        UPDATE public.restaurant_tables SET status = 'available'
        WHERE id = v_order.table_id;
    END IF;

    -- 12. Audit
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (v_actor, 'BILL_SETTLED', 'bill', p_bill_id::text,
        jsonb_build_object('bill_number', v_bill.bill_number, 'final_amount', v_bill.final_amount,
            'payment_count', jsonb_array_length(p_payments), 'payment_ids', v_payment_ids));

    -- 13. Return success (commit atomically as single transaction)
    RETURN jsonb_build_object(
        'success', true,
        'bill_id', p_bill_id,
        'bill_number', v_bill.bill_number,
        'final_amount', v_bill.final_amount,
        'payment_ids', v_payment_ids
    );
END;
$$;

-- =====================================================================
-- RPC 11: void_bill
-- =====================================================================
CREATE OR REPLACE FUNCTION public.void_bill(
    p_bill_id UUID,
    p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_bill RECORD;
    v_order RECORD;
    v_was_paid BOOLEAN;
BEGIN
    -- 1. Verify actor — super_admin ONLY
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL OR v_role <> 'super_admin' THEN
        RAISE EXCEPTION 'Unauthorized: only super_admin can void bills';
    END IF;

    -- 2. Validate reason
    IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
        RAISE EXCEPTION 'Void reason is required (minimum 3 characters)';
    END IF;

    -- 3. Lock bill
    SELECT * INTO v_bill FROM public.bills WHERE id = p_bill_id FOR UPDATE;
    IF v_bill IS NULL THEN
        RAISE EXCEPTION 'Bill not found';
    END IF;

    -- 4. Verify bill is voidable (not already voided)
    IF v_bill.status = 'voided' THEN
        RAISE EXCEPTION 'Bill is already voided';
    END IF;

    v_was_paid := (v_bill.status = 'paid');

    -- 5. Lock parent order
    SELECT * INTO v_order FROM public.orders WHERE id = v_bill.order_id FOR UPDATE;

    -- 6. Void the bill
    UPDATE public.bills SET
        status = 'voided',
        void_reason = p_reason,
        voided_by = v_actor,
        voided_at = now()
    WHERE id = p_bill_id;

    -- 7. If bill was paid, refund all associated payments (internal accounting record)
    IF v_was_paid THEN
        UPDATE public.payments SET
            status = 'refunded',
            refunded_at = now(),
            refunded_by = v_actor,
            refund_reason = p_reason
        WHERE bill_id = p_bill_id AND status = 'completed';

        -- Audit: PAYMENT_REFUNDED
        INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, old_data, new_data)
        VALUES (v_actor, 'PAYMENT_REFUNDED', 'bill', p_bill_id::text,
            jsonb_build_object('bill_number', v_bill.bill_number, 'was_paid', true),
            jsonb_build_object('refund_reason', p_reason, 'refunded_by', v_actor));
    END IF;

    -- 8. Cancel parent order
    UPDATE public.orders SET status = 'cancelled' WHERE id = v_bill.order_id;

    -- 9. Cancel all non-cancelled order items
    UPDATE public.order_items SET status = 'cancelled'
    WHERE order_id = v_bill.order_id AND status <> 'cancelled';

    -- 10. Release table if dine-in
    IF v_order.order_type = 'dine_in' AND v_order.table_id IS NOT NULL THEN
        UPDATE public.restaurant_tables SET status = 'available'
        WHERE id = v_order.table_id;
    END IF;

    -- 11. Audit: BILL_VOIDED
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, old_data, new_data)
    VALUES (v_actor, 'BILL_VOIDED', 'bill', p_bill_id::text,
        jsonb_build_object('previous_status', v_bill.status, 'bill_number', v_bill.bill_number,
            'final_amount', v_bill.final_amount),
        jsonb_build_object('void_reason', p_reason, 'voided_by', v_actor));

    RETURN jsonb_build_object('success', true, 'was_paid', v_was_paid);
END;
$$;

-- =====================================================================
-- RPC 12: create_category
-- =====================================================================
CREATE OR REPLACE FUNCTION public.create_category(
    p_name VARCHAR,
    p_slug VARCHAR,
    p_display_order INTEGER DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_category_id UUID;
BEGIN
    -- 1. Verify super_admin
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL OR v_role <> 'super_admin' THEN
        RAISE EXCEPTION 'Unauthorized: only super_admin can create categories';
    END IF;

    -- 2. Validate inputs
    IF p_name IS NULL OR length(trim(p_name)) = 0 THEN
        RAISE EXCEPTION 'Category name is required';
    END IF;
    IF p_slug IS NULL OR length(trim(p_slug)) = 0 THEN
        RAISE EXCEPTION 'Category slug is required';
    END IF;

    -- 3. Create category
    INSERT INTO public.categories (name, slug, display_order)
    VALUES (trim(p_name), lower(trim(p_slug)), p_display_order)
    RETURNING id INTO v_category_id;

    -- 4. Audit
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (v_actor, 'CATEGORY_CREATED', 'category', v_category_id::text,
        jsonb_build_object('name', p_name, 'slug', p_slug, 'display_order', p_display_order));

    RETURN jsonb_build_object('category_id', v_category_id);
END;
$$;

-- =====================================================================
-- RPC 13: update_category
-- =====================================================================
CREATE OR REPLACE FUNCTION public.update_category(
    p_category_id UUID,
    p_name VARCHAR DEFAULT NULL,
    p_slug VARCHAR DEFAULT NULL,
    p_display_order INTEGER DEFAULT NULL,
    p_is_active BOOLEAN DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_old RECORD;
BEGIN
    -- 1. Verify super_admin
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL OR v_role <> 'super_admin' THEN
        RAISE EXCEPTION 'Unauthorized: only super_admin can update categories';
    END IF;

    -- 2. Lock and get current category
    SELECT * INTO v_old FROM public.categories WHERE id = p_category_id FOR UPDATE;
    IF v_old IS NULL THEN
        RAISE EXCEPTION 'Category not found';
    END IF;

    -- 3. Update
    UPDATE public.categories SET
        name = COALESCE(trim(p_name), name),
        slug = COALESCE(lower(trim(p_slug)), slug),
        display_order = COALESCE(p_display_order, display_order),
        is_active = COALESCE(p_is_active, is_active)
    WHERE id = p_category_id;

    -- 4. Audit
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, old_data, new_data)
    VALUES (v_actor, 'CATEGORY_UPDATED', 'category', p_category_id::text,
        jsonb_build_object('name', v_old.name, 'slug', v_old.slug,
            'display_order', v_old.display_order, 'is_active', v_old.is_active),
        jsonb_build_object('name', COALESCE(p_name, v_old.name), 'slug', COALESCE(p_slug, v_old.slug),
            'display_order', COALESCE(p_display_order, v_old.display_order),
            'is_active', COALESCE(p_is_active, v_old.is_active)));

    RETURN jsonb_build_object('success', true);
END;
$$;

-- =====================================================================
-- RPC 14: create_menu_item
-- =====================================================================
CREATE OR REPLACE FUNCTION public.create_menu_item(
    p_category_id UUID,
    p_name VARCHAR,
    p_base_price NUMERIC,
    p_description TEXT DEFAULT NULL,
    p_display_order INTEGER DEFAULT 0,
    p_image_url TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_item_id UUID;
BEGIN
    -- 1. Verify super_admin
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL OR v_role <> 'super_admin' THEN
        RAISE EXCEPTION 'Unauthorized: only super_admin can create menu items';
    END IF;

    -- 2. Validate
    IF p_name IS NULL OR length(trim(p_name)) = 0 THEN
        RAISE EXCEPTION 'Menu item name is required';
    END IF;
    IF p_base_price IS NULL OR p_base_price < 0 THEN
        RAISE EXCEPTION 'Base price must be non-negative';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.categories WHERE id = p_category_id AND is_active = true) THEN
        RAISE EXCEPTION 'Category not found or inactive';
    END IF;

    -- 3. Create
    INSERT INTO public.menu_items (category_id, name, description, base_price, display_order, image_url)
    VALUES (p_category_id, trim(p_name), p_description, p_base_price, p_display_order, p_image_url)
    RETURNING id INTO v_item_id;

    -- 4. Audit
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, new_data)
    VALUES (v_actor, 'MENU_ITEM_CREATED', 'menu_item', v_item_id::text,
        jsonb_build_object('name', p_name, 'base_price', p_base_price, 'category_id', p_category_id));

    RETURN jsonb_build_object('menu_item_id', v_item_id);
END;
$$;

-- =====================================================================
-- RPC 15: update_menu_item
-- =====================================================================
CREATE OR REPLACE FUNCTION public.update_menu_item(
    p_menu_item_id UUID,
    p_name VARCHAR DEFAULT NULL,
    p_description TEXT DEFAULT NULL,
    p_base_price NUMERIC DEFAULT NULL,
    p_category_id UUID DEFAULT NULL,
    p_display_order INTEGER DEFAULT NULL,
    p_is_active BOOLEAN DEFAULT NULL,
    p_image_url TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_old RECORD;
BEGIN
    -- 1. Verify super_admin
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL OR v_role <> 'super_admin' THEN
        RAISE EXCEPTION 'Unauthorized: only super_admin can update menu items';
    END IF;

    -- 2. Lock and get current item
    SELECT * INTO v_old FROM public.menu_items WHERE id = p_menu_item_id FOR UPDATE;
    IF v_old IS NULL THEN
        RAISE EXCEPTION 'Menu item not found';
    END IF;

    -- 3. Validate new price
    IF p_base_price IS NOT NULL AND p_base_price < 0 THEN
        RAISE EXCEPTION 'Base price must be non-negative';
    END IF;

    -- 4. Validate new category if provided
    IF p_category_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM public.categories WHERE id = p_category_id AND is_active = true) THEN
            RAISE EXCEPTION 'Target category not found or inactive';
        END IF;
    END IF;

    -- 5. Update
    UPDATE public.menu_items SET
        name = COALESCE(trim(p_name), name),
        description = COALESCE(p_description, description),
        base_price = COALESCE(p_base_price, base_price),
        category_id = COALESCE(p_category_id, category_id),
        display_order = COALESCE(p_display_order, display_order),
        is_active = COALESCE(p_is_active, is_active),
        image_url = COALESCE(p_image_url, image_url)
    WHERE id = p_menu_item_id;

    -- 6. Audit (price change is also captured by trigger trg_audit_menu_items)
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, old_data, new_data)
    VALUES (v_actor, 'MENU_ITEM_UPDATED', 'menu_item', p_menu_item_id::text,
        jsonb_build_object('name', v_old.name, 'base_price', v_old.base_price,
            'category_id', v_old.category_id, 'is_active', v_old.is_active),
        jsonb_build_object('name', COALESCE(p_name, v_old.name),
            'base_price', COALESCE(p_base_price, v_old.base_price),
            'category_id', COALESCE(p_category_id, v_old.category_id),
            'is_active', COALESCE(p_is_active, v_old.is_active)));

    RETURN jsonb_build_object('success', true);
END;
$$;

-- =====================================================================
-- RPC 16: toggle_menu_item_availability
-- =====================================================================
CREATE OR REPLACE FUNCTION public.toggle_menu_item_availability(p_menu_item_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_old RECORD;
BEGIN
    -- 1. Verify cashier or super_admin
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL OR v_role NOT IN ('cashier', 'super_admin') THEN
        RAISE EXCEPTION 'Unauthorized: only cashier or super_admin can toggle availability';
    END IF;

    -- 2. Lock and get current item
    SELECT * INTO v_old FROM public.menu_items WHERE id = p_menu_item_id FOR UPDATE;
    IF v_old IS NULL THEN
        RAISE EXCEPTION 'Menu item not found';
    END IF;

    -- 3. Toggle
    UPDATE public.menu_items SET is_available = NOT v_old.is_available WHERE id = p_menu_item_id;

    -- 4. Audit
    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, old_data, new_data)
    VALUES (v_actor, 'MENU_ITEM_AVAILABILITY_CHANGED', 'menu_item', p_menu_item_id::text,
        jsonb_build_object('is_available', v_old.is_available),
        jsonb_build_object('is_available', NOT v_old.is_available));

    RETURN jsonb_build_object('success', true, 'is_available', NOT v_old.is_available);
END;
$$;

-- =====================================================================
-- RPC 17: update_user_role
-- =====================================================================
CREATE OR REPLACE FUNCTION public.update_user_role(
    p_target_user_id UUID,
    p_new_role VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_target RECORD;
    v_active_admin_count INTEGER;
BEGIN
    -- 1. Verify super_admin
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL OR v_role <> 'super_admin' THEN
        RAISE EXCEPTION 'Unauthorized: only super_admin can change roles';
    END IF;

    -- 2. Block self-demotion
    IF v_actor = p_target_user_id THEN
        RAISE EXCEPTION 'Cannot change your own role';
    END IF;

    -- 3. Validate new role
    IF p_new_role NOT IN ('super_admin', 'cashier', 'server') THEN
        RAISE EXCEPTION 'Invalid role: %', p_new_role;
    END IF;

    -- 4. Lock ALL active super_admin rows in deterministic order to serialize concurrent role changes
    PERFORM 1 FROM public.user_profiles
    WHERE role = 'super_admin' AND is_active = true
    ORDER BY id
    FOR UPDATE;

    -- 5. Get target user
    SELECT * INTO v_target FROM public.user_profiles WHERE id = p_target_user_id;
    IF v_target IS NULL THEN
        RAISE EXCEPTION 'Target user not found';
    END IF;

    -- 6. If demoting a super_admin, verify at least 2 active super_admins exist
    IF v_target.role = 'super_admin' AND p_new_role <> 'super_admin' THEN
        SELECT count(*) INTO v_active_admin_count
        FROM public.user_profiles
        WHERE role = 'super_admin' AND is_active = true;

        IF v_active_admin_count <= 1 THEN
            RAISE EXCEPTION 'Cannot demote the last active super_admin';
        END IF;
    END IF;

    -- 7. Update role
    UPDATE public.user_profiles SET role = p_new_role WHERE id = p_target_user_id;

    RETURN jsonb_build_object('success', true, 'old_role', v_target.role, 'new_role', p_new_role);
END;
$$;

-- =====================================================================
-- RPC 18: toggle_user_active
-- =====================================================================
CREATE OR REPLACE FUNCTION public.toggle_user_active(p_target_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_target RECORD;
    v_active_admin_count INTEGER;
BEGIN
    -- 1. Verify super_admin
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL OR v_role <> 'super_admin' THEN
        RAISE EXCEPTION 'Unauthorized: only super_admin can toggle user status';
    END IF;

    -- 2. Block self-deactivation
    IF v_actor = p_target_user_id THEN
        RAISE EXCEPTION 'Cannot deactivate yourself';
    END IF;

    -- 3. Lock ALL active super_admin rows in deterministic order to serialize concurrent status changes
    PERFORM 1 FROM public.user_profiles
    WHERE role = 'super_admin' AND is_active = true
    ORDER BY id
    FOR UPDATE;

    -- 4. Get target user
    SELECT * INTO v_target FROM public.user_profiles WHERE id = p_target_user_id;
    IF v_target IS NULL THEN
        RAISE EXCEPTION 'Target user not found';
    END IF;

    -- 5. If deactivating a super_admin, verify at least 2 active super_admins exist
    IF v_target.role = 'super_admin' AND v_target.is_active = true THEN
        SELECT count(*) INTO v_active_admin_count
        FROM public.user_profiles
        WHERE role = 'super_admin' AND is_active = true;

        IF v_active_admin_count <= 1 THEN
            RAISE EXCEPTION 'Cannot deactivate the last active super_admin';
        END IF;
    END IF;

    -- 6. Toggle
    UPDATE public.user_profiles SET is_active = NOT v_target.is_active WHERE id = p_target_user_id;

    RETURN jsonb_build_object('success', true, 'is_active', NOT v_target.is_active);
END;
$$;

-- =====================================================================
-- RPC 19: update_store_settings
-- =====================================================================
CREATE OR REPLACE FUNCTION public.update_store_settings(
    p_store_name VARCHAR DEFAULT NULL,
    p_tagline VARCHAR DEFAULT NULL,
    p_address TEXT DEFAULT NULL,
    p_phone VARCHAR DEFAULT NULL,
    p_email VARCHAR DEFAULT NULL,
    p_gstin VARCHAR DEFAULT NULL,
    p_tax_rate_percentage NUMERIC DEFAULT NULL,
    p_is_tax_inclusive BOOLEAN DEFAULT NULL,
    p_currency_code VARCHAR DEFAULT NULL,
    p_currency_symbol VARCHAR DEFAULT NULL,
    p_receipt_header TEXT DEFAULT NULL,
    p_receipt_footer TEXT DEFAULT NULL,
    p_bill_prefix VARCHAR DEFAULT NULL,
    p_order_prefix VARCHAR DEFAULT NULL,
    p_max_cashier_discount_percentage NUMERIC DEFAULT NULL,
    p_max_cashier_discount_amount NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_role VARCHAR(20);
    v_old RECORD;
BEGIN
    -- 1. Verify super_admin
    SELECT role INTO v_role FROM public.user_profiles WHERE id = v_actor AND is_active = true;
    IF v_role IS NULL OR v_role <> 'super_admin' THEN
        RAISE EXCEPTION 'Unauthorized: only super_admin can update store settings';
    END IF;

    -- 2. Lock settings row
    SELECT * INTO v_old FROM public.store_settings
    WHERE id = '00000000-0000-0000-0000-000000000001'::uuid FOR UPDATE;
    IF v_old IS NULL THEN
        RAISE EXCEPTION 'Store settings not found';
    END IF;

    -- 3. Validate tax rate
    IF p_tax_rate_percentage IS NOT NULL AND (p_tax_rate_percentage < 0 OR p_tax_rate_percentage > 100) THEN
        RAISE EXCEPTION 'Tax rate must be between 0 and 100';
    END IF;

    -- 4. Validate discount limits
    IF p_max_cashier_discount_percentage IS NOT NULL
       AND (p_max_cashier_discount_percentage < 0 OR p_max_cashier_discount_percentage > 100) THEN
        RAISE EXCEPTION 'Cashier discount percentage must be between 0 and 100';
    END IF;
    IF p_max_cashier_discount_amount IS NOT NULL AND p_max_cashier_discount_amount < 0 THEN
        RAISE EXCEPTION 'Cashier discount amount must be non-negative';
    END IF;

    -- 5. Update (trigger handles audit and updated_at)
    UPDATE public.store_settings SET
        store_name = COALESCE(p_store_name, store_name),
        tagline = COALESCE(p_tagline, tagline),
        address = COALESCE(p_address, address),
        phone = COALESCE(p_phone, phone),
        email = COALESCE(p_email, email),
        gstin = COALESCE(p_gstin, gstin),
        tax_rate_percentage = COALESCE(p_tax_rate_percentage, tax_rate_percentage),
        is_tax_inclusive = COALESCE(p_is_tax_inclusive, is_tax_inclusive),
        currency_code = COALESCE(p_currency_code, currency_code),
        currency_symbol = COALESCE(p_currency_symbol, currency_symbol),
        receipt_header = COALESCE(p_receipt_header, receipt_header),
        receipt_footer = COALESCE(p_receipt_footer, receipt_footer),
        bill_prefix = COALESCE(p_bill_prefix, bill_prefix),
        order_prefix = COALESCE(p_order_prefix, order_prefix),
        max_cashier_discount_percentage = COALESCE(p_max_cashier_discount_percentage, max_cashier_discount_percentage),
        max_cashier_discount_amount = COALESCE(p_max_cashier_discount_amount, max_cashier_discount_amount),
        updated_by = v_actor
    WHERE id = '00000000-0000-0000-0000-000000000001'::uuid;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- *****************************************************************************
-- SECTION 6: RLS ENABLEMENT & POLICIES
-- *****************************************************************************

-- Enable RLS on all 12 tables
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.store_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_tables ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bill_sequences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- Note: bill_sequences has ENABLE ROW LEVEL SECURITY with no SELECT/DML policies.
-- Direct client access is denied; atomic daily sequence increments are performed
-- exclusively by the trusted SECURITY DEFINER helper public.get_next_bill_number().
-- Table-owner bypass is preserved (no forced RLS) to allow internal sequence allocation.

-- SELECT policies for staff-readable tables (10 tables)
CREATE POLICY "Staff can read user_profiles" ON public.user_profiles
    FOR SELECT USING (public.is_staff());

CREATE POLICY "Staff can read store_settings" ON public.store_settings
    FOR SELECT USING (public.is_staff());

CREATE POLICY "Staff can read categories" ON public.categories
    FOR SELECT USING (public.is_staff());

CREATE POLICY "Staff can read menu_items" ON public.menu_items
    FOR SELECT USING (public.is_staff());

CREATE POLICY "Staff can read restaurant_tables" ON public.restaurant_tables
    FOR SELECT USING (public.is_staff());

CREATE POLICY "Staff can read customers" ON public.customers
    FOR SELECT USING (public.is_staff());

CREATE POLICY "Staff can read orders" ON public.orders
    FOR SELECT USING (public.is_staff());

CREATE POLICY "Staff can read order_items" ON public.order_items
    FOR SELECT USING (public.is_staff());

CREATE POLICY "Staff can read bills" ON public.bills
    FOR SELECT USING (public.is_staff());

CREATE POLICY "Staff can read payments" ON public.payments
    FOR SELECT USING (public.is_staff());

-- audit_logs: only super_admin can read
CREATE POLICY "Super admin can read audit_logs" ON public.audit_logs
    FOR SELECT USING (public.is_super_admin());

-- bill_sequences: NO SELECT policy (internal only, accessed via SECURITY DEFINER)
-- No policy = denied by default when RLS is enabled


-- *****************************************************************************
-- SECTION 7: OBJECT PRIVILEGES (Grants & Revokes)
-- *****************************************************************************

-- Grant schema usage to authenticated
GRANT USAGE ON SCHEMA public TO authenticated;

-- Grant SELECT on client-readable tables to authenticated
GRANT SELECT ON public.user_profiles TO authenticated;
GRANT SELECT ON public.store_settings TO authenticated;
GRANT SELECT ON public.categories TO authenticated;
GRANT SELECT ON public.menu_items TO authenticated;
GRANT SELECT ON public.restaurant_tables TO authenticated;
GRANT SELECT ON public.customers TO authenticated;
GRANT SELECT ON public.orders TO authenticated;
GRANT SELECT ON public.order_items TO authenticated;
GRANT SELECT ON public.bills TO authenticated;
GRANT SELECT ON public.payments TO authenticated;
GRANT SELECT ON public.audit_logs TO authenticated;

-- bill_sequences: NO grants to authenticated (internal only)
-- The table owner (postgres) can access it via SECURITY DEFINER functions

-- =============================================================================
-- 19 Client-Callable Business RPC Privileges
-- Zero-Trust Privilege Model:
-- Explicitly REVOKE FROM PUBLIC, REVOKE FROM anon, and GRANT TO authenticated
-- =============================================================================

-- 1. create_dine_in_order
REVOKE EXECUTE ON FUNCTION public.create_dine_in_order(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_dine_in_order(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_dine_in_order(UUID, TEXT) TO authenticated;

-- 2. create_takeaway_order
REVOKE EXECUTE ON FUNCTION public.create_takeaway_order(TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_takeaway_order(TEXT, TEXT, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_takeaway_order(TEXT, TEXT, TEXT) TO authenticated;

-- 3. add_order_item
REVOKE EXECUTE ON FUNCTION public.add_order_item(UUID, UUID, INTEGER, VARCHAR) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.add_order_item(UUID, UUID, INTEGER, VARCHAR) FROM anon;
GRANT EXECUTE ON FUNCTION public.add_order_item(UUID, UUID, INTEGER, VARCHAR) TO authenticated;

-- 4. update_order_item_quantity
REVOKE EXECUTE ON FUNCTION public.update_order_item_quantity(UUID, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_order_item_quantity(UUID, INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_order_item_quantity(UUID, INTEGER) TO authenticated;

-- 5. cancel_order_item
REVOKE EXECUTE ON FUNCTION public.cancel_order_item(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cancel_order_item(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.cancel_order_item(UUID, TEXT) TO authenticated;

-- 6. transfer_table
REVOKE EXECUTE ON FUNCTION public.transfer_table(UUID, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.transfer_table(UUID, UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.transfer_table(UUID, UUID) TO authenticated;

-- 7. mark_order_served
REVOKE EXECUTE ON FUNCTION public.mark_order_served(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.mark_order_served(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.mark_order_served(UUID) TO authenticated;

-- 8. cancel_order
REVOKE EXECUTE ON FUNCTION public.cancel_order(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cancel_order(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.cancel_order(UUID, TEXT) TO authenticated;

-- 9. generate_bill_for_order
REVOKE EXECUTE ON FUNCTION public.generate_bill_for_order(UUID, VARCHAR, NUMERIC, VARCHAR) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.generate_bill_for_order(UUID, VARCHAR, NUMERIC, VARCHAR) FROM anon;
GRANT EXECUTE ON FUNCTION public.generate_bill_for_order(UUID, VARCHAR, NUMERIC, VARCHAR) TO authenticated;

-- 10. settle_bill
REVOKE EXECUTE ON FUNCTION public.settle_bill(UUID, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.settle_bill(UUID, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.settle_bill(UUID, JSONB) TO authenticated;

-- 11. void_bill
REVOKE EXECUTE ON FUNCTION public.void_bill(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.void_bill(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.void_bill(UUID, TEXT) TO authenticated;

-- 12. create_category
REVOKE EXECUTE ON FUNCTION public.create_category(VARCHAR, VARCHAR, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_category(VARCHAR, VARCHAR, INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_category(VARCHAR, VARCHAR, INTEGER) TO authenticated;

-- 13. update_category
REVOKE EXECUTE ON FUNCTION public.update_category(UUID, VARCHAR, VARCHAR, INTEGER, BOOLEAN) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_category(UUID, VARCHAR, VARCHAR, INTEGER, BOOLEAN) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_category(UUID, VARCHAR, VARCHAR, INTEGER, BOOLEAN) TO authenticated;

-- 14. create_menu_item
REVOKE EXECUTE ON FUNCTION public.create_menu_item(UUID, VARCHAR, NUMERIC, TEXT, INTEGER, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_menu_item(UUID, VARCHAR, NUMERIC, TEXT, INTEGER, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_menu_item(UUID, VARCHAR, NUMERIC, TEXT, INTEGER, TEXT) TO authenticated;

-- 15. update_menu_item
REVOKE EXECUTE ON FUNCTION public.update_menu_item(UUID, VARCHAR, TEXT, NUMERIC, UUID, INTEGER, BOOLEAN, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_menu_item(UUID, VARCHAR, TEXT, NUMERIC, UUID, INTEGER, BOOLEAN, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_menu_item(UUID, VARCHAR, TEXT, NUMERIC, UUID, INTEGER, BOOLEAN, TEXT) TO authenticated;

-- 16. toggle_menu_item_availability
REVOKE EXECUTE ON FUNCTION public.toggle_menu_item_availability(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.toggle_menu_item_availability(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.toggle_menu_item_availability(UUID) TO authenticated;

-- 17. update_user_role
REVOKE EXECUTE ON FUNCTION public.update_user_role(UUID, VARCHAR) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_user_role(UUID, VARCHAR) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_user_role(UUID, VARCHAR) TO authenticated;

-- 18. toggle_user_active
REVOKE EXECUTE ON FUNCTION public.toggle_user_active(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.toggle_user_active(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.toggle_user_active(UUID) TO authenticated;

-- 19. update_store_settings
REVOKE EXECUTE ON FUNCTION public.update_store_settings(VARCHAR, VARCHAR, TEXT, VARCHAR, VARCHAR, VARCHAR, NUMERIC, BOOLEAN, VARCHAR, VARCHAR, TEXT, TEXT, VARCHAR, VARCHAR, NUMERIC, NUMERIC) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_store_settings(VARCHAR, VARCHAR, TEXT, VARCHAR, VARCHAR, VARCHAR, NUMERIC, BOOLEAN, VARCHAR, VARCHAR, TEXT, TEXT, VARCHAR, VARCHAR, NUMERIC, NUMERIC) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_store_settings(VARCHAR, VARCHAR, TEXT, VARCHAR, VARCHAR, VARCHAR, NUMERIC, BOOLEAN, VARCHAR, VARCHAR, TEXT, TEXT, VARCHAR, VARCHAR, NUMERIC, NUMERIC) TO authenticated;

-- =============================================================================
-- RLS Helper Function Privileges (3 Functions)
-- Revoke from PUBLIC and anon, grant to authenticated for RLS policy evaluation
-- =============================================================================
REVOKE EXECUTE ON FUNCTION public.is_staff() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.is_staff() FROM anon;
GRANT EXECUTE ON FUNCTION public.is_staff() TO authenticated;

REVOKE EXECUTE ON FUNCTION public.is_super_admin() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.is_super_admin() FROM anon;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated;

REVOKE EXECUTE ON FUNCTION public.is_cashier_or_admin() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.is_cashier_or_admin() FROM anon;
GRANT EXECUTE ON FUNCTION public.is_cashier_or_admin() TO authenticated;

-- =============================================================================
-- Internal & Trigger Helper Function Privileges (8 Functions)
-- Strictly revoke from authenticated, anon, and PUBLIC (internal-only execution)
-- =============================================================================
REVOKE EXECUTE ON FUNCTION public.normalize_indian_phone(TEXT) FROM authenticated, anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_next_bill_number(VARCHAR) FROM authenticated, anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.generate_order_number(VARCHAR) FROM authenticated, anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_current_user_role() FROM authenticated, anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_audit_user_profiles() FROM authenticated, anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_audit_store_settings() FROM authenticated, anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_audit_menu_items() FROM authenticated, anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_set_updated_at() FROM authenticated, anon, PUBLIC;

-- Revoke any direct DML privileges on all tables from authenticated
-- (Supabase grants SELECT via the above; we ensure no INSERT/UPDATE/DELETE)
REVOKE INSERT, UPDATE, DELETE ON public.user_profiles FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.store_settings FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.categories FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.menu_items FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.restaurant_tables FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.customers FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.orders FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.order_items FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.bills FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.payments FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.bill_sequences FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.audit_logs FROM authenticated;

-- Revoke everything from anon on all application tables
REVOKE ALL ON public.user_profiles FROM anon;
REVOKE ALL ON public.store_settings FROM anon;
REVOKE ALL ON public.categories FROM anon;
REVOKE ALL ON public.menu_items FROM anon;
REVOKE ALL ON public.restaurant_tables FROM anon;
REVOKE ALL ON public.customers FROM anon;
REVOKE ALL ON public.orders FROM anon;
REVOKE ALL ON public.order_items FROM anon;
REVOKE ALL ON public.bills FROM anon;
REVOKE ALL ON public.payments FROM anon;
REVOKE ALL ON public.bill_sequences FROM anon;
REVOKE ALL ON public.audit_logs FROM anon;


-- *****************************************************************************
-- SECTION 8: REALTIME CONFIGURATION
-- *****************************************************************************
-- Add operational tables to Supabase Realtime publication (Postgres Changes)
-- Note: supabase_realtime publication is managed by Supabase and should already exist
ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
ALTER PUBLICATION supabase_realtime ADD TABLE public.order_items;
ALTER PUBLICATION supabase_realtime ADD TABLE public.bills;

-- Set REPLICA IDENTITY FULL for complete row payloads on UPDATE events
ALTER TABLE public.orders REPLICA IDENTITY FULL;
ALTER TABLE public.order_items REPLICA IDENTITY FULL;
ALTER TABLE public.bills REPLICA IDENTITY FULL;


-- *****************************************************************************
-- SECTION 9: REPORTING VIEWS
-- *****************************************************************************

-- Daily sales summary (paid bills only)
CREATE OR REPLACE VIEW public.v_daily_sales AS
SELECT
    business_date,
    COUNT(*) AS total_bills,
    SUM(final_amount) AS gross_sales,
    SUM(discount_amount) AS total_discounts,
    SUM(tax_amount) AS gst_collected,
    SUM(round_off_amount) AS total_round_off,
    SUM(final_amount) AS net_revenue
FROM public.bills
WHERE status = 'paid'
GROUP BY business_date
ORDER BY business_date DESC;

-- Payment method summary by business date
CREATE OR REPLACE VIEW public.v_payment_summary AS
SELECT
    b.business_date,
    p.payment_method,
    p.status AS payment_status,
    COUNT(*) AS payment_count,
    SUM(p.amount) AS total_amount
FROM public.payments p
JOIN public.bills b ON b.id = p.bill_id
GROUP BY b.business_date, p.payment_method, p.status
ORDER BY b.business_date DESC, p.payment_method;

-- Item sales summary (paid bills, non-cancelled items)
CREATE OR REPLACE VIEW public.v_item_sales_summary AS
SELECT
    b.business_date,
    oi.item_name_snapshot,
    oi.category_name_snapshot,
    SUM(oi.quantity) AS total_quantity,
    SUM(oi.item_total) AS total_revenue
FROM public.order_items oi
JOIN public.orders o ON o.id = oi.order_id
JOIN public.bills b ON b.order_id = o.id
WHERE oi.status <> 'cancelled'
  AND b.status = 'paid'
GROUP BY b.business_date, oi.item_name_snapshot, oi.category_name_snapshot
ORDER BY b.business_date DESC, total_revenue DESC;

-- Void and refund report
CREATE OR REPLACE VIEW public.v_void_refund_report AS
SELECT
    b.bill_number,
    b.business_date,
    b.final_amount AS original_amount,
    b.void_reason,
    b.voided_at,
    vb.full_name AS voided_by_name,
    b.status AS bill_status,
    COALESCE(
        (SELECT SUM(p.amount) FROM public.payments p WHERE p.bill_id = b.id AND p.status = 'refunded'),
        0
    ) AS refunded_amount
FROM public.bills b
LEFT JOIN public.user_profiles vb ON vb.id = b.voided_by
WHERE b.status = 'voided'
ORDER BY b.voided_at DESC;

-- Revoke view access from PUBLIC and anon (zero-trust)
REVOKE ALL ON public.v_daily_sales FROM PUBLIC, anon;
REVOKE ALL ON public.v_payment_summary FROM PUBLIC, anon;
REVOKE ALL ON public.v_item_sales_summary FROM PUBLIC, anon;
REVOKE ALL ON public.v_void_refund_report FROM PUBLIC, anon;

-- Grant view SELECT access to authenticated staff
GRANT SELECT ON public.v_daily_sales TO authenticated;
GRANT SELECT ON public.v_payment_summary TO authenticated;
GRANT SELECT ON public.v_item_sales_summary TO authenticated;
GRANT SELECT ON public.v_void_refund_report TO authenticated;


-- *****************************************************************************
-- SECTION 10: SEED DATA
-- *****************************************************************************

-- Insert singleton store_settings row with V1 defaults
INSERT INTO public.store_settings (
    id,
    store_name,
    tagline,
    receipt_footer,
    bill_prefix,
    order_prefix,
    tax_rate_percentage,
    is_tax_inclusive,
    currency_code,
    currency_symbol,
    max_cashier_discount_percentage,
    max_cashier_discount_amount
)
VALUES (
    '00000000-0000-0000-0000-000000000001'::uuid,
    'Fresh Cane',
    'Pure & Natural Sugarcane Juice',
    'Thank you for visiting Fresh Cane!',
    'FC-',
    'ORD-',
    0.00,
    true,
    'INR',
    '₹',
    10.00,
    100.00
)
ON CONFLICT (id) DO NOTHING;


-- *****************************************************************************
-- SECTION 11: MIGRATION COMPLETE
-- *****************************************************************************
-- Fresh Cane V1 Initial Production Migration
-- Tables: 12
-- Client RPCs: 19
-- Internal Helpers: 11 (4 implementation + 3 RLS + 4 trigger/utility)
-- RLS: Enabled on all 12 tables
-- Realtime: orders, order_items, bills
-- Reporting Views: 4
-- Seed: store_settings singleton
-- =============================================================================
