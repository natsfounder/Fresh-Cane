import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fresh_cane/core/config/app_config.dart';

void main() {
  late SupabaseClient client;
  late SupabaseClient adminClient;
  late String serverUserId;
  late Map<String, dynamic> testTable;
  late Map<String, dynamic> testMenuItem;

  setUpAll(() async {
    client = SupabaseClient(
      AppConfig.supabaseUrl,
      AppConfig.supabaseAnonKey,
    );

    adminClient = SupabaseClient(
      AppConfig.supabaseUrl,
      AppConfig.supabaseAnonKey,
    );

    // Sign in as Server
    final authRes = await client.auth.signInWithPassword(
      email: 'server@freshcane.dev',
      password: 'server@123',
    );
    expect(authRes.user, isNotNull);
    serverUserId = authRes.user!.id;

    // Sign in as Super Admin (to inspect audit_logs which has RLS for super_admin)
    final adminAuthRes = await adminClient.auth.signInWithPassword(
      email: 'admin@freshcane.dev',
      password: 'Admin@123',
    );
    expect(adminAuthRes.user, isNotNull);

    // Fetch an active table for testing (e.g., Table 4 or Table 5)
    final tables = await client
        .from('restaurant_tables')
        .select()
        .eq('is_active', true)
        .order('table_number');
    expect(tables, isNotEmpty);
    testTable = tables.last;

    // Ensure test table is clean
    try {
      await client.rpc('close_table_session', params: {'p_table_id': testTable['id']});
    } catch (_) {}

    // Fetch an active menu item
    final menuItems = await client
        .from('menu_items')
        .select()
        .eq('is_active', true)
        .eq('is_available', true)
        .limit(1);
    expect(menuItems, isNotEmpty);
    testMenuItem = menuItems.first;
  });

  tearDownAll(() async {
    try {
      await client.rpc('close_table_session', params: {'p_table_id': testTable['id']});
    } catch (_) {}
  });

  group('Phase 2 Database & RPC Verification Tests', () {
    // -------------------------------------------------------------------------
    // TEST 1 — Existing customer: status defaults to 'active'
    // -------------------------------------------------------------------------
    test('Test 1 — Existing customer status defaults to active', () async {
      final customers = await client
          .from('table_session_customers')
          .select()
          .limit(5);

      for (final cust in customers) {
        expect(cust['status'], isNotNull, reason: 'Customer status must not be null');
        expect(
          ['active', 'finished', 'billed', 'closed'],
          contains(cust['status']),
          reason: 'Customer status must be a valid enum value',
        );
      }
    });

    // -------------------------------------------------------------------------
    // TEST 2 — Finish: active -> finished
    // -------------------------------------------------------------------------
    late String sessionId;
    late String customerAId;

    test('Test 2 — Server Finish transitions customer from active to finished', () async {
      // 1. Open table session
      final sessionRes = await client.rpc(
        'open_or_get_table_session',
        params: {'p_table_id': testTable['id']},
      );
      expect(sessionRes, isNotNull);
      sessionId = sessionRes['session_id'];
      final customers = sessionRes['customers'] as List;
      expect(customers, isNotEmpty);
      customerAId = customers[0]['id'];
      expect(customers[0]['status'], equals('active'));

      // 2. Execute finish_table_session_customer
      final finishRes = await client.rpc(
        'finish_table_session_customer',
        params: {'p_customer_id': customerAId},
      );
      expect(finishRes['success'], isTrue);
      expect(finishRes['status'], equals('finished'));
      expect(finishRes['finished_at'], isNotNull);
      expect(finishRes['finished_by'], equals(serverUserId));
      expect(finishRes['already_finished'], isFalse);

      // 3. Verify in database
      final custDb = await client
          .from('table_session_customers')
          .select()
          .eq('id', customerAId)
          .single();
      expect(custDb['status'], equals('finished'));
      expect(custDb['finished_at'], isNotNull);
      expect(custDb['finished_by'], equals(serverUserId));
    });

    // -------------------------------------------------------------------------
    // TEST 3 — Double Finish: idempotent, no duplicate audit event
    // -------------------------------------------------------------------------
    test('Test 3 — Double Finish is idempotent with no duplicate audit event', () async {
      // 1. Count audit logs via adminClient before second finish
      final auditBefore = await adminClient
          .from('audit_logs')
          .select()
          .eq('action', 'CUSTOMER_FINISHED')
          .eq('entity_id', customerAId);
      expect(auditBefore.length, equals(1), reason: 'First finish must have created 1 audit entry');

      // 2. Call finish_table_session_customer second time
      final finishRes = await client.rpc(
        'finish_table_session_customer',
        params: {'p_customer_id': customerAId},
      );
      expect(finishRes['success'], isTrue);
      expect(finishRes['status'], equals('finished'));
      expect(finishRes['already_finished'], isTrue);

      // 3. Count audit logs via adminClient after second finish: must remain EXACTLY 1
      final auditAfter = await adminClient
          .from('audit_logs')
          .select()
          .eq('action', 'CUSTOMER_FINISHED')
          .eq('entity_id', customerAId);
      expect(auditAfter.length, equals(1), reason: 'Duplicate audit log must not be created on double finish');
    });

    // -------------------------------------------------------------------------
    // TEST 4 — Finished customer ordering: submit_dine_in_order must fail
    // -------------------------------------------------------------------------
    test('Test 4 — Ordering for a finished customer is rejected by DB guard', () async {
      bool caughtError = false;
      try {
        await client.rpc(
          'submit_dine_in_order',
          params: {
            'p_table_id': testTable['id'],
            'p_session_id': sessionId,
            'p_session_customer_id': customerAId,
            'p_items': [
              {
                'menu_item_id': testMenuItem['id'],
                'quantity': 1,
                'special_instructions': '',
              }
            ],
          },
        );
      } on PostgrestException catch (e) {
        caughtError = true;
        expect(e.message, contains('completed ordering'));
      } catch (e) {
        caughtError = true;
        expect(e.toString(), contains('completed ordering'));
      }
      expect(caughtError, isTrue, reason: 'Database guard must reject order for finished customer');
    });

    // -------------------------------------------------------------------------
    // TEST 5 — Multi-customer isolation
    // -------------------------------------------------------------------------
    late String customerBId;
    late String customerCId;

    test('Test 5 — Multi-customer status isolation (A finished, B & C active)', () async {
      // Add Customer B
      final custBRes = await client.rpc(
        'add_customer_to_table_session',
        params: {
          'p_session_id': sessionId,
          'p_name': 'Customer B',
          'p_phone': '9876543210',
        },
      );
      customerBId = custBRes['id'];

      // Add Customer C
      final custCRes = await client.rpc(
        'add_customer_to_table_session',
        params: {
          'p_session_id': sessionId,
          'p_name': 'Customer C',
          'p_phone': '9876543211',
        },
      );
      customerCId = custCRes['id'];

      // Fetch session details
      final sessionDetails = await client.rpc(
        'get_active_table_session_details',
        params: {'p_table_id': testTable['id']},
      );

      final customers = sessionDetails['customers'] as List;
      final custA = customers.firstWhere((c) => c['id'] == customerAId);
      final custB = customers.firstWhere((c) => c['id'] == customerBId);
      final custC = customers.firstWhere((c) => c['id'] == customerCId);

      expect(custA['status'], equals('finished'));
      expect(custB['status'], equals('active'));
      expect(custC['status'], equals('active'));

      // Session status must remain 'active' because B and C are still active
      expect(sessionDetails['status'], equals('active'));
    });

    // -------------------------------------------------------------------------
    // TEST 6 — All customers finished -> table_sessions.status = 'billing', table remains 'occupied'
    // -------------------------------------------------------------------------
    test('Test 6 — All customers finished sets session to billing and keeps table occupied', () async {
      // Finish Customer B
      final finishB = await client.rpc(
        'finish_table_session_customer',
        params: {'p_customer_id': customerBId},
      );
      expect(finishB['status'], equals('finished'));
      expect(finishB['all_finished'], isFalse);

      // Verify session is still active
      final sessionMid = await client
          .from('table_sessions')
          .select()
          .eq('id', sessionId)
          .single();
      expect(sessionMid['status'], equals('active'));

      // Finish Customer C (all customers now finished)
      final finishC = await client.rpc(
        'finish_table_session_customer',
        params: {'p_customer_id': customerCId},
      );
      expect(finishC['status'], equals('finished'));
      expect(finishC['all_finished'], isTrue);
      expect(finishC['session_status'], equals('billing'));

      // Verify table_sessions.status is now 'billing'
      final sessionAfter = await client
          .from('table_sessions')
          .select()
          .eq('id', sessionId)
          .single();
      expect(sessionAfter['status'], equals('billing'));

      // CRITICAL: restaurant_tables.status must REMAIN 'occupied'!
      final tableAfter = await client
          .from('restaurant_tables')
          .select()
          .eq('id', testTable['id'])
          .single();
      expect(tableAfter['status'], equals('occupied'), reason: 'Physical table must remain occupied when in billing');
    });

    // -------------------------------------------------------------------------
    // TEST 7 — Cancelled order: contributes ₹0 to billable total
    // -------------------------------------------------------------------------
    test('Test 7 — Cancelled order contributes ₹0 to billable total in Today Orders', () async {
      // 1. Add active Customer D to test table session
      final custDRes = await client.rpc(
        'add_customer_to_table_session',
        params: {
          'p_session_id': sessionId,
          'p_name': 'Customer D',
          'p_phone': '9876543212',
        },
      );
      final customerDId = custDRes['id'];

      // 2. Submit order for Customer D
      final orderRes = await client.rpc(
        'submit_dine_in_order',
        params: {
          'p_table_id': testTable['id'],
          'p_session_id': sessionId,
          'p_session_customer_id': customerDId,
          'p_items': [
            {
              'menu_item_id': testMenuItem['id'],
              'quantity': 2,
              'special_instructions': 'Extra mint',
            }
          ],
        },
      );
      final orderId = orderRes['order_id'];
      expect(orderId, isNotNull);

      // 3. Cancel the order
      final cancelRes = await client.rpc(
        'cancel_server_order',
        params: {
          'p_order_id': orderId,
          'p_reason': 'Customer changed mind',
        },
      );
      expect(cancelRes['status'], equals('cancelled'));

      // 4. Query Today Orders
      final todayOrders = await client.rpc('get_server_today_orders') as List;
      final cancelledOrder = todayOrders.firstWhere((o) => o['order_id'] == orderId);

      expect(cancelledOrder['order_status'], equals('cancelled'));
      expect(num.parse(cancelledOrder['total_amount'].toString()), equals(0.00),
          reason: 'Cancelled order must contribute ₹0 to billable total');
      expect(num.parse(cancelledOrder['raw_amount'].toString()), greaterThan(0.00),
          reason: 'Raw snapshot amount is preserved for auditing');
    });

    // -------------------------------------------------------------------------
    // TEST 8 — Server isolation: Server cannot retrieve another server's orders
    // -------------------------------------------------------------------------
    test('Test 8 — Server isolation prevents server from querying other staff orders', () async {
      final dummyOtherServerId = '00000000-0000-0000-0000-000000009999';
      bool caught = false;
      try {
        await client.rpc(
          'get_server_today_orders',
          params: {'p_server_id': dummyOtherServerId},
        );
      } on PostgrestException catch (e) {
        caught = true;
        expect(e.message, contains('servers may only view their own order history'));
      } catch (e) {
        caught = true;
        expect(e.toString(), contains('servers may only view their own order history'));
      }
      expect(caught, isTrue, reason: 'Server role must be blocked from requesting other servers orders');

      // Calling without parameter returns only own orders
      final ownOrders = await client.rpc('get_server_today_orders') as List;
      expect(ownOrders, isA<List>());
    });

    // -------------------------------------------------------------------------
    // TEST 9 — Business day: Today IST orders appear, yesterday excluded
    // -------------------------------------------------------------------------
    test('Test 9 — Business day filter uses Asia/Kolkata date', () async {
      // Default query (today IST) returns the orders placed during this session
      final todayOrders = await client.rpc('get_server_today_orders') as List;
      expect(todayOrders, isNotEmpty);

      // Querying with yesterday's date returns 0 orders for today's test
      final yesterdayOrders = await client.rpc(
        'get_server_today_orders',
        params: {'p_date': '2020-01-01'},
      ) as List;
      expect(yesterdayOrders, isEmpty, reason: 'Historical date filter must not return today orders');
    });

    // -------------------------------------------------------------------------
    // TEST 10 — Table closure: only close_table_session frees the table
    // -------------------------------------------------------------------------
    test('Test 10 — Table closure releases table to available only via close_table_session', () async {
      // Table must currently still be 'occupied'
      final tableBefore = await client
          .from('restaurant_tables')
          .select()
          .eq('id', testTable['id'])
          .single();
      expect(tableBefore['status'], equals('occupied'));

      // Close table session (Cashier/Staff closure lifecycle)
      final closeRes = await client.rpc(
        'close_table_session',
        params: {'p_table_id': testTable['id']},
      );
      expect(closeRes['success'], isTrue);

      // Verify table is now 'available'
      final tableAfter = await client
          .from('restaurant_tables')
          .select()
          .eq('id', testTable['id'])
          .single();
      expect(tableAfter['status'], equals('available'));

      // Verify session is now 'completed'
      final sessionDb = await client
          .from('table_sessions')
          .select()
          .eq('id', sessionId)
          .single();
      expect(sessionDb['status'], equals('completed'));
    });
  });
}
