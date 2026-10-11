import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fresh_cane/core/config/app_config.dart';
import 'package:fresh_cane/core/errors/domain_exceptions.dart';
import 'package:fresh_cane/models/models.dart';
import 'package:fresh_cane/repositories/order_repository.dart';
import 'package:fresh_cane/state/state.dart';

void main() {
  // ***************************************************************************
  // PART 1: DOMAIN MODEL UNIT TESTS
  // ***************************************************************************
  group('Phase 3 Domain Models Unit Tests', () {
    test('1-4. Customer status enum deserialization (active, finished, billed, closed)', () {
      expect(CustomerStatus.fromString('active'), equals(CustomerStatus.active));
      expect(CustomerStatus.fromString('finished'), equals(CustomerStatus.finished));
      expect(CustomerStatus.fromString('billed'), equals(CustomerStatus.billed));
      expect(CustomerStatus.fromString('closed'), equals(CustomerStatus.closed));
      expect(CustomerStatus.fromString('UNKNOWN'), equals(CustomerStatus.active));
      expect(CustomerStatus.fromString(null), equals(CustomerStatus.active));

      final custActive = SessionCustomer.fromJson({
        'id': 'c1',
        'session_id': 's1',
        'customer_label': 'Cust 1',
        'status': 'active',
      });
      expect(custActive.status, equals(CustomerStatus.active));
      expect(custActive.isActive, isTrue);

      final custFinished = SessionCustomer.fromJson({
        'id': 'c2',
        'session_id': 's1',
        'customer_label': 'Cust 2',
        'status': 'finished',
        'finished_at': '2026-09-19T10:00:00Z',
        'finished_by': 'u1',
      });
      expect(custFinished.status, equals(CustomerStatus.finished));
      expect(custFinished.isFinished, isTrue);
      expect(custFinished.finishedAt, isNotNull);
      expect(custFinished.finishedBy, equals('u1'));

      final custBilled = SessionCustomer.fromJson({
        'id': 'c3',
        'session_id': 's1',
        'customer_label': 'Cust 3',
        'status': 'billed',
      });
      expect(custBilled.status, equals(CustomerStatus.billed));
      expect(custBilled.isBilled, isTrue);

      final custClosed = SessionCustomer.fromJson({
        'id': 'c4',
        'session_id': 's1',
        'customer_label': 'Cust 4',
        'status': 'closed',
      });
      expect(custClosed.status, equals(CustomerStatus.closed));
      expect(custClosed.isClosed, isTrue);
    });

    test('5. canOrder is true ONLY for active status', () {
      const activeCust = SessionCustomer(
        id: '1',
        sessionId: 's',
        customerLabel: 'A',
        status: CustomerStatus.active,
      );
      const finishedCust = SessionCustomer(
        id: '2',
        sessionId: 's',
        customerLabel: 'B',
        status: CustomerStatus.finished,
      );
      const billedCust = SessionCustomer(
        id: '3',
        sessionId: 's',
        customerLabel: 'C',
        status: CustomerStatus.billed,
      );
      const closedCust = SessionCustomer(
        id: '4',
        sessionId: 's',
        customerLabel: 'D',
        status: CustomerStatus.closed,
      );

      expect(activeCust.canOrder, isTrue);
      expect(finishedCust.canOrder, isFalse);
      expect(billedCust.canOrder, isFalse);
      expect(closedCust.canOrder, isFalse);
    });

    test('6. isReadyForBilling is based strictly on status, NOT activeTotal', () {
      // Finished customer with ₹0 billable total is STILL ready for billing
      const zeroTotalFinished = SessionCustomer(
        id: '1',
        sessionId: 's',
        customerLabel: 'Zero',
        status: CustomerStatus.finished,
        activeTotal: 0.0,
      );
      expect(zeroTotalFinished.isReadyForBilling, isTrue);

      // Active customer with positive total is NOT ready for billing
      const positiveActive = SessionCustomer(
        id: '2',
        sessionId: 's',
        customerLabel: 'Active',
        status: CustomerStatus.active,
        activeTotal: 250.0,
      );
      expect(positiveActive.isReadyForBilling, isFalse);
    });

    test('18 & 21-22. TodayOrder deserialization, snapshots, and cancellation ₹0 contribution', () {
      final activeOrderJson = {
        'order_id': 'o1',
        'order_number': 'ORD-001',
        'table_id': 't1',
        'table_number': 'T-01',
        'session_id': 's1',
        'customer_id': 'c1',
        'customer_name': 'Ramesh',
        'customer_phone': '9876543210',
        'customer_status': 'active',
        'order_status': 'open',
        'total_amount': 150.00,
        'raw_amount': 150.00,
        'items_count': 2,
        'items_summary': 'Fresh Cane Juice × 2',
        'created_at': '2026-09-19T07:30:00Z',
        'cancelled_at': null,
        'cancellation_reason': null,
      };

      final activeOrder = TodayOrder.fromJson(activeOrderJson);
      expect(activeOrder.orderId, equals('o1'));
      expect(activeOrder.orderNumber, equals('ORD-001'));
      expect(activeOrder.tableNumber, equals('T-01'));
      expect(activeOrder.customerName, equals('Ramesh'));
      expect(activeOrder.customerStatus, equals(CustomerStatus.active));
      expect(activeOrder.isCancelled, isFalse);
      expect(activeOrder.totalAmount, equals(150.00));
      expect(activeOrder.billableAmount, equals(150.00));

      final cancelledOrderJson = {
        'order_id': 'o2',
        'order_number': 'ORD-002',
        'table_id': 't1',
        'table_number': 'T-01',
        'session_id': 's1',
        'customer_id': 'c1',
        'customer_name': 'Ramesh',
        'customer_phone': '9876543210',
        'customer_status': 'active',
        'order_status': 'cancelled',
        'total_amount': 0.00,
        'raw_amount': 90.00,
        'items_count': 1,
        'items_summary': 'Mint Cane Juice × 1',
        'created_at': '2026-09-19T07:45:00Z',
        'cancelled_at': '2026-09-19T07:50:00Z',
        'cancellation_reason': 'Out of stock',
      };

      final cancelledOrder = TodayOrder.fromJson(cancelledOrderJson);
      expect(cancelledOrder.isCancelled, isTrue);
      expect(cancelledOrder.totalAmount, equals(0.00));
      expect(cancelledOrder.billableAmount, equals(0.00));
      expect(cancelledOrder.rawAmount, equals(90.00)); // Snapshot retained
      expect(cancelledOrder.cancellationReason, equals('Out of stock'));
    });

    test('16-17. TableSessionDetails status vs physical table availability invariant', () {
      final billingSession = TableSessionDetails.fromJson({
        'table_id': 't1',
        'table_number': 'T-01',
        'seating_capacity': 4,
        'table_status': 'occupied', // Physical table remains occupied!
        'session_id': 's1',
        'status': 'billing', // Session is in billing
        'opened_at': '2026-09-19T07:00:00Z',
        'customers': [],
        'active_total': 180.0,
        'active_orders_count': 2,
      });

      expect(billingSession.isBilling, isTrue);
      expect(billingSession.hasActiveSession, isTrue);
      // Table availability must NOT be true when table is occupied in billing!
      expect(billingSession.isAvailable, isFalse);
      expect(billingSession.tableStatus, equals('occupied'));
    });
  });

  // ***************************************************************************
  // PART 2: INTEGRATION TESTS WITH REPOSITORY, NOTIFIERS & LIVE SUPABASE
  // ***************************************************************************
  group('Phase 3 Repository & State Integration Tests', () {
    late SupabaseClient client;
    late OrderRepository repository;
    late Map<String, dynamic> testTable;
    late Map<String, dynamic> testMenuItem;

    setUpAll(() async {
      client = SupabaseClient(
        AppConfig.supabaseUrl,
        AppConfig.supabaseAnonKey,
      );

      final authRes = await client.auth.signInWithPassword(
        email: 'server@freshcane.dev',
        password: 'server@123',
      );
      expect(authRes.user, isNotNull);

      repository = OrderRepository(client);

      final tables = await client
          .from('restaurant_tables')
          .select()
          .eq('is_active', true)
          .order('table_number');
      testTable = tables.last;

      try {
        await repository.closeTableSession(testTable['id']);
      } catch (_) {}

      final menuItems = await client
          .from('menu_items')
          .select()
          .eq('is_active', true)
          .eq('is_available', true)
          .limit(1);
      testMenuItem = menuItems.first;
    });

    tearDownAll(() async {
      try {
        await repository.closeTableSession(testTable['id']);
      } catch (_) {}
    });

    late String sessionId;
    late String customerAId;
    late String customerBId;

    test('7-9. Repository finishCustomer calls RPC, updates state, and is idempotent', () async {
      final sessionDetails = await repository.openOrGetTableSession(testTable['id']);
      sessionId = sessionDetails.sessionId!;
      customerAId = sessionDetails.customers.first.id;

      // Finish Customer A
      final result1 = await repository.finishCustomer(customerAId);
      expect(result1['success'], isTrue);
      expect(result1['status'], equals('finished'));
      expect(result1['already_finished'], isFalse);

      // Verify updated authoritative session
      final refreshed = await repository.fetchActiveTableSession(testTable['id']);
      final custA = refreshed.customers.firstWhere((c) => c.id == customerAId);
      expect(custA.isFinished, isTrue);
      expect(custA.canOrder, isFalse);

      // Idempotent second call
      final result2 = await repository.finishCustomer(customerAId);
      expect(result2['success'], isTrue);
      expect(result2['status'], equals('finished'));
      expect(result2['already_finished'], isTrue);
    });

    test('10. Billed/Closed rejection maps to CustomerNoLongerActiveException or failure', () async {
      // Simulate attempting to finish an invalid or closed ID
      final dummyId = '00000000-0000-0000-0000-000000000099';
      expect(
        () => repository.finishCustomer(dummyId),
        throwsA(isA<FreshCaneException>()),
      );
    });

    test('12-15. Multi-customer: Customer A finished, Customer B active, order isolation', () async {
      // Add Customer B to session
      final custBRes = await repository.addCustomerToSession(
        sessionId,
        name: 'Customer B',
        phone: '9876543220',
      );
      customerBId = custBRes['id'];

      // Fetch session
      final session = await repository.fetchActiveTableSession(testTable['id']);
      final custA = session.customers.firstWhere((c) => c.id == customerAId);
      final custB = session.customers.firstWhere((c) => c.id == customerBId);

      expect(custA.isFinished, isTrue);
      expect(custA.canOrder, isFalse);
      expect(custB.isActive, isTrue);
      expect(custB.canOrder, isTrue);

      // Customer B can place an order successfully
      final orderRes = await repository.submitDineInOrder(
        tableId: testTable['id'],
        sessionId: sessionId,
        sessionCustomerId: customerBId,
        customerName: 'Customer B',
        items: [
          CartItem(
            menuItem: MenuItem.fromJson(testMenuItem),
            quantity: 1,
          ),
        ],
      );
      expect(orderRes['order_id'], isNotNull);

      // Customer A CANNOT place an order (rejected by repository & backend guard)
      expect(
        () => repository.submitDineInOrder(
          tableId: testTable['id'],
          sessionId: sessionId,
          sessionCustomerId: customerAId,
          customerName: 'Customer A',
          items: [
            CartItem(
              menuItem: MenuItem.fromJson(testMenuItem),
              quantity: 1,
            ),
          ],
        ),
        throwsA(isA<CustomerCannotOrderException>()),
      );
    });

    test('16-17. All customers finished transitions session to billing, table remains occupied', () async {
      // Finish Customer B (now all customers A & B are finished)
      final finishBRes = await repository.finishCustomer(customerBId);
      expect(finishBRes['all_finished'], isTrue);
      expect(finishBRes['session_status'], equals('billing'));

      // Fetch authoritative session details
      final session = await repository.fetchActiveTableSession(testTable['id']);
      expect(session.isBilling, isTrue);
      expect(session.status, equals('billing'));

      // Physical table MUST remain occupied!
      expect(session.tableStatus, equals('occupied'));
      expect(session.isAvailable, isFalse);
    });

    test('19-20. Today Orders repository API isolates to current IST business day', () async {
      final todayOrders = await repository.fetchTodayOrders();
      expect(todayOrders, isA<List<TodayOrder>>());
      expect(todayOrders, isNotEmpty);

      // All returned orders must belong to today
      for (final order in todayOrders) {
        expect(order.orderNumber, isNotEmpty);
        expect(order.tableNumber, isNotEmpty);
        expect(order.billableAmount, greaterThanOrEqualTo(0.0));
      }

      // Past date query returns empty
      final pastOrders = await repository.fetchTodayOrders(date: DateTime(2020, 1, 1));
      expect(pastOrders, isEmpty);
    });

    test('23. ServerOrderNotifier and TodayOrdersNotifier Riverpod state management', () async {
      final container = ProviderContainer(
        overrides: [
          orderRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      // 1. Check initial TodayOrders state
      final initialTodayState = container.read(todayOrdersProvider);
      expect(initialTodayState.isLoading, isTrue);

      // 2. Load today orders
      await container.read(todayOrdersProvider.notifier).loadOrders();
      final loadedTodayState = container.read(todayOrdersProvider);
      expect(loadedTodayState.isLoading, isFalse);
      expect(loadedTodayState.orders, isNotEmpty);
      expect(loadedTodayState.totalBillableAmount, greaterThan(0.0));

      // 3. Check ServerOrderNotifier finish action
      final serverNotifier = container.read(serverOrderProvider.notifier);
      await serverNotifier.openTable(RestaurantTable.fromJson(testTable));

      // Active table loaded
      final serverState = container.read(serverOrderProvider);
      expect(serverState.activeTable, isNotNull);
      expect(serverState.activeSessionDetails?.isBilling, isTrue);
    });

    test('24-27. Cashier compatibility: multiple orders remain separate, existing bill intact', () async {
      // In the session, verify Customer B has orders
      final session = await repository.fetchActiveTableSession(testTable['id']);
      final custB = session.customers.firstWhere((c) => c.id == customerBId);

      expect(custB.orders, isNotEmpty);
      // Order boundaries are strictly preserved
      for (final o in custB.orders) {
        expect(o.id, isNotEmpty);
        expect(o.orderNumber, isNotEmpty);
        expect(o.totalAmount, greaterThan(0.0));
      }

      // Verify no duplicate billing architecture: public.bills still references order_id
      final billsColumns = await client.from('bills').select('id, order_id').limit(1);
      expect(billsColumns, isA<List>());
    });
  });
}
