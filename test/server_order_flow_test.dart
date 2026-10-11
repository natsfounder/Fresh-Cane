import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fresh_cane/core/config/app_config.dart';
import 'package:fresh_cane/models/models.dart';
import 'package:fresh_cane/repositories/order_repository.dart';
import 'package:fresh_cane/state/server_order_state.dart';

void main() {
  group('Domain Models & Calculations Unit Tests', () {
    test('RestaurantTable model properties and availability', () {
      final availableTable = RestaurantTable(
        id: 't-1',
        tableNumber: 'T-01',
        seatingCapacity: 4,
        status: 'available',
        isActive: true,
      );

      expect(availableTable.isAvailable, isTrue);
      expect(availableTable.isOccupied, isFalse);

      final occupiedTable = availableTable.copyWith(status: 'occupied');
      expect(occupiedTable.isAvailable, isFalse);
      expect(occupiedTable.isOccupied, isTrue);

      final inactiveTable = availableTable.copyWith(isActive: false);
      expect(inactiveTable.isAvailable, isFalse);

      final json = availableTable.toJson();
      final fromJson = RestaurantTable.fromJson(json);
      expect(fromJson.tableNumber, equals('T-01'));
      expect(fromJson.seatingCapacity, equals(4));
    });

    test('Category and MenuItem models serialization', () {
      final cat = Category(
        id: 'c-1',
        name: 'Fresh Juices',
        slug: 'fresh-juices',
        displayOrder: 1,
        isActive: true,
      );
      expect(cat.name, equals('Fresh Juices'));
      expect(Category.fromJson(cat.toJson()).slug, equals('fresh-juices'));

      final item = MenuItem(
        id: 'm-1',
        categoryId: 'c-1',
        name: 'Sugarcane Juice',
        description: 'Fresh pressed sugarcane juice',
        basePrice: 40.0,
        isAvailable: true,
        isActive: true,
        displayOrder: 1,
      );
      expect(item.basePrice, equals(40.0));
      expect(MenuItem.fromJson(item.toJson()).name, equals('Sugarcane Juice'));
    });

    test('CartItem calculation and RPC JSON formatting', () {
      final item = MenuItem(
        id: 'm-1',
        categoryId: 'c-1',
        name: 'Sugarcane Juice',
        basePrice: 40.0,
        isAvailable: true,
        isActive: true,
        displayOrder: 1,
      );

      final cartItem = CartItem(
        menuItem: item,
        quantity: 3,
        specialInstructions: 'Less ice',
      );

      expect(cartItem.itemTotal, equals(120.0));

      final rpcJson = cartItem.toRpcJson();
      expect(rpcJson['menu_item_id'], equals('m-1'));
      expect(rpcJson['quantity'], equals(3));
      expect(rpcJson['special_instructions'], equals('Less ice'));
    });

    test('ServerOrderState computed totals and submission rules', () {
      final table = RestaurantTable(
        id: 't-1',
        tableNumber: 'T-01',
        seatingCapacity: 4,
        status: 'available',
        isActive: true,
      );

      final juice = MenuItem(
        id: 'm-1',
        categoryId: 'c-1',
        name: 'Sugarcane Juice',
        basePrice: 40.0,
        isAvailable: true,
        isActive: true,
        displayOrder: 1,
      );
      final sandwich = MenuItem(
        id: 'm-2',
        categoryId: 'c-2',
        name: 'Veg Sandwich',
        basePrice: 70.0,
        isAvailable: true,
        isActive: true,
        displayOrder: 2,
      );

      var state = const ServerOrderState();
      expect(state.canSubmitOrder, isFalse);
      expect(state.totalItemsCount, equals(0));
      expect(state.subtotalAmount, equals(0.0));

      // Add table and customer
      state = state.copyWith(
        activeTable: () => table,
        selectedCustomer: () => const SessionCustomer(
          id: 'cust-1',
          sessionId: 'sess-1',
          customerLabel: 'Customer 1',
        ),
      );
      expect(state.canSubmitOrder, isFalse, reason: 'Cart is still empty');

      // Add items
      state = state.copyWith(cart: {
        juice.id: CartItem(menuItem: juice, quantity: 2), // 80
        sandwich.id: CartItem(menuItem: sandwich, quantity: 1), // 70
      });

      expect(state.totalItemsCount, equals(3));
      expect(state.subtotalAmount, equals(150.0));
      expect(state.grandTotalAmount, equals(150.0));
      expect(state.canSubmitOrder, isTrue);

      // When submitting, canSubmitOrder becomes false
      state = state.copyWith(isSubmitting: true);
      expect(state.canSubmitOrder, isFalse);
    });

    test('Customer Indian mobile number validation regex', () {
      final phoneRegex = RegExp(r'^[6-9]\d{9}$');

      // Valid Indian numbers
      expect(phoneRegex.hasMatch('9876543210'), isTrue);
      expect(phoneRegex.hasMatch('8123456789'), isTrue);
      expect(phoneRegex.hasMatch('7000000000'), isTrue);
      expect(phoneRegex.hasMatch('6999999999'), isTrue);

      // Invalid numbers
      expect(phoneRegex.hasMatch('5876543210'), isFalse, reason: 'Starts with 5');
      expect(phoneRegex.hasMatch('987654321'), isFalse, reason: '9 digits');
      expect(phoneRegex.hasMatch('98765432100'), isFalse, reason: '11 digits');
      expect(phoneRegex.hasMatch('987654321a'), isFalse, reason: 'Contains char');
      expect(phoneRegex.hasMatch('+919876543210'), isFalse, reason: 'Raw prefix');
    });
  });

  group('Database & Server Order RPC Integration Tests', () {
    late SupabaseClient client;
    late OrderRepository repository;

    setUpAll(() async {
      client = SupabaseClient(
        AppConfig.supabaseUrl,
        AppConfig.supabaseAnonKey,
      );

      // Authenticate as active server user
      final authRes = await client.auth.signInWithPassword(
        email: 'server@freshcane.dev',
        password: 'server@123',
      );

      expect(authRes.user, isNotNull);
      repository = OrderRepository(client);
    });

    test('Order catalog data (tables, categories, menu items) is loaded', () async {
      final tables = await repository.fetchTables();
      expect(tables.length, greaterThanOrEqualTo(8));
      expect(tables.any((t) => t.tableNumber == 'T-01'), isTrue);

      final categories = await repository.fetchCategories();
      expect(categories.length, greaterThanOrEqualTo(3));
      expect(categories.any((c) => c.name == 'Fresh Juices'), isTrue);

      final menuItems = await repository.fetchMenuItems();
      expect(menuItems.length, greaterThanOrEqualTo(7));
      expect(menuItems.any((m) => m.name == 'Sugarcane Juice'), isTrue);
    });

    test('Atomic order submission, table concurrency locking, and cleanup', () async {
      // Fetch available tables and menu items
      final tables = await repository.fetchTables();
      final testTable = tables.firstWhere(
        (t) => t.isAvailable,
        orElse: () => tables.first,
      );

      final menuItems = await repository.fetchMenuItems();
      final juice = menuItems.firstWhere((m) => m.name == 'Sugarcane Juice');
      final sandwich = menuItems.firstWhere((m) => m.name == 'Veg Sandwich');

      final cart = [
        CartItem(menuItem: juice, quantity: 2, specialInstructions: 'Cold'),
        CartItem(menuItem: sandwich, quantity: 1),
      ];

      // 1. Submit Dine-In Order
      final submitResult = await repository.submitDineInOrder(
        tableId: testTable.id,
        customerName: 'Integration Test Customer',
        customerPhone: '9876543210',
        items: cart,
        notes: 'Automated test order',
      );

      expect(submitResult['order_id'], isNotNull);
      expect(submitResult['order_number'], startsWith('ORD-'));
      final orderId = submitResult['order_id'] as String;

      try {
        // 2. Verify Table is now OCCUPIED
        final updatedTableRow = await client
            .from('restaurant_tables')
            .select()
            .eq('id', testTable.id)
            .single();
        expect(updatedTableRow['status'], equals('occupied'));

        // 3. Verify Order record
        final orderRow = await client
            .from('orders')
            .select()
            .eq('id', orderId)
            .single();
        expect(orderRow['table_id'], equals(testTable.id));
        expect(orderRow['order_type'], equals('dine_in'));
        expect(orderRow['customer_name'], equals('Integration Test Customer'));
        expect(orderRow['customer_phone'], equals('9876543210'));

        // 4. Verify Order Items & immutable snapshots
        final orderItems = await client
            .from('order_items')
            .select()
            .eq('order_id', orderId);
        expect(orderItems.length, equals(2));

        final juiceItem = orderItems.firstWhere((i) => i['menu_item_id'] == juice.id);
        expect(juiceItem['quantity'], equals(2));
        expect((juiceItem['unit_price_snapshot'] as num).toDouble(), equals(40.0));
        expect(juiceItem['item_name_snapshot'], equals('Sugarcane Juice'));
        expect(juiceItem['category_name_snapshot'], equals('Fresh Juices'));
        expect((juiceItem['item_total'] as num).toDouble(), equals(80.0));
        expect(juiceItem['special_instructions'], equals('Cold'));

        final sandwichItem = orderItems.firstWhere((i) => i['menu_item_id'] == sandwich.id);
        expect(sandwichItem['quantity'], equals(1));
        expect((sandwichItem['unit_price_snapshot'] as num).toDouble(), equals(70.0));
        expect(sandwichItem['item_name_snapshot'], equals('Veg Sandwich'));
        expect(sandwichItem['category_name_snapshot'], equals('Snacks'));
        expect((sandwichItem['item_total'] as num).toDouble(), equals(70.0));

        final totalOrderAmount = orderItems.fold<double>(
          0.0,
          (sum, item) => sum + (item['item_total'] as num).toDouble(),
        );
        expect(totalOrderAmount, equals(150.0)); // (40*2) + (70*1) = 150

        // 5. Multi-Order Verification: Second order on same active table MUST succeed as separate order
        final secondOrderResult = await repository.submitDineInOrder(
          tableId: testTable.id,
          customerName: 'Second Customer',
          customerPhone: '9876543211',
          items: cart,
          notes: 'Second order on same table',
        );

        expect(secondOrderResult['order_id'], isNotNull);
        expect(secondOrderResult['order_id'], isNot(equals(orderId)));
        final secondOrderId = secondOrderResult['order_id'] as String;

        // 6. Test Individual Cancellation: Cancel first order independently
        final cancelResult = await repository.cancelOrder(
          orderId,
          reason: 'Test cancellation',
        );
        expect(cancelResult['status'], equals('cancelled'));

        // Verify first order is marked cancelled in DB
        final cancelledRow = await client
            .from('orders')
            .select()
            .eq('id', orderId)
            .single();
        expect(cancelledRow['status'], equals('cancelled'));
        expect(cancelledRow['cancelled_at'], isNotNull);

        // Verify second order is still ACTIVE
        final activeRow = await client
            .from('orders')
            .select()
            .eq('id', secondOrderId)
            .single();
        expect(activeRow['status'], equals('open'));

        // Clean up second order as well
        await repository.cancelOrder(
          secondOrderId,
          reason: 'Test cleanup',
        );
      } finally {
        // Reset test table session and status via close_table_session RPC
        await repository.closeTableSession(testTable.id);

        final resetTable = await client
            .from('restaurant_tables')
            .select()
            .eq('id', testTable.id)
            .single();
        expect(resetTable['status'], equals('available'));
      }
    });
  });
}
