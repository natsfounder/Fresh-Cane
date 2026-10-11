import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fresh_cane/core/config/app_config.dart';
import 'package:fresh_cane/core/errors/domain_exceptions.dart';
import 'package:fresh_cane/models/models.dart';
import 'package:fresh_cane/repositories/order_repository.dart';

void main() {
  group('Fresh Cane V1 — Phase 4 Server Presentation & Business Flow E2E Verification Suite', () {
    late SupabaseClient client;
    late OrderRepository repository;

    late RestaurantTable targetTable;
    late String sessionId;
    late SessionCustomer customerA;
    late SessionCustomer customerB;

    late String order1Id;
    late String order2Id;
    late String order3Id;
    late String order4Id;

    late MenuItem sugarcaneJuice;
    late MenuItem vegSandwich;

    setUpAll(() async {
      client = SupabaseClient(
        AppConfig.supabaseUrl,
        AppConfig.supabaseAnonKey,
      );

      // STEP 1: SERVER LOGIN
      final authRes = await client.auth.signInWithPassword(
        email: 'server@freshcane.dev',
        password: 'server@123',
      );
      expect(authRes.user, isNotNull, reason: 'Server authentication must succeed');

      // Verify server user role
      final profileRow = await client
          .from('user_profiles')
          .select('role, is_active')
          .eq('id', authRes.user!.id)
          .single();
      expect(profileRow['role'], equals('server'), reason: 'User must have server role');
      expect(profileRow['is_active'], isTrue, reason: 'Server account must be active');

      repository = OrderRepository(client);

      // Load catalog items
      final menuItems = await repository.fetchMenuItems();
      sugarcaneJuice = menuItems.firstWhere((m) => m.name == 'Sugarcane Juice');
      vegSandwich = menuItems.firstWhere((m) => m.name == 'Veg Sandwich');
    });

    test('STEP 1 & 2: Table Selection & Session Clean Initialization', () async {
      final tables = await repository.fetchTables();
      expect(tables.isNotEmpty, isTrue);

      targetTable = tables.firstWhere(
        (t) => t.tableNumber.contains('5') || t.tableNumber.contains('05'),
        orElse: () => tables.firstWhere((t) => t.isAvailable, orElse: () => tables.first),
      );

      // Reset any preexisting session on this table
      if (targetTable.isOccupied) {
        await repository.closeTableSession(targetTable.id);
      }

      final sessionDetails = await repository.openOrGetTableSession(targetTable.id);
      expect(sessionDetails.sessionId, isNotNull);
      expect(sessionDetails.status, equals('active'));
      sessionId = sessionDetails.sessionId!;
    });

    test('STEP 3 & 4: Customer A ("Ahmed") & Customer B Creation', () async {
      var details = await repository.fetchActiveTableSession(targetTable.id);
      if (details.customers.isNotEmpty) {
        customerA = details.customers.first;
      } else {
        await repository.addCustomerToSession(
          sessionId,
          name: 'Ahmed',
          phone: '9876543210',
        );
        details = await repository.fetchActiveTableSession(targetTable.id);
        customerA = details.customers.first;
      }
      expect(customerA.id, isNotEmpty);
      expect(customerA.status, equals(CustomerStatus.active));
      expect(customerA.canOrder, isTrue);

      // Add Customer B
      await repository.addCustomerToSession(
        sessionId,
        name: 'Customer B',
        phone: '9123456780',
      );

      details = await repository.fetchActiveTableSession(targetTable.id);
      customerB = details.customers.firstWhere((c) => c.displayName == 'Customer B');
      expect(customerB.id, isNotEmpty);
      expect(customerB.displayName, equals('Customer B'));
      expect(customerB.status, equals(CustomerStatus.active));
      expect(customerB.canOrder, isTrue);
    });

    test('STEP 5 & 6: Customer A Multiple Orders (Order #001 & #002)', () async {
      // Order #001 for Customer A (Sugarcane Juice x2 + Veg Sandwich x1)
      final res1 = await repository.submitDineInOrder(
        tableId: targetTable.id,
        sessionId: sessionId,
        sessionCustomerId: customerA.id,
        customerName: customerA.displayName,
        customerPhone: customerA.customerPhone,
        items: [
          CartItem(menuItem: sugarcaneJuice, quantity: 2),
          CartItem(menuItem: vegSandwich, quantity: 1),
        ],
      );
      order1Id = res1['order_id'] as String;
      expect(order1Id, isNotEmpty);

      // Repeat Order #002 for Customer A (Sugarcane Juice x1)
      final res2 = await repository.submitDineInOrder(
        tableId: targetTable.id,
        sessionId: sessionId,
        sessionCustomerId: customerA.id,
        customerName: customerA.displayName,
        customerPhone: customerA.customerPhone,
        items: [
          CartItem(menuItem: sugarcaneJuice, quantity: 1),
        ],
      );
      order2Id = res2['order_id'] as String;
      expect(order2Id, isNotEmpty);

      // Verify Customer A has 2 active orders
      final details = await repository.fetchActiveTableSession(targetTable.id);
      final refreshedA = details.customers.firstWhere((c) => c.id == customerA.id);
      expect(refreshedA.orders.length, equals(2));
      expect(refreshedA.canOrder, isTrue);
      expect(refreshedA.status, equals(CustomerStatus.active));
    });

    test('STEP 7: Customer B Order #003', () async {
      // Order #003 for Customer B (Veg Sandwich x2)
      final res3 = await repository.submitDineInOrder(
        tableId: targetTable.id,
        sessionId: sessionId,
        sessionCustomerId: customerB.id,
        customerName: customerB.displayName,
        customerPhone: customerB.customerPhone,
        items: [
          CartItem(menuItem: vegSandwich, quantity: 2),
        ],
      );
      order3Id = res3['order_id'] as String;
      expect(order3Id, isNotEmpty);

      final details = await repository.fetchActiveTableSession(targetTable.id);
      final refreshedB = details.customers.firstWhere((c) => c.id == customerB.id);
      expect(refreshedB.orders.length, equals(1));
      expect(refreshedB.canOrder, isTrue);
    });

    test('STEP 8 & 9: Finish Customer A and Verify Invariants', () async {
      // Authoritative Finish for Customer A
      final finishRes = await repository.finishCustomer(customerA.id);
      expect(finishRes['status'], equals('finished'));

      // Fetch authoritative session state
      final details = await repository.fetchActiveTableSession(targetTable.id);
      final finishedA = details.customers.firstWhere((c) => c.id == customerA.id);
      expect(finishedA.status, equals(CustomerStatus.finished));
      expect(finishedA.isFinished, isTrue);
      expect(finishedA.canOrder, isFalse);

      // Orders for Customer A remain intact and visible
      expect(finishedA.orders.length, equals(2));

      // Attempting to place an order for Finished Customer A must be rejected by backend
      expect(
        () async => await repository.submitDineInOrder(
          tableId: targetTable.id,
          sessionId: sessionId,
          sessionCustomerId: customerA.id,
          customerName: customerA.displayName,
          customerPhone: customerA.customerPhone,
          items: [
            CartItem(menuItem: sugarcaneJuice, quantity: 1),
          ],
        ),
        throwsA(isA<CustomerCannotOrderException>()),
      );
    });

    test('STEP 10 & 11: Customer B Remains Active and Can Place Order #004', () async {
      final details = await repository.fetchActiveTableSession(targetTable.id);
      final activeB = details.customers.firstWhere((c) => c.id == customerB.id);
      expect(activeB.status, equals(CustomerStatus.active));
      expect(activeB.canOrder, isTrue);

      // Customer B places Order #004 while Customer A is finished
      final res4 = await repository.submitDineInOrder(
        tableId: targetTable.id,
        sessionId: sessionId,
        sessionCustomerId: customerB.id,
        customerName: customerB.displayName,
        customerPhone: customerB.customerPhone,
        items: [
          CartItem(menuItem: sugarcaneJuice, quantity: 1),
        ],
      );
      order4Id = res4['order_id'] as String;
      expect(order4Id, isNotEmpty);

      final updatedDetails = await repository.fetchActiveTableSession(targetTable.id);
      final updatedB = updatedDetails.customers.firstWhere((c) => c.id == customerB.id);
      expect(updatedB.orders.length, equals(2));
      expect(updatedDetails.status, equals('active'));
    });

    test('STEP 12, 13 & 14: Finish Customer B — All Customers Finished Transitions Session to Billing', () async {
      // Finish Customer B
      final finishRes = await repository.finishCustomer(customerB.id);
      expect(finishRes['status'], equals('finished'));

      // Refresh authoritative session details
      final details = await repository.fetchActiveTableSession(targetTable.id);
      expect(details.customers.every((c) => c.isFinished), isTrue);

      // Invariant: Session transitions to 'billing'
      expect(details.status, equals('billing'));
      expect(details.isBilling, isTrue);

      // CRITICAL Invariant: Physical restaurant table remains 'occupied'
      final tables = await repository.fetchTables();
      final table = tables.firstWhere((t) => t.id == targetTable.id);
      expect(table.status, equals('occupied'));
      expect(table.isOccupied, isTrue);
      expect(table.isAvailable, isFalse);
    });

    test('STEP 15 & 16: Today Orders Presentation Data Verification', () async {
      final todayOrders = await repository.fetchTodayOrders();
      expect(todayOrders.isNotEmpty, isTrue);

      // Confirm orders placed today exist in the list
      final order1 = todayOrders.firstWhere((o) => o.orderId == order1Id);
      expect(order1.orderNumber, isNotEmpty);
      expect(order1.tableNumber, equals(targetTable.tableNumber));
      expect(order1.customerName, equals(customerA.displayName));
      expect(order1.isActive, isTrue);
      expect(order1.totalAmount, greaterThan(0));
      expect(order1.billableAmount, equals(order1.totalAmount));

      // Check IST timestamp
      expect(order1.createdAt.isBefore(DateTime.now().add(const Duration(minutes: 5))), isTrue);
    });

    test('STEP 17 & 18: Non-Destructive Cancellation in Today Orders (Order #002)', () async {
      // Cancel Customer A's Order #002
      await repository.cancelOrder(order2Id, reason: 'Customer changed mind');

      final todayOrders = await repository.fetchTodayOrders();
      final cancelledOrder = todayOrders.firstWhere((o) => o.orderId == order2Id);

      expect(cancelledOrder.isCancelled, isTrue);
      expect(cancelledOrder.isActive, isFalse);
      expect(cancelledOrder.cancellationReason, equals('Customer changed mind'));
      // Authoritative financial invariant: Cancelled order contributes strictly ₹0 to billable total
      expect(cancelledOrder.billableAmount, equals(0.0));
      expect(cancelledOrder.rawAmount, greaterThan(0.0));
    });

    tearDownAll(() async {
      // Clean up test table session
      try {
        await repository.closeTableSession(targetTable.id);
      } catch (_) {}
    });
  });
}
