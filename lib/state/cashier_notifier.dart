import 'dart:async';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../repositories/billing_repository.dart';
import '../repositories/order_repository.dart';
import '../services/supabase_service.dart';
import 'cashier_provider.dart';
import 'cashier_state.dart';
import 'server_order_provider.dart';

/// Riverpod Notifier managing Cashier operations:
/// 1. Mode Selection (Dine-In Billing vs Parcel Ordering/Billing)
/// 2. Dine-In Billing Queue (Table Selection -> Customer -> Generate Bill -> Settle -> Close Table)
/// 3. Parcel Workflow (Customer Phone/Name -> Menu -> Take Order -> Instant Bill & Settle)
class CashierNotifier extends Notifier<CashierState> {
  StreamSubscription<List<RestaurantTable>>? _tablesSubscription;
  RealtimeChannel? _realtimeChannel;
  bool _mounted = true;

  @override
  CashierState build() {
    _mounted = true;
    ref.onDispose(() {
      _mounted = false;
      _tablesSubscription?.cancel();
      _realtimeChannel?.unsubscribe();
    });

    Future.microtask(() => initialize());
    return const CashierState(isLoading: true);
  }

  BillingRepository get _billingRepository => ref.read(billingRepositoryProvider);
  OrderRepository get _orderRepository => ref.read(orderRepositoryProvider);

  /// Load catalog and initial tables.
  Future<void> initialize() async {
    if (!_mounted) return;
    state = state.copyWith(isLoading: true, errorMessage: () => null);

    try {
      final results = await Future.wait<dynamic>([
        _orderRepository.fetchTables(),
        _orderRepository.fetchCategories(),
        _orderRepository.fetchMenuItems(),
        _orderRepository.fetchAddons(),
      ]);

      if (!_mounted) return;

      final tables = results[0] as List<RestaurantTable>;
      final categories = results[1] as List<Category>;
      final menuItems = results[2] as List<MenuItem>;
      final addons = results[3] as List<MenuAddon>;

      final firstCategoryId = categories.isNotEmpty ? categories.first.id : null;

      state = state.copyWith(
        tables: tables,
        categories: categories,
        menuItems: menuItems,
        availableAddons: addons,
        selectedCategoryId: () => firstCategoryId,
        isLoading: false,
      );

      _subscribeToRealtimeTables();
      _subscribeToRealtimeMenuAndTables();
    } catch (e) {
      if (!_mounted) return;
      debugPrint('Error initializing cashier catalog: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: () => 'Failed to load tables and menu catalog.',
      );
    }
  }

  void _subscribeToRealtimeTables() {
    _tablesSubscription?.cancel();
    _tablesSubscription = _orderRepository.streamTables().listen(
      (updatedTables) {
        state = state.copyWith(tables: updatedTables);
      },
      onError: (err) {
        debugPrint('Realtime cashier tables error: $err');
      },
    );
  }

  void _subscribeToRealtimeMenuAndTables() {
    _realtimeChannel?.unsubscribe();
    final client = SupabaseService.client;
    _realtimeChannel = client
        .channel('cashier_catalog_sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'menu_items',
          callback: (_) async {
            if (!_mounted) return;
            try {
              final items = await _orderRepository.fetchMenuItems(onlyAvailable: true);
              if (!_mounted) return;

              final availableIds = {for (var m in items) m.id};
              final updatedParcelCart = Map<String, CartItem>.from(state.parcelCart);
              updatedParcelCart.removeWhere((key, _) => !availableIds.contains(key));

              state = state.copyWith(
                menuItems: items,
                parcelCart: updatedParcelCart,
              );
            } catch (e) {
              debugPrint('Cashier realtime menu items refresh error: $e');
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'restaurant_tables',
          callback: (_) async {
            if (!_mounted) return;
            try {
              final tables = await _orderRepository.fetchTables();
              if (!_mounted) return;
              state = state.copyWith(tables: tables);
            } catch (e) {
              debugPrint('Cashier realtime tables refresh error: $e');
            }
          },
        )
        .subscribe();
  }

  /// Switch mode (Dine-In vs Parcel).
  void selectMode(CashierMode mode) {
    if (mode == CashierMode.dineIn) {
      state = state.copyWith(
        activeMode: CashierMode.dineIn,
        currentStep: CashierStep.dineInQueue,
        errorMessage: () => null,
      );
    } else if (mode == CashierMode.parcel) {
      final firstCategory = state.categories.isNotEmpty ? state.categories.first.id : null;
      state = state.copyWith(
        activeMode: CashierMode.parcel,
        currentStep: CashierStep.parcelCustomer,
        selectedCategoryId: () => firstCategory,
        parcelCart: {},
        parcelCustomerName: () => null,
        parcelCustomerPhone: () => null,
        parcelNotes: () => null,
        errorMessage: () => null,
      );
    } else if (mode == CashierMode.expenses) {
      state = state.copyWith(
        activeMode: CashierMode.expenses,
        errorMessage: () => null,
      );
    } else {
      state = state.copyWith(
        activeMode: CashierMode.none,
        currentStep: CashierStep.modeSelection,
        errorMessage: () => null,
      );
    }
  }

  /// Return to Cashier Mode selection screen.
  void returnToModeSelection() {
    state = state.copyWith(
      activeMode: CashierMode.none,
      currentStep: CashierStep.modeSelection,
      selectedTableSession: () => null,
      selectedCustomer: () => null,
      selectedOrder: () => null,
      activeBill: () => null,
      paymentResult: () => null,
      parcelCart: {},
      parcelNotes: () => null,
      errorMessage: () => null,
    );
  }

  /// Select a table to view session details and customer orders.
  Future<void> selectTable(RestaurantTable table) async {
    state = state.copyWith(isLoading: true, errorMessage: () => null);

    try {
      final sessionDetails = await _orderRepository.fetchActiveTableSession(table.id);

      final unpaidCustomers = sessionDetails.customers.where((c) => c.hasUnpaidOrders).toList();
      final defaultCustomer = unpaidCustomers.isNotEmpty
          ? unpaidCustomers.first
          : (sessionDetails.customers.isNotEmpty ? sessionDetails.customers.first : null);

      // Check if any order already has an active unpaid bill
      Bill? existingBill;
      if (defaultCustomer != null) {
        for (final order in defaultCustomer.orders) {
          final b = await _billingRepository.fetchBillForOrder(order.id);
          if (b != null && b.status == 'unpaid') {
            existingBill = b;
            break;
          }
        }
      }

      state = state.copyWith(
        selectedTableSession: () => sessionDetails,
        selectedCustomer: () => defaultCustomer,
        activeBill: () => existingBill,
        currentStep: CashierStep.tableDetail,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('Error selecting table: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: () => 'Failed to load table session: $e',
      );
    }
  }

  /// Select a specific customer within a table session to view/bill their orders.
  Future<void> selectCustomer(SessionCustomer customer) async {
    Bill? existingBill;
    for (final order in customer.orders) {
      final b = await _billingRepository.fetchBillForOrder(order.id);
      if (b != null && b.status == 'unpaid') {
        existingBill = b;
        break;
      }
    }

    state = state.copyWith(
      selectedCustomer: () => customer,
      activeBill: () => existingBill,
      errorMessage: () => null,
    );
  }

  /// Return from Table Detail view back to Dine-In Billing Queue.
  void returnToDineInQueue() {
    state = state.copyWith(
      selectedTableSession: () => null,
      selectedCustomer: () => null,
      selectedOrder: () => null,
      activeBill: () => null,
      currentStep: CashierStep.dineInQueue,
      errorMessage: () => null,
    );
  }

  /// Generate bill for an order (or consolidated customer orders).
  Future<Bill?> generateBillForOrder(
    String orderId, {
    String? discountType,
    double discountValue = 0,
    String? discountReason,
  }) async {
    // Dine-In Guard: The server must mark the customer as finished before a bill can be created
    if (state.selectedTableSession != null &&
        state.selectedCustomer != null &&
        !state.selectedCustomer!.isFinished) {
      state = state.copyWith(
        errorMessage: () =>
            'Cannot generate bill: Customer is still dining. The server must mark this customer as finished before billing.',
      );
      return null;
    }

    state = state.copyWith(isSubmitting: true, errorMessage: () => null);

    try {
      final bill = await _billingRepository.generateBillForOrder(
        orderId,
        discountType: discountType,
        discountValue: discountValue,
        discountReason: discountReason,
      );

      // Refresh table session if in dine-in mode to reflect consolidated orders
      if (state.selectedTableSession != null) {
        final updatedSession = await _orderRepository.fetchActiveTableSession(state.selectedTableSession!.tableId);
        final unpaidCustomers = updatedSession.customers.where((c) => c.hasUnpaidOrders).toList();
        final updatedCustomer = state.selectedCustomer != null
            ? updatedSession.customers.firstWhere(
                (c) => c.id == state.selectedCustomer!.id,
                orElse: () => (unpaidCustomers.isNotEmpty ? unpaidCustomers.first : updatedSession.customers.first),
              )
            : (unpaidCustomers.isNotEmpty ? unpaidCustomers.first : (updatedSession.customers.isNotEmpty ? updatedSession.customers.first : null));

        state = state.copyWith(
          selectedTableSession: () => updatedSession,
          selectedCustomer: () => updatedCustomer,
          activeBill: () => bill,
          isSubmitting: false,
        );
      } else {
        state = state.copyWith(
          activeBill: () => bill,
          isSubmitting: false,
        );
      }

      return bill;
    } catch (e) {
      debugPrint('Error generating bill: $e');
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: () => 'Bill generation failed: $e',
      );
      return null;
    }
  }

  /// Settle bill with payment records.
  Future<bool> settleBill(
    String billId,
    List<Map<String, dynamic>> payments,
  ) async {
    state = state.copyWith(isSubmitting: true, errorMessage: () => null);

    try {
      final result = await _billingRepository.settleBill(billId, payments);

      // Refresh table session if in dine-in mode
      if (state.selectedTableSession != null) {
        final tableId = state.selectedTableSession!.tableId;
        final updatedSession = await _orderRepository.fetchActiveTableSession(tableId);

        // Check if there are still active dining customers or unbilled orders at this table
        final hasActiveDining = updatedSession.customers.any((c) =>
            c.isActive ||
            c.orders.any((o) => o.isActive) ||
            c.hasUnpaidOrders);

        // Get customers with unpaid orders ready to bill next, or active dining customers
        final remainingUnpaid = updatedSession.customers.where((c) => c.hasUnpaidOrders).toList();
        final remainingActive = updatedSession.customers.where((c) => c.isActive && c.status != CustomerStatus.billed).toList();
        final nextCustomer = remainingUnpaid.isNotEmpty
            ? remainingUnpaid.first
            : (remainingActive.isNotEmpty ? remainingActive.first : null);

        // If ALL customers across this table are settled and NO active dining customers remain, close table session!
        if (!hasActiveDining) {
          try {
            await _billingRepository.closeTableSession(tableId);
          } catch (closeErr) {
            debugPrint('Auto-close table session note: $closeErr');
          }
          final refreshedTables = await _orderRepository.fetchTables();

          state = state.copyWith(
            tables: refreshedTables,
            selectedTableSession: () => null,
            selectedCustomer: () => null,
            activeBill: () => null,
            paymentResult: () => result,
            currentStep: CashierStep.dineInQueue,
            isSubmitting: false,
          );
        } else {
          // Table still has active dining or pending customers! Keep table occupied & session alive!
          final updatedTables = await _orderRepository.fetchTables();
          Bill? nextCustomerBill;
          if (nextCustomer != null) {
            for (final order in nextCustomer.orders) {
              final b = await _billingRepository.fetchBillForOrder(order.id);
              if (b != null && b.status == 'unpaid') {
                nextCustomerBill = b;
                break;
              }
            }
          }

          state = state.copyWith(
            tables: updatedTables,
            selectedTableSession: () => updatedSession,
            selectedCustomer: () => nextCustomer,
            activeBill: () => nextCustomerBill,
            paymentResult: () => result,
            isSubmitting: false,
          );
        }
      } else {
        state = state.copyWith(
          paymentResult: () => result,
          activeBill: () => null,
          isSubmitting: false,
        );
      }

      return true;
    } catch (e) {
      debugPrint('Error settling bill: $e');
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: () => 'Payment settlement failed: $e',
      );
      return false;
    }
  }

  /// Close table session.
  Future<bool> closeTableSession(String tableId) async {
    state = state.copyWith(isLoading: true, errorMessage: () => null);

    try {
      await _billingRepository.closeTableSession(tableId);
      final refreshedTables = await _orderRepository.fetchTables();

      state = state.copyWith(
        tables: refreshedTables,
        selectedTableSession: () => null,
        selectedCustomer: () => null,
        activeBill: () => null,
        currentStep: CashierStep.dineInQueue,
        isLoading: false,
      );

      return true;
    } catch (e) {
      debugPrint('Error closing table session: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: () => 'Failed to close table session: $e',
      );
      return false;
    }
  }

  // ─── PARCEL FLOW METHODS ───────────────────────────────────────────────────

  /// Set parcel customer info and proceed to ordering screen.
  void setParcelCustomerInfo({String? name, required String phone}) {
    final cleaned = phone.replaceAll(RegExp(r'\D'), '');
    if (cleaned.length < 10) {
      state = state.copyWith(
        errorMessage: () => 'Please enter a valid 10-digit Indian mobile number.',
      );
      return;
    }

    state = state.copyWith(
      parcelCustomerName: () => name?.trim(),
      parcelCustomerPhone: () => cleaned,
      currentStep: CashierStep.parcelOrdering,
      errorMessage: () => null,
    );
  }

  /// Select category in parcel ordering screen.
  void selectParcelCategory(String? categoryId) {
    state = state.copyWith(selectedCategoryId: () => categoryId);
  }

  /// Add item to parcel cart.
  void addParcelItem(MenuItem item) {
    final updatedCart = Map<String, CartItem>.from(state.parcelCart);
    final currentQty = updatedCart[item.id]?.quantity ?? 0;

    updatedCart[item.id] = CartItem(
      menuItem: item,
      quantity: currentQty + 1,
      specialInstructions: updatedCart[item.id]?.specialInstructions,
    );

    state = state.copyWith(parcelCart: updatedCart);
  }

  /// Decrement item in parcel cart.
  void decrementParcelItem(String menuItemId) {
    final updatedCart = Map<String, CartItem>.from(state.parcelCart);
    final currentQty = updatedCart[menuItemId]?.quantity ?? 0;
    if (currentQty <= 0) return;

    if (currentQty - 1 <= 0) {
      updatedCart.remove(menuItemId);
    } else {
      final existing = updatedCart[menuItemId]!;
      updatedCart[menuItemId] = existing.copyWith(quantity: currentQty - 1);
    }

    state = state.copyWith(parcelCart: updatedCart);
  }

  /// Remove item completely from parcel cart.
  void removeParcelItem(String menuItemId) {
    final updatedCart = Map<String, CartItem>.from(state.parcelCart);
    updatedCart.remove(menuItemId);
    state = state.copyWith(parcelCart: updatedCart);
  }

  /// Submit parcel order and return generated order details.
  Future<Map<String, dynamic>?> submitParcelOrder() async {
    if (state.parcelCart.isEmpty) {
      state = state.copyWith(
        errorMessage: () => 'Please select items to place a parcel order.',
      );
      return null;
    }

    if (state.parcelCustomerPhone == null || state.parcelCustomerPhone!.isEmpty) {
      state = state.copyWith(
        errorMessage: () => 'Customer phone number is required.',
      );
      return null;
    }

    state = state.copyWith(isSubmitting: true, errorMessage: () => null);

    try {
      final items = state.parcelCart.values.toList();
      final orderResult = await _billingRepository.submitParcelOrder(
        customerName: state.parcelCustomerName,
        customerPhone: state.parcelCustomerPhone!,
        items: items,
        notes: state.parcelNotes,
      );

      final orderId = orderResult['order_id'] as String;

      // Automatically generate bill for the parcel order
      final bill = await _billingRepository.generateBillForOrder(orderId);

      state = state.copyWith(
        activeBill: () => bill,
        isSubmitting: false,
      );

      return orderResult;
    } catch (e) {
      debugPrint('Error submitting parcel order: $e');
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: () => 'Parcel order submission failed: $e',
      );
      return null;
    }
  }

  /// Clear active error banner.
  void clearError() {
    state = state.copyWith(errorMessage: () => null);
  }
}
