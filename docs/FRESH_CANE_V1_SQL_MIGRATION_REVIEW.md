# Fresh Cane V1 — SQL Migration Review & Hardening Report

> **Migration File:** `supabase/migrations/20260912170000_fresh_cane_v1_initial.sql`  
> **Architecture Specification:** Fresh Cane Database Architecture V2.2.3  
> **Target Database Engine:** PostgreSQL 17 (Supabase Cloud Managed)  
> **Review Date:** 2026-09-12  
> **Execution Status:** **NOT EXECUTED REMOTELY** (Local Static Review Only)  
> **Final Verdict:** `READY FOR SQL EXECUTION REVIEW`  

---

## 1. Migration Summary

* **Migration Filename:** `supabase/migrations/20260912170000_fresh_cane_v1_initial.sql`
* **Migration Version:** `20260912170000` (V1 Initial Production Schema)
* **PostgreSQL Version:** PostgreSQL 17
* **Supabase Compatibility:** Fully compatible with Supabase Auth (`auth.users`, `auth.uid()`), Supabase Realtime (Postgres Changes on `supabase_realtime` publication), and Supabase PostgREST RPC engine.
* **Execution Status:** **NOT EXECUTED REMOTELY**. No connection to remote Supabase, no `supabase db push`, no `supabase migration up`, no `psql` execution. All verification performed via local static analysis.

---

## 2. Schema Verification (12/12 Tables)

All 12 core tables defined in V2.2.3 are implemented in strict dependency order with complete constraints, types, and indexes:

| # | Table | Primary Key | Foreign Keys | Check Constraints / Invariants | Key Indexes |
|:--|:------|:------------|:-------------|:-------------------------------|:------------|
| 1 | `user_profiles` | `id` (UUID → `auth.users`) | `auth.users(id)` ON DELETE RESTRICT | `role IN ('super_admin', 'cashier', 'server')` | `idx_user_profiles_role`, `idx_user_profiles_active` |
| 2 | `store_settings` | `id` (UUID, singleton) | `updated_by` → `user_profiles(id)` | Singleton check, tax rate 0-100, cashier discount caps | Single row (`00000000-0000-0000-0000-000000000001`) |
| 3 | `categories` | `id` (UUID) | None | Unique name, unique slug | `idx_categories_display_order` |
| 4 | `menu_items` | `id` (UUID) | `category_id` → `categories(id)` | `base_price >= 0` | `idx_menu_items_category`, `idx_menu_items_active_available` (partial) |
| 5 | `restaurant_tables` | `id` (UUID) | None | `status IN ('available', 'occupied', 'reserved', 'inactive')`, `capacity > 0` | `idx_restaurant_tables_active_status` (partial) |
| 6 | `customers` | `id` (UUID) | None | `phone ~ '^[6-9][0-9]{9}$'` (canonical 10-digit Indian mobile) | `idx_customers_phone` (unique) |
| 7 | `orders` | `id` (UUID) | `table_id`, `customer_id`, `server_id` | `order_type IN ('dine_in', 'takeaway')`, `status IN ('open', 'served', 'completed', 'cancelled')`, table required for dine-in | `idx_orders_table_active` (partial unique: 1 active dine-in order per table), `idx_orders_status_date` |
| 8 | `order_items` | `id` (UUID) | `order_id` → `orders(id)`, `menu_item_id` | `quantity > 0`, `unit_price_snapshot >= 0`, `status IN ('ordered', 'served', 'cancelled')` | `idx_order_items_order_id`, `idx_order_items_status` |
| 9 | `bills` | `id` (UUID) | `order_id`, `cashier_id`, `settled_by`, `voided_by` | Unique bill_number, 1 bill per order, financial snapshots, `status IN ('unpaid', 'paid', 'voided')` | `idx_bills_business_date`, `idx_bills_status`, `idx_bills_order_id` |
| 10 | `payments` | `id` (UUID) | `bill_id`, `received_by`, `refunded_by` | `amount > 0`, `payment_method IN ('cash', 'upi', 'card')`, `status IN ('completed', 'refunded')`, cash tendered/change rules | `idx_payments_bill_id`, `idx_payments_status` |
| 11 | `bill_sequences` | `sequence_date` (DATE) | None | Primary key on `sequence_date`, atomic upsert | Internal sequencing table |
| 12 | `audit_logs` | `id` (UUID) | `user_id` → `user_profiles(id)` | Append-only audit trail with structured JSONB data | `idx_audit_logs_user_id`, `idx_audit_logs_entity`, `idx_audit_logs_created_at` |

---

## 3. Client RPC Verification (19/19 Functions)

All 19 client-callable business RPCs are defined with `SECURITY DEFINER`, strict parameter typing, and database-level permission validation:

| # | RPC Function Signature | Allowed Roles | Transaction & Concurrency Controls |
|:--|:-----------------------|:--------------|:-----------------------------------|
| 1 | `create_dine_in_order(UUID, TEXT)` | Any active staff | Locks `restaurant_tables FOR UPDATE`; 3-attempt atomic order number collision retry |
| 2 | `create_takeaway_order(TEXT, TEXT, TEXT)` | Any active staff | Optional customer normalization; 3-attempt atomic order number collision retry |
| 3 | `add_order_item(UUID, UUID, INTEGER, VARCHAR)` | Any active staff | Locks parent `orders FOR UPDATE`; verifies no bill exists; takes price/name/category snapshots |
| 4 | `update_order_item_quantity(UUID, INTEGER)` | Any active staff | Locks parent `orders FOR UPDATE`; verifies no bill exists; verifies item not served/cancelled |
| 5 | `cancel_order_item(UUID, TEXT)` | Any active staff | Locks parent `orders FOR UPDATE`; verifies no bill exists; soft-cancels item with reason |
| 6 | `transfer_table(UUID, UUID)` | Any active staff | Locks parent `orders FOR UPDATE`; locks source and destination tables in deterministic UUID order |
| 7 | `mark_order_served(UUID)` | Any active staff | Locks parent `orders FOR UPDATE`; marks active items served; transitions order to `served` |
| 8 | `cancel_order(UUID, TEXT)` | `cashier`, `super_admin` | Locks parent `orders FOR UPDATE`; verifies no bill exists; cancels items; frees table if dine-in |
| 9 | `generate_bill_for_order(UUID, VARCHAR, NUMERIC, VARCHAR)` | `cashier`, `super_admin` | Locks parent `orders FOR UPDATE` (requires `served` status); locks `store_settings FOR SHARE`; negative discount rejection; atomic bill sequence |
| 10 | `settle_bill(UUID, JSONB)` | `cashier`, `super_admin` | Locks `bills FOR UPDATE`; locks `orders FOR UPDATE`; verifies unpaid; exact sum check; atomic payment records; transitions order to `completed`; frees table |
| 11 | `void_bill(UUID, TEXT)` | `super_admin` only | Locks `bills FOR UPDATE`; locks `orders FOR UPDATE`; voids bill; marks payments refunded; cancels order; frees table |
| 12 | `create_category(VARCHAR, VARCHAR, INTEGER)` | `super_admin` only | Validates name/slug uniqueness; assigns display order |
| 13 | `update_category(UUID, VARCHAR, VARCHAR, INTEGER, BOOLEAN)` | `super_admin` only | Locks `categories FOR UPDATE`; partial update via COALESCE |
| 14 | `create_menu_item(UUID, VARCHAR, NUMERIC, TEXT, INTEGER, TEXT)` | `super_admin` only | Validates category; validates non-negative base price |
| 15 | `update_menu_item(UUID, VARCHAR, TEXT, NUMERIC, UUID, INTEGER, BOOLEAN, TEXT)` | `super_admin` only | Locks `menu_items FOR UPDATE`; partial update via COALESCE; price changes audited |
| 16 | `toggle_menu_item_availability(UUID)` | `cashier`, `super_admin` | Locks `menu_items FOR UPDATE`; toggles `is_available` |
| 17 | `update_user_role(UUID, VARCHAR)` | `super_admin` only | Prevents self-demotion; locks active superadmins using deterministic `ORDER BY id FOR UPDATE`; guards last active superadmin |
| 18 | `toggle_user_active(UUID)` | `super_admin` only | Prevents self-deactivation; locks active superadmins using deterministic `ORDER BY id FOR UPDATE`; guards last active superadmin |
| 19 | `update_store_settings(VARCHAR, VARCHAR, TEXT, VARCHAR, VARCHAR, VARCHAR, NUMERIC, BOOLEAN, VARCHAR, VARCHAR, TEXT, TEXT, VARCHAR, VARCHAR, NUMERIC, NUMERIC)` | `super_admin` only | Locks singleton `store_settings FOR UPDATE`; validates tax rate (0-100) and discount caps |

---

## 4. Internal Function Verification (11 Functions)

11 internal helper, security, and trigger functions support the schema:

| # | Function | Category | Purpose |
|:--|:---------|:---------|:--------|
| 1 | `is_staff()` | RLS Helper | Returns true if `auth.uid()` belongs to an active staff member |
| 2 | `is_super_admin()` | RLS Helper | Returns true if `auth.uid()` belongs to an active super_admin |
| 3 | `is_cashier_or_admin()` | RLS Helper | Returns true if `auth.uid()` belongs to an active cashier or super_admin |
| 4 | `get_current_user_role()` | Security Helper | Resolves active user role from `auth.uid()` (internal only) |
| 5 | `normalize_indian_phone(TEXT)` | Validation Helper | Validates and strips country/trunk prefixes to canonical 10 digits |
| 6 | `generate_order_number(VARCHAR)` | Business Helper | Generates format `ORD-YYYYMMDD-XXXX` with crypto-random entropy |
| 7 | `get_next_bill_number(VARCHAR)` | Financial Helper | Atomic UPSERT on `bill_sequences` returning `FC-YYYYMMDD-0001` |
| 8 | `trg_audit_user_profiles()` | Audit Trigger | Audits staff role and active status modifications |
| 9 | `trg_audit_store_settings()` | Audit Trigger | Audits configuration modifications to singleton store settings |
| 10 | `trg_audit_menu_items()` | Audit Trigger | Audits menu item price changes |
| 11 | `trg_set_updated_at()` | Utility Trigger | Automatically sets `updated_at = now()` on row update |

---

## 5. Function Privilege Matrix (30/30 Functions)

The database privilege model enforces strict zero-trust access control. Every function has deliberate, explicit grants and revokes:

| # | Function Name | Function Type | PUBLIC | anon | authenticated | Rationale |
|:--|:--------------|:--------------|:------:|:----:|:-------------:|:----------|
| 1 | `create_dine_in_order(UUID, TEXT)` | Client RPC | **NO** | **NO** | **YES** | Authenticated staff dine-in order creation |
| 2 | `create_takeaway_order(TEXT, TEXT, TEXT)` | Client RPC | **NO** | **NO** | **YES** | Authenticated staff takeaway order creation |
| 3 | `add_order_item(UUID, UUID, INTEGER, VARCHAR)` | Client RPC | **NO** | **NO** | **YES** | Authenticated staff item addition |
| 4 | `update_order_item_quantity(UUID, INTEGER)` | Client RPC | **NO** | **NO** | **YES** | Authenticated staff quantity update |
| 5 | `cancel_order_item(UUID, TEXT)` | Client RPC | **NO** | **NO** | **YES** | Authenticated staff item cancellation |
| 6 | `transfer_table(UUID, UUID)` | Client RPC | **NO** | **NO** | **YES** | Authenticated staff table transfer |
| 7 | `mark_order_served(UUID)` | Client RPC | **NO** | **NO** | **YES** | Authenticated staff order served transition |
| 8 | `cancel_order(UUID, TEXT)` | Client RPC | **NO** | **NO** | **YES** | Cashier / admin order cancellation |
| 9 | `generate_bill_for_order(UUID, VARCHAR, NUMERIC, VARCHAR)` | Client RPC | **NO** | **NO** | **YES** | Cashier / admin bill generation |
| 10 | `settle_bill(UUID, JSONB)` | Client RPC | **NO** | **NO** | **YES** | Cashier / admin payment settlement |
| 11 | `void_bill(UUID, TEXT)` | Client RPC | **NO** | **NO** | **YES** | Super admin bill void & payment refund |
| 12 | `create_category(VARCHAR, VARCHAR, INTEGER)` | Client RPC | **NO** | **NO** | **YES** | Super admin category management |
| 13 | `update_category(UUID, VARCHAR, VARCHAR, INTEGER, BOOLEAN)` | Client RPC | **NO** | **NO** | **YES** | Super admin category management |
| 14 | `create_menu_item(UUID, VARCHAR, NUMERIC, TEXT, INTEGER, TEXT)` | Client RPC | **NO** | **NO** | **YES** | Super admin menu management |
| 15 | `update_menu_item(UUID, VARCHAR, TEXT, NUMERIC, UUID, INTEGER, BOOLEAN, TEXT)` | Client RPC | **NO** | **NO** | **YES** | Super admin menu management |
| 16 | `toggle_menu_item_availability(UUID)` | Client RPC | **NO** | **NO** | **YES** | Cashier / admin availability toggle |
| 17 | `update_user_role(UUID, VARCHAR)` | Client RPC | **NO** | **NO** | **YES** | Super admin role management |
| 18 | `toggle_user_active(UUID)` | Client RPC | **NO** | **NO** | **YES** | Super admin staff activation |
| 19 | `update_store_settings(...)` | Client RPC | **NO** | **NO** | **YES** | Super admin store settings update |
| 20 | `is_staff()` | RLS Helper | **NO** | **NO** | **YES** | Required for RLS SELECT evaluation |
| 21 | `is_super_admin()` | RLS Helper | **NO** | **NO** | **YES** | Required for RLS SELECT evaluation |
| 22 | `is_cashier_or_admin()` | RLS Helper | **NO** | **NO** | **YES** | Required for RLS SELECT evaluation |
| 23 | `get_current_user_role()` | Internal Helper | **NO** | **NO** | **NO** | Internal execution only |
| 24 | `normalize_indian_phone(TEXT)` | Internal Helper | **NO** | **NO** | **NO** | Internal execution only |
| 25 | `generate_order_number(VARCHAR)` | Internal Helper | **NO** | **NO** | **NO** | Internal execution only |
| 26 | `get_next_bill_number(VARCHAR)` | Internal Helper | **NO** | **NO** | **NO** | Internal execution only |
| 27 | `trg_audit_user_profiles()` | Trigger Function | **NO** | **NO** | **NO** | Trigger execution only |
| 28 | `trg_audit_store_settings()` | Trigger Function | **NO** | **NO** | **NO** | Trigger execution only |
| 29 | `trg_audit_menu_items()` | Trigger Function | **NO** | **NO** | **NO** | Trigger execution only |
| 30 | `trg_set_updated_at()` | Trigger Function | **NO** | **NO** | **NO** | Trigger execution only |

---

## 6. RLS & Direct DML Matrix (12 Tables)

Direct client DML (INSERT, UPDATE, DELETE) is completely blocked on all application tables. All mutations must occur through the approved SECURITY DEFINER RPCs:

| Table | RLS Status | Client SELECT Policy | Direct Client DML (INSERT, UPDATE, DELETE) | Mutation Mechanism |
|:------|:-----------|:---------------------|:-------------------------------------------|:-------------------|
| `user_profiles` | ENABLED | `is_staff()` (all active staff) | **DENIED** (No policy; REVOKED) | RPC (`update_user_role`, `toggle_user_active`) |
| `store_settings` | ENABLED | `is_staff()` (all active staff) | **DENIED** (No policy; REVOKED) | RPC (`update_store_settings`) |
| `categories` | ENABLED | `is_staff()` (all active staff) | **DENIED** (No policy; REVOKED) | RPC (`create_category`, `update_category`) |
| `menu_items` | ENABLED | `is_staff()` (all active staff) | **DENIED** (No policy; REVOKED) | RPC (`create_menu_item`, `update_menu_item`, `toggle_menu_item_availability`) |
| `restaurant_tables` | ENABLED | `is_staff()` (all active staff) | **DENIED** (No policy; REVOKED) | RPC (`create_dine_in_order`, `transfer_table`, `settle_bill`, `cancel_order`) |
| `customers` | ENABLED | `is_staff()` (all active staff) | **DENIED** (No policy; REVOKED) | RPC (`create_takeaway_order`) |
| `orders` | ENABLED | `is_staff()` (all active staff) | **DENIED** (No policy; REVOKED) | RPC (`create_dine_in_order`, `create_takeaway_order`, `mark_order_served`, `cancel_order`, `settle_bill`, `void_bill`) |
| `order_items` | ENABLED | `is_staff()` (all active staff) | **DENIED** (No policy; REVOKED) | RPC (`add_order_item`, `update_order_item_quantity`, `cancel_order_item`, `mark_order_served`, `cancel_order`) |
| `bills` | ENABLED | `is_staff()` (all active staff) | **DENIED** (No policy; REVOKED) | RPC (`generate_bill_for_order`, `settle_bill`, `void_bill`) |
| `payments` | ENABLED | `is_staff()` (all active staff) | **DENIED** (No policy; REVOKED) | RPC (`settle_bill`, `void_bill`) |
| `bill_sequences` | ENABLED | **DENIED** (No policy; no grants) | **DENIED** (No policy; no grants) | Internal SECURITY DEFINER helper (`get_next_bill_number`) |
| `audit_logs` | ENABLED | `is_super_admin()` (admins only) | **DENIED** (No policy; REVOKED) | Append-only via triggers & RPCs |

> **Blocker 2 Resolution Note on `bill_sequences`:** `FORCE ROW LEVEL SECURITY` has been removed from `bill_sequences`. Because `bill_sequences` has `ENABLE ROW LEVEL SECURITY` with zero grants to `authenticated` or `anon` and zero policies, client access is completely blocked. Removing `FORCE` ensures that internal operations executing under the table owner (`postgres`) via `SECURITY DEFINER` functions (`get_next_bill_number`) succeed without being blocked by empty RLS policies.

---

## 7. Security Review

* **`SECURITY DEFINER` Hardening:** All 30 functions are declared `SECURITY DEFINER`.
* **`search_path` Isolation:** All 30 functions explicitly set `SET search_path = public, pg_temp` on the function header.
* **Actor Derivation:** Actor identity is strictly derived from `auth.uid()` in every business RPC (28 occurrences of `auth.uid()`). Client-supplied user/actor IDs are never trusted for authorization.
* **Service Role Exposure:** Scanned and verified. No occurrences of `service_role` or `SUPABASE_SERVICE_ROLE_KEY`.
* **Zero Secrets Detected:** No database passwords, JWT tokens, API keys, or private key blocks are contained in the migration.
* **Zero Dynamic SQL:** Scanned and verified. No dynamic SQL (`EXECUTE '...'`) is used anywhere in the migration.

---

## 8. Financial Integrity

* **Data Types:** All financial fields use exact fixed-point `NUMERIC(10,2)` (no float or double precision).
* **Tax-Inclusive Formula:**
  $$\text{discounted\_subtotal} = \text{subtotal} - \text{discount\_amount}$$
  $$\text{tax\_amount} = \text{ROUND}\left(\text{discounted\_subtotal} - \frac{\text{discounted\_subtotal}}{1 + \frac{\text{tax\_rate}}{100}}, 2\right)$$
  $$\text{raw\_total} = \text{discounted\_subtotal}$$
  *(Tax is extracted; it is NOT added back onto the total).*
* **Tax-Exclusive Formula:**
  $$\text{tax\_amount} = \text{ROUND}\left(\frac{\text{discounted\_subtotal} \times \text{tax\_rate}}{100}, 2\right)$$
  $$\text{raw\_total} = \text{discounted\_subtotal} + \text{tax\_amount}$$
* **Rounding:**
  $$\text{final\_amount} = \text{ROUND}(\text{raw\_total}, 0)$$
  $$\text{round\_off} = \text{final\_amount} - \text{raw\_total}$$
* **Negative Discount Rejection:** `generate_bill_for_order()` explicitly rejects negative discount values (`p_discount_value < 0` raises an exception). Discounts of 0 or NULL result in no discount. Discounts $> 0$ require a valid discount type (`percentage` or `flat`), enforce cashier limits, require a minimum 3-character reason, and are capped at the order subtotal.
* **Exact Settlement Matching:** `settle_bill()` verifies that the exact sum of payments equals `bill.final_amount`. Over-payment or under-payment raises an exception.
* **Cash Validation:** Cash payments require `cash_tendered >= amount`; change returned is calculated server-side as `cash_tendered - amount`. Non-cash payments enforce NULL for cash tendered/change fields.

---

## 9. Concurrency Controls

* **Parent Order Locking:** Modifying RPCs (`add_order_item`, `update_order_item_quantity`, `cancel_order_item`, `transfer_table`, `mark_order_served`, `cancel_order`, `generate_bill_for_order`, `settle_bill`, `void_bill`) lock the parent `orders` row using `FOR UPDATE`.
* **Bill Locking:** `settle_bill()` and `void_bill()` lock the target `bills` row using `FOR UPDATE`.
* **Table Transfer Lock Ordering:** `transfer_table()` acquires locks on source and destination `restaurant_tables` rows in ascending UUID order (`LEAST(p_order.table_id, p_new_table_id)` then `GREATEST`), eliminating table transfer deadlocks under concurrent execution.
* **Atomic Bill Sequences:** `get_next_bill_number()` utilizes `INSERT INTO bill_sequences ... ON CONFLICT (sequence_date) DO UPDATE SET last_number = last_number + 1 RETURNING last_number`, guaranteeing collision-free, unique daily bill numbers.
* **Order Number Collision Protection (Hardening 3):** `create_dine_in_order()` and `create_takeaway_order()` wrap the order number generation and INSERT in a 3-attempt loop protected by a PL/pgSQL `EXCEPTION WHEN unique_violation THEN` block. If a concurrent race condition occurs, the subtransaction rolls back, the loop retries with a fresh crypto-random suffix, and only raises an exception if all 3 attempts collide.
* **Deterministic Super Admin Locks (Hardening 6):** `update_user_role()` and `toggle_user_active()` lock all active superadmin rows using `ORDER BY id FOR UPDATE`. This guarantees a deterministic lock order across concurrent administrative transactions, preventing deadlocks while guaranteeing that the last active super_admin can never be demoted or deactivated.

---

## 10. Lifecycle Semantics

### Order Lifecycle
$$\text{open} \longrightarrow \text{served} \longrightarrow \text{completed}$$
$$\text{open} \ / \ \text{served} \longrightarrow \text{cancelled}$$

* **Order Creation:** Orders start in `open` status.
* **Order Served:** When items are delivered, staff calls `mark_order_served()`, marking active items and the order as `served`.
* **Order Billed (Hardening 5 Decision):** `generate_bill_for_order()` requires the order to be in `served` status. It does NOT silently change `open → served`. An unserved order must be marked served before a bill can be generated. While the bill remains `unpaid`, the order stays in `served` status.
* **Order Completion:** When `settle_bill()` completes payment, the order transitions from `served` to `completed`, and the table is released.
* **Order Cancellation:** An unbilled order can be cancelled directly via `cancel_order()`. A billed order must be voided via `void_bill()`, which automatically cancels the parent order and refunds payments.

### Bill Lifecycle
$$\text{unpaid} \longrightarrow \text{paid}$$
$$\text{unpaid} \longrightarrow \text{voided}$$
$$\text{paid} \longrightarrow \text{voided}$$

* **Bill Generation:** Creates an `unpaid` bill with complete historical financial snapshots.
* **Settlement:** `settle_bill()` transitions an `unpaid` bill to `paid`.
* **Voiding:** `void_bill()` can void either an `unpaid` bill or a `paid` bill. If the bill was paid, all associated payments are updated to `refunded` with timestamp, reason, and actor ID.

---

## 11. Audit Coverage (21/21 Events)

The audit log captures 21 discrete operational events:

| # | Event Action | Triggering Operation | Source |
|:--|:-------------|:---------------------|:-------|
| 1 | `USER_ROLE_CHANGED` | Role assignment / demotion | Trigger `trg_audit_user_profiles` |
| 2 | `USER_STATUS_CHANGED` | Staff activation / deactivation | Trigger `trg_audit_user_profiles` |
| 3 | `CATEGORY_CREATED` | New menu category | RPC `create_category` |
| 4 | `CATEGORY_UPDATED` | Category edit | RPC `update_category` |
| 5 | `MENU_ITEM_CREATED` | New menu item | RPC `create_menu_item` |
| 6 | `MENU_ITEM_UPDATED` | Menu item edit | RPC `update_menu_item` |
| 7 | `MENU_ITEM_PRICE_CHANGED` | Base price change | Trigger `trg_audit_menu_items` |
| 8 | `MENU_ITEM_AVAILABILITY_CHANGED` | Availability toggle | RPC `toggle_menu_item_availability` |
| 9 | `ORDER_CREATED` | New dine-in or takeaway order | RPC `create_dine_in_order`, `create_takeaway_order` |
| 10 | `ORDER_ITEM_ADDED` | Item added to order | RPC `add_order_item` |
| 11 | `ORDER_ITEM_QUANTITY_CHANGED` | Item quantity adjusted | RPC `update_order_item_quantity` |
| 12 | `ORDER_ITEM_CANCELLED` | Item cancelled | RPC `cancel_order_item` |
| 13 | `ORDER_SERVED` | Order marked served | RPC `mark_order_served` |
| 14 | `TABLE_TRANSFERRED` | Dine-in table transferred | RPC `transfer_table` |
| 15 | `ORDER_CANCELLED` | Order cancelled | RPC `cancel_order` |
| 16 | `BILL_GENERATED` | Bill created | RPC `generate_bill_for_order` |
| 17 | `DISCOUNT_APPLIED` | Discount applied to bill | RPC `generate_bill_for_order` |
| 18 | `BILL_SETTLED` | Bill paid | RPC `settle_bill` |
| 19 | `BILL_VOIDED` | Bill voided | RPC `void_bill` |
| 20 | `PAYMENT_REFUNDED` | Payments refunded on void | RPC `void_bill` |
| 21 | `SETTINGS_UPDATED` | Store settings modified | Trigger `trg_audit_store_settings` |

---

## 12. Realtime Configuration

* **Engine:** Supabase Realtime via Postgres Changes (NOT broadcast).
* **Publication:** `supabase_realtime` publication configured for operational tables:
  - `orders`
  - `order_items`
  - `bills`
* **Replica Identity:** Set to `FULL` on `orders`, `order_items`, and `bills`.
* **Important Notice:**
  ```text
  Postgres Changes configured in migration.
  Runtime RLS/subscription behavior requires post-migration verification.
  ```

---

## 13. Thermal Printing Architecture

The physical printing sequence follows the strict post-commit pattern:

```text
database transaction commits first
        ↓
Flutter receives success
        ↓
thermal printing occurs
        ↓
reprint available if printer failure occurs
```

Printing failures never roll back financial transactions. Bills and orders remain safely committed in the database, with reprint capabilities available on POS terminals.

---

## 14. Remaining Owner Decisions (Preserved from V2.2.3)

The following 7 business owner decisions are intentionally preserved with conservative V1 seed defaults and require explicit owner confirmation:

1. **GST registration:** Currently defaults to unregistered (`gstin = NULL`).
2. **GST/tax rate:** Currently defaults to `5.00%` (restaurant standard).
3. **Tax inclusive/exclusive:** Currently defaults to `true` (tax-inclusive pricing).
4. **Cashier discount percentage cap:** Currently defaults to `10.00%`.
5. **Cashier discount rupee cap:** Currently defaults to `₹200.00`.
6. **Integer rupee rounding:** Currently enabled (`final_amount = ROUND(raw_total, 0)`).
7. **Takeaway vs parcel terminology:** Configured as `takeaway` in database schema.

---

## 15. Static Verification Results

| # | Static Verification Item | Expected | Actual | Result |
|:--|:-------------------------|:---------|:-------|:-------|
| 1 | Table Count | 12 | 12 | ✅ PASS |
| 2 | Client RPC Count | 19 | 19 | ✅ PASS |
| 3 | Helper & Trigger Function Count | 11 | 11 | ✅ PASS |
| 4 | Total Functions | 30 | 30 | ✅ PASS |
| 5 | `SECURITY DEFINER` on all functions | 30 | 30 | ✅ PASS |
| 6 | `SET search_path = public, pg_temp` | 30 | 30 | ✅ PASS |
| 7 | Secret & Credential Scan | 0 secrets | 0 detected | ✅ PASS |
| 8 | `FORCE ROW LEVEL SECURITY` Count | 0 | 0 | ✅ PASS (Blocker 2 Fixed) |
| 9 | Explicit `PUBLIC` Revokes on RPCs | 19 | 19 | ✅ PASS (Blocker 1 Fixed) |
| 10 | Explicit `anon` Revokes on RPCs | 19 | 19 | ✅ PASS |
| 11 | Explicit `authenticated` Grants on RPCs | 19 | 19 | ✅ PASS |
| 12 | Negative Discount Validation | Exception raised on `< 0` | Implemented | ✅ PASS (Hardening 4 Fixed) |
| 13 | Order Number Collision Retry | 3-attempt exception loop | Implemented in RPC 1 & 2 | ✅ PASS (Hardening 3 Fixed) |
| 14 | Bill Generation Order Status | Requires `served` status | Implemented in RPC 9 | ✅ PASS (Hardening 5 Fixed) |
| 15 | Superadmin Lock Order | `ORDER BY id FOR UPDATE` | Implemented in RPC 17 & 18 | ✅ PASS (Hardening 6 Fixed) |
| 16 | Reporting Views Zero-Trust Revokes | Revoked from `PUBLIC, anon` | Implemented on all 4 views | ✅ PASS |

---

## 16. Final Verdict

```text
READY FOR SQL EXECUTION REVIEW
```
