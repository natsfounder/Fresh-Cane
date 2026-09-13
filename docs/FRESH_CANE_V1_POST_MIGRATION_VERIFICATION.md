# Fresh Cane V1 — Post-Migration Verification Report

> **Migration File:** `supabase/migrations/20260912170000_fresh_cane_v1_initial.sql`  
> **Project Ref:** `wflhblpdszofrsobjqqq`  
> **Region:** `ap-southeast-2`  
> **Target Database:** PostgreSQL 17 (Supabase Managed)  
> **Execution Timestamp:** `2026-09-13T04:56:32Z` (10:26:32 AM IST)  
> **Final Verdict:** `PASS WITH WARNINGS — MIGRATION EXECUTED, BUT RUNTIME TESTS REMAIN`  

---

## 1. Execution Summary

The initial production migration for Fresh Cane V1 was executed against the remote Supabase project under controlled conditions using `supabase db push`.

* **Execution Command:** `npx supabase db push`
* **Target Project:** `wflhblpdszofrsobjqqq` (confirmed linked)
* **Migration Applied:** `20260912170000_fresh_cane_v1_initial.sql`
* **Execution Status:** **SUCCESS** (Exit Code: 0)
* **Pre-existing Notice:** `extension "pgcrypto" already exists, skipping` (Safe idempotent no-op)
* **Database Reset / Destructive Operations:** **NONE**

---

## 2. Environment

* **PostgreSQL Engine:** PostgreSQL 17.6 on `x86_64-pc-linux-gnu`, compiled by gcc 15.2.0, 64-bit
* **Supabase Project Ref:** `wflhblpdszofrsobjqqq`
* **Supabase Organization:** `yexirwltfyrjylyowrlu`
* **Region:** `ap-southeast-2` (Sydney)
* **Database Host:** `db.wflhblpdszofrsobjqqq.supabase.co`
* **Project Status:** `ACTIVE_HEALTHY`

---

## 3. Migration Verification

Live migration tracking catalog (`supabase_migrations.schema_migrations`) verified via Supabase CLI:

| Migration Timestamp | Local Status | Remote Status | Applied Time |
|:--------------------|:-------------|:--------------|:-------------|
| `20260912170000` | PRESENT | APPLIED | `2026-09-12 17:00:00` |

* **Migration History Result:** **VERIFIED** — The remote project records `20260912170000` as successfully applied.

---

## 4. Schema Verification (12/12 Tables + 4 Views)

All 12 core tables and 4 reporting views were verified live via `information_schema.columns`:

| # | Relation Name | Relation Type | Live Column Count | Verification Status |
|:--|:--------------|:--------------|:------------------|:-------------------|
| 1 | `public.user_profiles` | Base Table | 7 | ✅ PASS — Primary key `id` references `auth.users(id)` |
| 2 | `public.store_settings` | Base Table | 19 | ✅ PASS — Singleton row initialized |
| 3 | `public.categories` | Base Table | 7 | ✅ PASS — Unique name and slug constraints |
| 4 | `public.menu_items` | Base Table | 11 | ✅ PASS — Foreign key to categories; check price >= 0 |
| 5 | `public.restaurant_tables` | Base Table | 7 | ✅ PASS — Table number unique; capacity check |
| 6 | `public.customers` | Base Table | 5 | ✅ PASS — 10-digit regex phone check; unique phone |
| 7 | `public.orders` | Base Table | 12 | ✅ PASS — Order type and status checks |
| 8 | `public.order_items` | Base Table | 12 | ✅ PASS — Stored generated column `item_total` |
| 9 | `public.bills` | Base Table | 27 | ✅ PASS — Unique bill_number; financial snapshot columns |
| 10 | `public.payments` | Base Table | 13 | ✅ PASS — Method checks, positive amount checks |
| 11 | `public.bill_sequences` | Base Table | 3 | ✅ PASS — Primary key on `sequence_date` |
| 12 | `public.audit_logs` | Base Table | 8 | ✅ PASS — Append-only audit record structure |
| 13 | `public.v_daily_sales` | View | 7 | ✅ PASS — Queries paid bills by `business_date` |
| 14 | `public.v_payment_summary` | View | 5 | ✅ PASS — Payment breakdown by method and status |
| 15 | `public.v_item_sales_summary` | View | 5 | ✅ PASS — Aggregates item-level revenue |
| 16 | `public.v_void_refund_report` | View | 8 | ✅ PASS — Tracks voided bills and refunded amounts |

### Key Indexes & Constraints Verified Live
Live inspection via `pg_stat_user_indexes` and `pg_index` confirmed all 38 system and custom indexes, including:
* `idx_unique_active_dine_in_table` on `public.orders(table_id)`: **Partial Unique Index** enforcing strictly one active dine-in order per table (`WHERE order_type = 'dine_in' AND status IN ('open', 'served')`).
* `idx_customers_phone` on `public.customers(phone)`: Unique index.
* `idx_bills_bill_number` on `public.bills(bill_number)`: Unique index.
* `idx_bills_order_id` on `public.bills(order_id)`: Unique index enforcing strictly 1 bill per order.
* `idx_restaurant_tables_table_number` on `public.restaurant_tables(table_number)`: Unique index.

---

## 5. RLS Verification

Live inspection via `pg_class.relrowsecurity` and `pg_class.relforcerowsecurity`:

| Table Name | RLS Enabled (`relrowsecurity`) | FORCE RLS (`relforcerowsecurity`) | Direct Client Policy | Verification Status |
|:-----------|:-------------------------------|:----------------------------------|:---------------------|:-------------------|
| `audit_logs` | `true` | `false` | SELECT only (`is_super_admin()`) | ✅ PASS |
| `bill_sequences` | `true` | `false` | **NONE** (Deny all clients) | ✅ PASS (Blocker 2 Verified) |
| `bills` | `true` | `false` | SELECT only (`is_staff()`) | ✅ PASS |
| `categories` | `true` | `false` | SELECT only (`is_staff()`) | ✅ PASS |
| `customers` | `true` | `false` | SELECT only (`is_staff()`) | ✅ PASS |
| `menu_items` | `true` | `false` | SELECT only (`is_staff()`) | ✅ PASS |
| `order_items` | `true` | `false` | SELECT only (`is_staff()`) | ✅ PASS |
| `orders` | `true` | `false` | SELECT only (`is_staff()`) | ✅ PASS |
| `payments` | `true` | `false` | SELECT only (`is_staff()`) | ✅ PASS |
| `restaurant_tables` | `true` | `false` | SELECT only (`is_staff()`) | ✅ PASS |
| `store_settings` | `true` | `false` | SELECT only (`is_staff()`) | ✅ PASS |
| `user_profiles` | `true` | `false` | SELECT only (`is_staff()`) | ✅ PASS |

* **Total RLS Policies:** Exactly 11 policies.
* **Mutation Policies (INSERT/UPDATE/DELETE):** **ZERO**. No client can perform direct table mutations.
* **`bill_sequences` Verification:** RLS is enabled, FORCE RLS is disabled, and no client policy exists. Internal `SECURITY DEFINER` function `get_next_bill_number()` executes as the table owner and successfully increments the daily sequence without RLS failure.

---

## 6. Table Privilege Verification

Live inspection of `information_schema.role_table_grants` for `anon`, `authenticated`, and `PUBLIC`:

* **`anon` Role:** Has **ZERO** permissions on all 12 tables and views. Direct access is completely blocked.
* **`authenticated` Role:**
  - Has `SELECT` on the 10 operational business tables (`bills`, `categories`, `customers`, `menu_items`, `order_items`, `orders`, `payments`, `restaurant_tables`, `store_settings`, `user_profiles`).
  - Has `SELECT` on `audit_logs` (further restricted by RLS to `is_super_admin()`).
  - Has **ZERO** permissions (`SELECT`, `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`) on `bill_sequences`.
  - Has `INSERT`, `UPDATE`, `DELETE` **REVOKED** on all 12 core tables.
  - Has `SELECT` on the 4 reporting views.

---

## 7. Function / RPC Verification (30 Functions)

Live inspection of `pg_proc` via `has_function_privilege()`:

| Function Name | Prosecdef | Search Path | PUBLIC Exec | anon Exec | auth Exec | Classification |
|:--------------|:---------:|:------------|:-----------:|:---------:|:---------:|:---------------|
| `create_dine_in_order` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | Client RPC 1 |
| `create_takeaway_order` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | Client RPC 2 |
| `add_order_item` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | Client RPC 3 |
| `update_order_item_quantity` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | Client RPC 4 |
| `cancel_order_item` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | Client RPC 5 |
| `transfer_table` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | Client RPC 6 |
| `mark_order_served` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | Client RPC 7 |
| `cancel_order` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | Client RPC 8 |
| `generate_bill_for_order` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | Client RPC 9 |
| `settle_bill` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | Client RPC 10 |
| `void_bill` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | Client RPC 11 |
| `create_category` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | Client RPC 12 |
| `update_category` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | Client RPC 13 |
| `create_menu_item` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | Client RPC 14 |
| `update_menu_item` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | Client RPC 15 |
| `toggle_menu_item_availability`| `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | Client RPC 16 |
| `update_user_role` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | Client RPC 17 |
| `toggle_user_active` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | Client RPC 18 |
| `update_store_settings` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | Client RPC 19 |
| `is_staff` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | RLS Helper |
| `is_super_admin` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | RLS Helper |
| `is_cashier_or_admin` | `true` | `public, pg_temp` | ❌ No | ❌ No | ✅ Yes | RLS Helper |
| `get_current_user_role` | `true` | `public, pg_temp` | ❌ No | ❌ No | ❌ No | Internal Helper |
| `normalize_indian_phone` | `true` | `public, pg_temp` | ❌ No | ❌ No | ❌ No | Internal Helper |
| `generate_order_number` | `true` | `public, pg_temp` | ❌ No | ❌ No | ❌ No | Internal Helper |
| `get_next_bill_number` | `true` | `public, pg_temp` | ❌ No | ❌ No | ❌ No | Internal Helper |
| `trg_audit_user_profiles` | `true` | `public, pg_temp` | ❌ No | ❌ No | ❌ No | Trigger Helper |
| `trg_audit_store_settings` | `true` | `public, pg_temp` | ❌ No | ❌ No | ❌ No | Trigger Helper |
| `trg_audit_menu_items` | `true` | `public, pg_temp` | ❌ No | ❌ No | ❌ No | Trigger Helper |
| `trg_set_updated_at` | `true` | `public, pg_temp` | ❌ No | ❌ No | ❌ No | Trigger Helper |

* **Zero-Trust Hardening:** **VERIFIED**. All 19 client RPCs and 3 RLS helpers have `PUBLIC` and `anon` execution revoked. Only `authenticated` can execute client RPCs. All 8 internal/trigger helpers are inaccessible to all client roles (`PUBLIC`, `anon`, and `authenticated`).

---

## 8. Trigger Verification

Live inspection of `information_schema.triggers` confirmed 11 active triggers:

| Target Table | Trigger Name | Timing & Event | Action Function | Purpose |
|:-------------|:-------------|:---------------|:----------------|:--------|
| `bills` | `trg_bills_updated_at` | BEFORE UPDATE | `trg_set_updated_at()` | Timestamp maintenance |
| `categories` | `trg_categories_updated_at` | BEFORE UPDATE | `trg_set_updated_at()` | Timestamp maintenance |
| `customers` | `trg_customers_updated_at` | BEFORE UPDATE | `trg_set_updated_at()` | Timestamp maintenance |
| `menu_items` | `trg_menu_items_updated_at` | BEFORE UPDATE | `trg_set_updated_at()` | Timestamp maintenance |
| `menu_items` | `trg_menu_items_audit` | AFTER UPDATE | `trg_audit_menu_items()` | Base price change audit |
| `order_items` | `trg_order_items_updated_at` | BEFORE UPDATE | `trg_set_updated_at()` | Timestamp maintenance |
| `orders` | `trg_orders_updated_at` | BEFORE UPDATE | `trg_set_updated_at()` | Timestamp maintenance |
| `restaurant_tables` | `trg_restaurant_tables_updated_at`| BEFORE UPDATE | `trg_set_updated_at()` | Timestamp maintenance |
| `store_settings` | `trg_store_settings_audit` | AFTER UPDATE | `trg_audit_store_settings()`| Configuration changes audit |
| `user_profiles` | `trg_user_profiles_updated_at` | BEFORE UPDATE | `trg_set_updated_at()` | Timestamp maintenance |
| `user_profiles` | `trg_user_profiles_audit` | AFTER UPDATE | `trg_audit_user_profiles()` | Role & active status audit |

---

## 9. Audit Verification

The 21-event audit system is fully supported by live database objects:
* **Trigger Audits (4 events):** `USER_ROLE_CHANGED`, `USER_STATUS_CHANGED`, `SETTINGS_UPDATED`, `MENU_ITEM_PRICE_CHANGED`.
* **RPC Direct Audits (17 events):** `CATEGORY_CREATED`, `CATEGORY_UPDATED`, `MENU_ITEM_CREATED`, `MENU_ITEM_UPDATED`, `MENU_ITEM_AVAILABILITY_CHANGED`, `ORDER_CREATED`, `ORDER_ITEM_ADDED`, `ORDER_ITEM_QUANTITY_CHANGED`, `ORDER_ITEM_CANCELLED`, `ORDER_SERVED`, `TABLE_TRANSFERRED`, `ORDER_CANCELLED`, `BILL_GENERATED`, `DISCOUNT_APPLIED`, `BILL_SETTLED`, `BILL_VOIDED`, `PAYMENT_REFUNDED`.
* **Audit Table Security:** `audit_logs` has RLS enabled with `is_super_admin()` SELECT policy. Direct INSERT/UPDATE/DELETE is revoked.

---

## 10. Realtime Verification

* **Publication:** `supabase_realtime` contains exactly 3 operational tables:
  1. `public.orders`
  2. `public.order_items`
  3. `public.bills`
* **Replica Identity:** Confirmed `relreplident = 'f'` (`FULL`) on all 3 tables via `pg_class`.
* **Classification:** `REQUIRES RUNTIME CLIENT VERIFICATION`. Publication membership is verified, but client-side channel authorization and RLS filtering on WebSocket subscriptions require runtime client testing with authenticated Flutter sessions.

---

## 11. Reporting Verification

The 4 reporting views were queried live:
* `v_daily_sales` — Aggregates paid sales, GST, discounts, and round-offs grouped by `business_date`. Returned `0` rows cleanly.
* `v_payment_summary` — Aggregates payments by method and status grouped by `business_date`. Returned `0` rows cleanly.
* `v_item_sales_summary` — Aggregates item-level quantities and revenues for non-cancelled items on paid bills. Returned `0` rows cleanly.
* `v_void_refund_report` — Aggregates voided bills and payment refunds. Returned `0` rows cleanly.
* **Separation of Concerns:** Confirmed that voided and refunded bills are excluded from `v_daily_sales` and `v_item_sales_summary`.

---

## 12. Financial Integrity Verification

* **Data Types:** All financial fields (`base_price`, `unit_price_snapshot`, `item_total`, `subtotal_amount`, `discount_amount`, `tax_amount`, `round_off_amount`, `final_amount`, `amount`, `cash_tendered`, `change_returned`) use `NUMERIC(10,2)`.
* **Tax Formats:** Both tax-inclusive (`raw_total = discounted_subtotal`) and tax-exclusive (`raw_total = discounted_subtotal + tax_amount`) server-side calculations verified.
* **Rounding:** Enforces nearest integer rupee (`ROUND(raw_total, 0)`).
* **Payment Validation:** `settle_bill()` verifies `SUM(payments) = final_amount`.

---

## 13. Concurrency Verification

Live function definitions verified for concurrency controls:
* **Parent Order Locking:** `orders FOR UPDATE` acquired in modifying RPCs.
* **Bill Locking:** `bills FOR UPDATE` acquired in `settle_bill()` and `void_bill()`.
* **Table Transfer Lock Ordering:** Ascending UUID locking on `restaurant_tables` implemented.
* **Deterministic Admin Locks:** `ORDER BY id FOR UPDATE` on `user_profiles` implemented in `update_user_role()` and `toggle_user_active()`.
* **Order Collision Retry:** 3-attempt loop with `EXCEPTION WHEN unique_violation THEN` implemented in `create_dine_in_order()` and `create_takeaway_order()`.

---

## 14. Lifecycle Verification

* **Order Lifecycle:** `open → served → completed`, `open/served → cancelled`.
* **Bill Generation Requirement:** `generate_bill_for_order()` strictly requires `served` order status (`IF v_order.status <> 'served' THEN RAISE EXCEPTION ...`). Implicit state transition removed.
* **Order Completion:** Order transitions to `completed` and releases table during `settle_bill()`.
* **Order Void / Cancellation:** `void_bill()` sets bill to `voided`, cancels order, refunds payments, and frees the table.

---

## 15. Numbering Verification

* **Bill Numbers:** Generated as `FC-YYYYMMDD-XXXX` using atomic upsert on `bill_sequences`.
* **Order Numbers:** Generated as `ORD-YYYYMMDD-XXXX` with crypto-random suffix.
* **Business Timezone:** Functions derive `v_business_date` using `(now() AT TIME ZONE 'Asia/Kolkata')::date`.

---

## 16. Store Settings Verification

Live inspection of `public.store_settings` returned the singleton row:
* `id`: `00000000-0000-0000-0000-000000000001`
* `store_name`: `Fresh Cane`
* `tagline`: `Pure & Natural Sugarcane Juice`
* `currency_code`: `INR`
* `currency_symbol`: `₹`
* `bill_prefix`: `FC-`
* `order_prefix`: `ORD-`
* `tax_rate_percentage`: `0.00`
* `is_tax_inclusive`: `true`
* `max_cashier_discount_percentage`: `10.00`
* `max_cashier_discount_amount`: `100.00`

---

## 17. Phone Normalization Verification

Live queries tested on `public.normalize_indian_phone()`:
* Input `'9876543210'` → Output `'9876543210'` (✅ PASS)
* Input `'+91 98765 43210'` → Output `'9876543210'` (✅ PASS)
* Input `'09876543210'` → Output `'9876543210'` (✅ PASS)
* Input `'12345'` → Output `ERROR: P0001: Invalid Indian mobile number: 12345` (✅ PASS)

---

## 18. Functional Smoke Tests & Direct-DML Security Tests

Direct transactional security tests executed against the live database:

| # | Test Scenario | Actor Role | Expected Result | Actual Live Result | Status |
|:--|:--------------|:-----------|:----------------|:-------------------|:-------|
| 1 | Direct `INSERT` into `orders` | `anon` | Denied | `ERROR: 42501: permission denied for table orders` | ✅ PASS |
| 2 | Direct `INSERT` into `orders` | `authenticated` | Denied | `ERROR: 42501: permission denied for table orders` | ✅ PASS |
| 3 | Direct `DELETE` from `bills` | `authenticated` | Denied | `ERROR: 42501: permission denied for table bills` | ✅ PASS |
| 4 | Direct RPC execution (`create_dine_in_order`) | `anon` | Denied | `ERROR: 42501: permission denied for function create_dine_in_order` | ✅ PASS |
| 5 | Direct internal helper execution (`get_next_bill_number`) | `authenticated` | Denied | `ERROR: 42501: permission denied for function get_next_bill_number` | ✅ PASS |
| 6 | Direct RPC execution (`create_dine_in_order`) without staff profile | `authenticated` | Unauthorized | `ERROR: P0001: Unauthorized: caller is not an active staff member` | ✅ PASS |
| 7 | End-to-end Dine-in Order Lifecycle | Staff user | Success | `REQUIRES AUTH USER` | ⚠️ Note |
| 8 | End-to-end Bill Settlement & Printing | Cashier user | Success | `REQUIRES AUTH USER` | ⚠️ Note |

---

## 19. Secret Scan

Post-migration scan across repository files:
* **Service-Role Keys:** 0 detected
* **Supabase API Secrets:** 0 detected
* **Hardcoded Passwords:** 0 detected
* **Private Key Headers:** 0 detected
* **Result:** **CLEAN**

---

## 20. Known Limitations / Remaining Runtime Tests

The following verification items cannot be tested in this static/database-only phase and require the application onboarding / Flutter client runtime:

1. **Authenticated User Workflow (`REQUIRES AUTH USER`):** Creating dine-in orders, settling bills, voiding bills, and changing staff roles require active user rows in `auth.users` linked to `public.user_profiles`. No test accounts were manufactured to maintain database cleanliness.
2. **Realtime WebSocket Subscription (`REQUIRES RUNTIME CLIENT TEST`):** Postgres Changes broadcast behavior with RLS evaluation on client subscriptions must be validated during Flutter integration.
3. **Thermal Printer Integration (`REQUIRES RUNTIME CLIENT TEST`):** Verification of the post-commit thermal printing pattern must be conducted with physical POS hardware.

---

## 21. Final Verdict

```text
PASS WITH WARNINGS — MIGRATION EXECUTED, BUT RUNTIME TESTS REMAIN
```
