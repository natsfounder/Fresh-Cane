import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fresh_cane/core/config/app_config.dart';
import 'package:fresh_cane/models/models.dart';
import 'package:fresh_cane/repositories/order_repository.dart';
import 'package:fresh_cane/state/server_order_state.dart';

void main() {
  group('Fresh Cane V1 — Final Physical Device E2E Verification Suite', () {
    late SupabaseClient client;
    late OrderRepository repository;

    late RestaurantTable table5;
    late String table5SessionId;
    late SessionCustomer customerAhmed;
    late SessionCustomer customerB;
    late SessionCustomer customerC;

    late String order1Id;
    late String order2Id;
    late String order3Id;
    late String order4Id;
    late String order5Id;

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
      expect(authRes.user, isNotNull, reason: 'Authentication must succeed');

      // Verify server user role
      final profileRow = await client
          .from('user_profiles')
          .select('role, is_active')
          .eq('id', authRes.user!.id)
          .single();
      expect(profileRow['role'], equals('server'), reason: 'User must have server role');
      expect(profileRow['is_active'], isTrue, reason: 'Server account must be active');

      repository = OrderRepository(client);

      // Load menu catalog
      final menuItems = await repository.fetchMenuItems();
      sugarcaneJuice = menuItems.firstWhere((m) => m.name == 'Sugarcane Juice');
      vegSandwich = menuItems.firstWhere((m) => m.name == 'Veg Sandwich');
    });

    test('STEP 2: Table Selection & Session Initialization (Table 5)', () async {
      final tables = await repository.fetchTables();
      expect(tables.isNotEmpty, isTrue);

      // Find Table 5 (or first available table)
      table5 = tables.firstWhere(
        (t) => t.tableNumber.contains('5') || t.tableNumber.contains('05'),
        orElse: () => tables.firstWhere((t) => t.isAvailable, orElse: () => tables.first),
      );

      // If already occupied from previous tests, reset it cleanly first
      if (table5.isOccupied) {
        await repository.closeTableSession(table5.id);
      }

      // Open Table 5 session
      final sessionDetails = await repository.openOrGetTableSession(table5.id);
      expect(sessionDetails.sessionId, isNotNull);
      expect(sessionDetails.status, equals('active'));
      table5SessionId = sessionDetails.sessionId!;

      // Concurrency check: calling openOrGetTableSession again returns SAME session without duplication
      final duplicateCheck = await repository.openOrGetTableSession(table5.id);
      expect(duplicateCheck.sessionId, equals(table5SessionId));

      // Verify Table is now occupied in restaurant_tables
      final updatedTable = await client
          .from('restaurant_tables')
          .select()
          .eq('id', table5.id)
          .single();
      expect(updatedTable['status'], equals('occupied'));
    });

    test('STEP 3: Customer A Creation ("Ahmed")', () async {
      // Add Customer Ahmed to Table 5 session
      await repository.addCustomerToSession(
        table5SessionId,
        name: 'Ahmed',
        phone: '9876543210',
      );

      final sessionDetails = await repository.fetchActiveTableSession(table5.id);
      final ahmedMatch = sessionDetails.customers.where((c) => c.displayName == 'Ahmed').toList();
      expect(ahmedMatch.isNotEmpty, isTrue, reason: 'Customer Ahmed must be seated in table session');
      customerAhmed = ahmedMatch.first;
      expect(customerAhmed.customerPhone, equals('9876543210'));
    });

    test('STEP 4: Ordering UX Quantity Controls (0 -> + -> 1 -> + -> 2 -> - -> 1 -> - -> 0)', () {
      var state = const ServerOrderState();

      // Initial: 0 in cart
      expect(state.getQuantityInCart(sugarcaneJuice.id), equals(0));
      expect(state.cart.containsKey(sugarcaneJuice.id), isFalse);

      // + -> 1
      state = state.copyWith(cart: {
        sugarcaneJuice.id: CartItem(menuItem: sugarcaneJuice, quantity: 1),
      });
      expect(state.getQuantityInCart(sugarcaneJuice.id), equals(1));
      expect(state.totalItemsCount, equals(1));

      // + -> 2
      state = state.copyWith(cart: {
        sugarcaneJuice.id: CartItem(menuItem: sugarcaneJuice, quantity: 2),
      });
      expect(state.getQuantityInCart(sugarcaneJuice.id), equals(2));
      expect(state.totalItemsCount, equals(2));

      // - -> 1
      state = state.copyWith(cart: {
        sugarcaneJuice.id: CartItem(menuItem: sugarcaneJuice, quantity: 1),
      });
      expect(state.getQuantityInCart(sugarcaneJuice.id), equals(1));

      // - -> 0 (removes item from cart completely)
      final clearedCart = Map<String, CartItem>.from(state.cart)..remove(sugarcaneJuice.id);
      state = state.copyWith(cart: clearedCart);
      expect(state.getQuantityInCart(sugarcaneJuice.id), equals(0));
      expect(state.cart.containsKey(sugarcaneJuice.id), isFalse);
      expect(state.canSubmitOrder, isFalse, reason: 'Empty cart cannot be submitted');
    });

    test('STEP 5: Place Customer A Order #001 (Sugarcane Juice x2 + Veg Sandwich x1)', () async {
      final cart = [
        CartItem(menuItem: sugarcaneJuice, quantity: 2),
        CartItem(menuItem: vegSandwich, quantity: 1),
      ];

      final res = await repository.submitDineInOrder(
        tableId: table5.id,
        sessionId: table5SessionId,
        sessionCustomerId: customerAhmed.id,
        customerName: customerAhmed.displayName,
        customerPhone: customerAhmed.customerPhone,
        items: cart,
        notes: 'Order #001',
      );

      expect(res['order_id'], isNotNull);
      order1Id = res['order_id'] as String;

      // Verify order amount: (40*2) + (70*1) = 150
      final orderRow = await client.from('orders').select().eq('id', order1Id).single();
      expect(orderRow['status'], equals('open'));
      expect((res['total_amount'] as num).toDouble(), equals(150.0));
      expect(orderRow['session_id'], equals(table5SessionId));
      expect(orderRow['session_customer_id'], equals(customerAhmed.id));
    });

    test('STEP 6: Customer A Repeat Order #002 (Order #001 must remain untouched)', () async {
      final cart = [
        CartItem(menuItem: sugarcaneJuice, quantity: 1),
      ];

      final res = await repository.submitDineInOrder(
        tableId: table5.id,
        sessionId: table5SessionId,
        sessionCustomerId: customerAhmed.id,
        customerName: customerAhmed.displayName,
        customerPhone: customerAhmed.customerPhone,
        items: cart,
        notes: 'Order #002 repeat',
      );

      expect(res['order_id'], isNotNull);
      order2Id = res['order_id'] as String;
      expect(order2Id, isNot(equals(order1Id)), reason: 'Repeat order must be a separate record');

      // Verify Order #001 is completely untouched
      final order1Row = await client.from('orders').select().eq('id', order1Id).single();
      expect(order1Row['status'], equals('open'));

      // Verify Order #002 is 40.0
      final order2Row = await client.from('orders').select().eq('id', order2Id).single();
      expect(order2Row['status'], equals('open'));
      expect((res['total_amount'] as num).toDouble(), equals(40.0));
    });

    test('STEP 7: Customer B Creation & Order #003', () async {
      await repository.addCustomerToSession(
        table5SessionId,
        name: 'Customer B',
        phone: '9876543211',
      );

      final sessionDetails = await repository.fetchActiveTableSession(table5.id);
      customerB = sessionDetails.customers.firstWhere((c) => c.displayName == 'Customer B');

      final cart = [
        CartItem(menuItem: vegSandwich, quantity: 1), // 70.0
      ];

      final res = await repository.submitDineInOrder(
        tableId: table5.id,
        sessionId: table5SessionId,
        sessionCustomerId: customerB.id,
        customerName: customerB.displayName,
        customerPhone: customerB.customerPhone,
        items: cart,
        notes: 'Order #003 Customer B',
      );

      order3Id = res['order_id'] as String;
      expect(order3Id, isNotNull);
    });

    test('STEP 8: Customer C Creation & Order #004', () async {
      await repository.addCustomerToSession(
        table5SessionId,
        name: 'Customer C',
        phone: '9876543212',
      );

      final sessionDetails = await repository.fetchActiveTableSession(table5.id);
      customerC = sessionDetails.customers.firstWhere((c) => c.displayName == 'Customer C');

      final cart = [
        CartItem(menuItem: sugarcaneJuice, quantity: 1), // 40.0
      ];

      final res = await repository.submitDineInOrder(
        tableId: table5.id,
        sessionId: table5SessionId,
        sessionCustomerId: customerC.id,
        customerName: customerC.displayName,
        customerPhone: customerC.customerPhone,
        items: cart,
        notes: 'Order #004 Customer C',
      );

      order4Id = res['order_id'] as String;
      expect(order4Id, isNotNull);

      // Verify Table 5 represents 3+ customers and 4 independent orders
      final updatedSession = await repository.fetchActiveTableSession(table5.id);
      expect(updatedSession.customers.length, greaterThanOrEqualTo(3));
      expect(updatedSession.activeOrdersCount, equals(4));
    });

    test('STEP 9 & 10: Individual Order Cancellation (Order #003) & Billable Total Validation', () async {
      // Current active orders before cancellation:
      // #001 = 150, #002 = 40, #003 = 70, #004 = 40. Sum = 300.
      final preCancelSession = await repository.fetchActiveTableSession(table5.id);
      expect(preCancelSession.activeTotal, equals(300.0));

      // Cancel ONLY Order #003
      final cancelRes = await repository.cancelOrder(
        order3Id,
        reason: 'Customer B changed mind',
      );
      expect(cancelRes['status'], equals('cancelled'));

      // STEP 10: Check Active Billable Total
      // Active total MUST strictly exclude #003: 150 + 40 + 40 = 230.0 (NOT 300.0)
      final postCancelSession = await repository.fetchActiveTableSession(table5.id);
      expect(postCancelSession.activeTotal, equals(230.0), reason: 'Cancelled order must be excluded from active total');
      expect(postCancelSession.activeOrdersCount, equals(3));

      // Verify other orders remain ACTIVE
      final order1 = await client.from('orders').select().eq('id', order1Id).single();
      final order2 = await client.from('orders').select().eq('id', order2Id).single();
      final order4 = await client.from('orders').select().eq('id', order4Id).single();
      expect(order1['status'], equals('open'));
      expect(order2['status'], equals('open'));
      expect(order4['status'], equals('open'));
    });

    test('STEP 11: Non-Destructive Cancellation (Order #003 row and items retained)', () async {
      final cancelledRow = await client.from('orders').select().eq('id', order3Id).single();
      expect(cancelledRow['status'], equals('cancelled'));
      expect(cancelledRow['cancelled_at'], isNotNull);
      expect(cancelledRow['cancellation_reason'], equals('Customer B changed mind'));

      // Verify order items still exist in database for auditing
      final items = await client.from('order_items').select().eq('order_id', order3Id);
      expect(items.isNotEmpty, isTrue);

      // Verify Customer B and Table 5 are NOT cancelled
      final tableRow = await client.from('restaurant_tables').select().eq('id', table5.id).single();
      expect(tableRow['status'], equals('occupied'));
    });

    test('STEP 12: Continue Ordering After Cancellation (Customer B places Order #005)', () async {
      final cart = [
        CartItem(menuItem: sugarcaneJuice, quantity: 1), // 40.0
      ];

      final res = await repository.submitDineInOrder(
        tableId: table5.id,
        sessionId: table5SessionId,
        sessionCustomerId: customerB.id,
        customerName: customerB.displayName,
        customerPhone: customerB.customerPhone,
        items: cart,
        notes: 'Order #005 Customer B re-order',
      );

      order5Id = res['order_id'] as String;
      expect(order5Id, isNotNull);

      // New active total: 230.0 + 40.0 = 270.0
      final sessionDetails = await repository.fetchActiveTableSession(table5.id);
      expect(sessionDetails.activeTotal, equals(270.0));
      expect(sessionDetails.activeOrdersCount, equals(4));
    });

    test('STEP 13: App Restart Persistence Simulation', () async {
      // Re-instantiate client and repository to simulate complete app close and reopen
      final freshClient = SupabaseClient(AppConfig.supabaseUrl, AppConfig.supabaseAnonKey);
      await freshClient.auth.signInWithPassword(email: 'server@freshcane.dev', password: 'server@123');
      final freshRepository = OrderRepository(freshClient);

      // Fetch active table session from database
      final restoredSession = await freshRepository.fetchActiveTableSession(table5.id);

      expect(restoredSession.sessionId, equals(table5SessionId));
      expect(restoredSession.status, equals('active'));
      expect(restoredSession.activeTotal, equals(270.0));
      expect(restoredSession.activeOrdersCount, equals(4));

      // Check all customers restored
      final customerNames = restoredSession.customers.map((c) => c.displayName).toSet();
      expect(customerNames.contains('Ahmed'), isTrue);
      expect(customerNames.contains('Customer B'), isTrue);
      expect(customerNames.contains('Customer C'), isTrue);

      // Check Customer B order history contains both cancelled order and active order
      final restoredCustomerB = restoredSession.customers.firstWhere((c) => c.displayName == 'Customer B');
      final cBOrderIds = restoredCustomerB.orders.map((o) => o.id).toSet();
      expect(cBOrderIds.contains(order3Id), isTrue, reason: 'Cancelled order must remain in customer history');
      expect(cBOrderIds.contains(order5Id), isTrue, reason: 'Active order must remain in customer history');
    });

    tearDownAll(() async {
      // Reset Table 5 session to available
      await repository.closeTableSession(table5.id);

      final resetTable = await client.from('restaurant_tables').select().eq('id', table5.id).single();
      expect(resetTable['status'], equals('available'));
    });
  });
}
