import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_cane/core/theme/app_theme.dart';
import 'package:fresh_cane/models/models.dart';
import 'package:fresh_cane/presentation/server/today_orders_screen.dart';
import 'package:fresh_cane/presentation/server/views/table_context_view.dart';
import 'package:fresh_cane/presentation/server/widgets/finish_customer_dialog.dart';
import 'package:fresh_cane/state/server_order_notifier.dart';
import 'package:fresh_cane/state/server_order_provider.dart';
import 'package:fresh_cane/state/today_orders_provider.dart';

// ─── Test Fake Notifiers ──────────────────────────────────────────────────────

class FakeServerOrderNotifier extends ServerOrderNotifier {
  final ServerOrderState initialState;
  bool finishCustomerCalled = false;
  String? finishedCustomerId;

  FakeServerOrderNotifier(this.initialState);

  @override
  ServerOrderState build() {
    return initialState;
  }

  @override
  Future<bool> finishCustomer(String customerId) async {
    finishCustomerCalled = true;
    finishedCustomerId = customerId;

    // Simulate authoritative DB state return
    final currentSession = state.activeSessionDetails;
    if (currentSession != null) {
      final updatedCustomers = currentSession.customers.map((c) {
        if (c.id == customerId) {
          return SessionCustomer(
            id: c.id,
            sessionId: c.sessionId,
            customerLabel: c.customerLabel,
            customerName: c.customerName,
            customerPhone: c.customerPhone,
            status: CustomerStatus.finished,
            orders: c.orders,
            activeOrdersCount: c.activeOrdersCount,
            activeTotal: c.activeTotal,
          );
        }
        return c;
      }).toList();

      final allFinished = updatedCustomers.every((c) => !c.canOrder);

      final updatedSession = TableSessionDetails(
        sessionId: currentSession.sessionId,
        tableId: currentSession.tableId,
        tableNumber: currentSession.tableNumber,
        seatingCapacity: currentSession.seatingCapacity,
        tableStatus: currentSession.tableStatus,
        status: allFinished ? 'billing' : currentSession.status,
        openedAt: currentSession.openedAt,
        customers: updatedCustomers,
        activeOrdersCount: currentSession.activeOrdersCount,
        activeTotal: currentSession.activeTotal,
      );

      state = state.copyWith(
        activeSessionDetails: () => updatedSession,
        isLoading: false,
      );
    }
    return true;
  }
}

class FakeTodayOrdersNotifier extends TodayOrdersNotifier {
  final TodayOrdersState initialState;
  bool refreshCalled = false;

  FakeTodayOrdersNotifier(this.initialState);

  @override
  TodayOrdersState build() {
    return initialState;
  }

  @override
  Future<void> refresh() async {
    refreshCalled = true;
  }

  @override
  Future<void> loadOrders() async {}
}

// ─── Main Test Suite ─────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testTable = RestaurantTable(
    id: 'tbl-001',
    tableNumber: 'Table 5',
    seatingCapacity: 4,
    status: 'occupied',
    isActive: true,
  );

  final testOrder1 = SessionOrderSummary(
    id: 'ord-001',
    orderNumber: 'Order #001',
    status: 'open',
    totalAmount: 150.0,
    itemsCount: 2,
    itemsSummary: 'Sugarcane Juice × 2',
    createdAt: DateTime(2026, 9, 19, 13, 0),
  );

  final testOrder2 = SessionOrderSummary(
    id: 'ord-002',
    orderNumber: 'Order #002',
    status: 'open',
    totalAmount: 120.0,
    itemsCount: 1,
    itemsSummary: 'Veg Sandwich × 1',
    createdAt: DateTime(2026, 9, 19, 13, 15),
  );

  final testCustomerA = SessionCustomer(
    id: 'cust-A',
    sessionId: 'sess-001',
    customerLabel: 'Ahmed',
    customerName: 'Ahmed',
    customerPhone: '9876543210',
    status: CustomerStatus.active,
    orders: [testOrder1, testOrder2],
    activeOrdersCount: 2,
    activeTotal: 270.0,
  );

  final testCustomerB = SessionCustomer(
    id: 'cust-B',
    sessionId: 'sess-001',
    customerLabel: 'Customer B',
    customerName: 'Customer B',
    status: CustomerStatus.active,
    orders: const [],
    activeOrdersCount: 0,
    activeTotal: 0.0,
  );

  group('Phase 4: Customer Finish Dialog Unit Tests', () {
    testWidgets('1-5. Dialog displays customer name, order count, billable total, and handles actions',
        (tester) async {
      bool? dialogResult;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  dialogResult = await FinishCustomerDialog.show(
                    context: context,
                    customer: testCustomerA,
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      // Open Dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify content
      expect(find.text('Finish Customer?'), findsOneWidget);
      expect(find.text('Ahmed'), findsOneWidget);
      expect(find.text('+91 9876543210'), findsOneWidget);
      expect(find.text('2 Orders'), findsOneWidget);
      expect(find.text('₹270'), findsOneWidget);
      expect(
        find.textContaining('Once finished, this customer cannot place new orders'),
        findsOneWidget,
      );

      // Cancel button test
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Finish Customer?'), findsNothing);
      expect(dialogResult, isFalse);

      // Open Dialog again and confirm
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Finish Customer'));
      await tester.pumpAndSettle();

      expect(find.text('Finish Customer?'), findsNothing);
      expect(dialogResult, isTrue);
    });
  });

  group('Phase 4: TableContextView Customer Finish & Multi-Customer Presentation Tests', () {
    testWidgets('1-11. Active customer displays New Order and Finish, confirm invokes notifier and updates to Finished',
        (tester) async {
      final sessionDetails = TableSessionDetails(
        sessionId: 'sess-001',
        tableId: 'tbl-001',
        tableNumber: 'Table 5',
        seatingCapacity: 4,
        tableStatus: 'occupied',
        status: 'active',
        openedAt: DateTime(2026, 9, 19, 12, 0),
        customers: [testCustomerA],
        activeOrdersCount: 2,
        activeTotal: 270.0,
      );

      final initialState = ServerOrderState(
        activeTable: testTable,
        activeSessionDetails: sessionDetails,
        currentStep: ServerViewStep.tableContext,
      );

      final fakeNotifier = FakeServerOrderNotifier(initialState);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serverOrderProvider.overrideWith(() => fakeNotifier),
          ],
          child: const MaterialApp(
            home: TableContextView(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Active customer displays Finish button
      expect(find.text('✓ Finish'), findsOneWidget);
      // 2. Active customer displays New Order
      expect(find.text('New Order'), findsOneWidget);
      // 3. Status badge is ACTIVE
      expect(find.text('ACTIVE'), findsWidgets);
      expect(find.text('Ahmed'), findsOneWidget);

      // 4. Tap Finish button to open confirmation dialog
      await tester.tap(find.text('✓ Finish'));
      await tester.pumpAndSettle();

      expect(find.text('Finish Customer?'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(FinishCustomerDialog),
          matching: find.text('₹270'),
        ),
        findsOneWidget,
      );

      // 5. Confirm Finish
      await tester.tap(find.text('Finish Customer'));
      await tester.pumpAndSettle();

      // 6. Confirms notifier was invoked
      expect(fakeNotifier.finishCustomerCalled, isTrue);
      expect(fakeNotifier.finishedCustomerId, equals('cust-A'));

      // 7. Successful Finish displays Finished state
      expect(find.text('FINISHED'), findsOneWidget);
      expect(find.text('Waiting for Cashier billing'), findsWidgets);
      expect(find.text('✓ Finished'), findsOneWidget);

      // 8. Finished customer's past orders remain visible
      expect(find.text('Order #001'), findsOneWidget);
      expect(find.text('Order #002'), findsOneWidget);

      // 9. All customers finished banner appears and table remains occupied
      expect(
        find.textContaining('All customers finished • Waiting for Cashier billing'),
        findsOneWidget,
      );
      expect(find.text('OCCUPIED'), findsOneWidget);
    });

    testWidgets('12-15. Multi-Customer: Customer A finished, Customer B remains active with ordering',
        (tester) async {
      final finishedCustomerA = SessionCustomer(
        id: 'cust-A',
        sessionId: 'sess-001',
        customerLabel: 'Ahmed',
        customerName: 'Ahmed',
        status: CustomerStatus.finished,
        orders: [testOrder1],
        activeOrdersCount: 1,
        activeTotal: 150.0,
      );

      final sessionDetails = TableSessionDetails(
        sessionId: 'sess-001',
        tableId: 'tbl-001',
        tableNumber: 'Table 5',
        seatingCapacity: 4,
        tableStatus: 'occupied',
        status: 'active',
        openedAt: DateTime(2026, 9, 19, 12, 0),
        customers: [finishedCustomerA, testCustomerB],
        activeOrdersCount: 1,
        activeTotal: 150.0,
      );

      final initialState = ServerOrderState(
        activeTable: testTable,
        activeSessionDetails: sessionDetails,
        currentStep: ServerViewStep.tableContext,
      );

      final fakeNotifier = FakeServerOrderNotifier(initialState);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serverOrderProvider.overrideWith(() => fakeNotifier),
          ],
          child: const MaterialApp(
            home: TableContextView(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Customer A is FINISHED
      expect(find.text('FINISHED'), findsOneWidget);
      // Customer B is ACTIVE (plus active orders also show ACTIVE)
      expect(find.text('ACTIVE'), findsWidgets);

      // Customer B has Take Order and Finish available
      expect(find.text('Take Order'), findsOneWidget);
      expect(find.text('✓ Finish'), findsOneWidget);

      // Customer A has ✓ Finished badge
      expect(find.text('✓ Finished'), findsOneWidget);

      // Session is still active (not all finished yet, so billing banner is NOT shown)
      expect(
        find.textContaining('All customers finished • Waiting for Cashier billing'),
        findsNothing,
      );
    });
  });

  group('Phase 4: Today Orders Screen Presentation Tests', () {
    testWidgets('24-30. Today Orders renders dine-in, parcel, cancelled ₹0, empty state, and refresh',
        (tester) async {
      final todayOrders = [
        TodayOrder(
          orderId: 'o-1',
          orderNumber: 'Order #005',
          tableId: 'tbl-001',
          tableNumber: '5',
          customerName: 'Ahmed',
          customerPhone: '9876543210',
          customerStatus: CustomerStatus.active,
          orderStatus: 'open',
          totalAmount: 110.0,
          rawAmount: 110.0,
          itemsCount: 2,
          itemsSummary: 'Sugarcane Juice × 1, Veg Sandwich × 1',
          createdAt: DateTime(2026, 9, 19, 13, 35),
        ),
        TodayOrder(
          orderId: 'o-2',
          orderNumber: 'Order #008',
          tableId: '',
          tableNumber: '', // Parcel order: no table
          customerName: 'Fatima',
          customerPhone: '9123456789',
          customerStatus: CustomerStatus.active,
          orderStatus: 'open',
          totalAmount: 180.0,
          rawAmount: 180.0,
          itemsCount: 1,
          itemsSummary: 'Paneer Momos × 2',
          createdAt: DateTime(2026, 9, 19, 13, 52),
        ),
        TodayOrder(
          orderId: 'o-3',
          orderNumber: 'Order #003',
          tableId: 'tbl-001',
          tableNumber: '5',
          customerName: 'Raj',
          customerStatus: CustomerStatus.active,
          orderStatus: 'cancelled',
          totalAmount: 0.0, // Billable is ₹0
          rawAmount: 80.0,
          itemsCount: 1,
          itemsSummary: 'Lime Juice × 1',
          createdAt: DateTime(2026, 9, 19, 13, 20),
          cancelledAt: DateTime(2026, 9, 19, 13, 25),
          cancellationReason: 'Customer changed mind',
        ),
      ];

      final state = TodayOrdersState(
        orders: todayOrders,
        isLoading: false,
      );

      final fakeTodayNotifier = FakeTodayOrdersNotifier(state);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            todayOrdersProvider.overrideWith(() => fakeTodayNotifier),
          ],
          child: const MaterialApp(
            home: TodayOrdersScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Screen title
      expect(find.text("Today's Orders"), findsOneWidget);

      // Metrics: Total 3, Billable ₹290 (110 + 180 + 0), Cancelled 1
      expect(find.text('3'), findsOneWidget); // Orders count
      expect(find.text('₹290'), findsOneWidget); // Billable total
      expect(find.text('1'), findsOneWidget); // Cancelled count

      // Dine-in order with Table 5 badge
      expect(find.text('Order #005'), findsOneWidget);
      expect(find.text('Table 5'), findsWidgets);

      // Parcel order with PARCEL badge and no table number
      expect(find.text('Order #008'), findsOneWidget);
      expect(find.text('PARCEL'), findsOneWidget);

      // Cancelled order with ₹0 billable amount and CANCELLED badge
      expect(find.text('Order #003'), findsOneWidget);
      expect(find.text('CANCELLED (Billable: ₹0)'), findsOneWidget);
      expect(find.textContaining('Customer changed mind'), findsOneWidget);

      // Refresh button triggers refresh
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(fakeTodayNotifier.refreshCalled, isTrue);
    });

    testWidgets('Empty state renders correctly when no orders exist',
        (tester) async {
      const state = TodayOrdersState(
        orders: [],
        isLoading: false,
      );

      final fakeTodayNotifier = FakeTodayOrdersNotifier(state);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            todayOrdersProvider.overrideWith(() => fakeTodayNotifier),
          ],
          child: const MaterialApp(
            home: TodayOrdersScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No orders today'), findsOneWidget);
      expect(
        find.textContaining("Orders you create during today's"),
        findsOneWidget,
      );
    });
  });
}
