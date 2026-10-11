import 'dart:async';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/errors/domain_exceptions.dart';
import '../models/models.dart';
import '../repositories/order_repository.dart';
import '../services/supabase_service.dart';
import 'server_order_provider.dart';

/// Riverpod Notifier orchestrating the restaurant Server workflow:
/// 1. Table Selection (New / Active)
/// 2. Table Context (Multi-Customer, Active Totals, Order History, Cancellation)
/// 3. Dedicated Ordering Screen (Categories on LEFT, Menu Cards with +/- controls, Cart on RIGHT)
class ServerOrderNotifier extends Notifier<ServerOrderState> {
  StreamSubscription<List<RestaurantTable>>? _tablesSubscription;
  RealtimeChannel? _realtimeChannel;

  bool _mounted = true;

  @override
  ServerOrderState build() {
    _mounted = true;
    ref.onDispose(() {
      _mounted = false;
      _tablesSubscription?.cancel();
      _realtimeChannel?.unsubscribe();
    });

    Future.microtask(() => initialize());
    return const ServerOrderState(isLoading: true);
  }

  OrderRepository get _repository => ref.read(orderRepositoryProvider);

  /// Load initial tables, categories, and menu items.
  Future<void> initialize() async {
    if (!_mounted) return;
    state = state.copyWith(isLoading: true, errorMessage: () => null);

    try {
      final results = await Future.wait<dynamic>([
        _repository.fetchTables(),
        _repository.fetchCategories(),
        _repository.fetchMenuItems(),
        _repository.fetchAddons(),
      ]);

      if (!_mounted) return;

      final tables = results[0] as List<RestaurantTable>;
      final categories = results[1] as List<Category>;
      final menuItems = results[2] as List<MenuItem>;
      final addons = results[3] as List<MenuAddon>;

      state = state.copyWith(
        tables: tables,
        categories: categories,
        menuItems: menuItems,
        availableAddons: addons,
        isLoading: false,
      );

      _subscribeToRealtimeTables();
      _subscribeToRealtimeOrdersAndCustomers();
    } catch (e) {
      if (!_mounted) return;
      debugPrint('Error initializing server catalog: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: () =>
            'Failed to load tables and menu. Please check your connection.',
      );
    }
  }

  /// Subscribe to Realtime updates on restaurant_tables.
  void _subscribeToRealtimeTables() {
    _tablesSubscription?.cancel();
    _tablesSubscription = _repository.streamTables().listen(
      (updatedTables) async {
        if (!_mounted) return;
        RestaurantTable? newActiveTable = state.activeTable;

        if (state.activeTable != null) {
          final found = updatedTables.firstWhere(
            (t) => t.id == state.activeTable!.id,
            orElse: () => state.activeTable!,
          );
          newActiveTable = found;

          // If the active table was closed and is now available:
          if (!newActiveTable.isOccupied) {
            state = state.copyWith(
              tables: updatedTables,
              activeTable: () => null,
              activeSessionDetails: () => null,
              selectedCustomer: () => null,
              currentStep: ServerViewStep.tableSelection,
            );
            return;
          } else {
            // Table is occupied: trigger silent session sync
            _handleSilentSessionRefresh();
          }
        }

        state = state.copyWith(
          tables: updatedTables,
          activeTable: () => newActiveTable,
        );
      },
      onError: (err) {
        debugPrint('Realtime tables stream error: $err');
      },
    );
  }

  /// Realtime listener on orders, customers, and sessions across all staff devices.
  /// When Cashier bills an order, settled customers vanish immediately on the Server screen.
  void _subscribeToRealtimeOrdersAndCustomers() {
    _realtimeChannel?.unsubscribe();
    final client = SupabaseService.client;
    _realtimeChannel = client
        .channel('server_active_orders_sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'table_session_customers',
          callback: (_) => _handleSilentSessionRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) => _handleSilentSessionRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'table_sessions',
          callback: (_) => _handleSilentSessionRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'menu_items',
          callback: (_) => _handleSilentMenuRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'restaurant_tables',
          callback: (_) => _handleSilentTablesRefresh(),
        )
        .subscribe();
  }

  /// Silently refreshes menu items when admin updates stock or availability in real time.
  Future<void> _handleSilentMenuRefresh() async {
    if (!_mounted) return;
    try {
      final updatedMenuItems = await _repository.fetchMenuItems(onlyAvailable: true);
      if (!_mounted) return;

      final availableIds = {for (var m in updatedMenuItems) m.id};
      final updatedCart = Map<String, CartItem>.from(state.cart);
      updatedCart.removeWhere((key, _) => !availableIds.contains(key));

      state = state.copyWith(
        menuItems: updatedMenuItems,
        cart: updatedCart,
      );
    } catch (e) {
      debugPrint('Silent menu refresh error: $e');
    }
  }

  /// Silently refreshes tables when admin toggles table active/inactive in real time.
  Future<void> _handleSilentTablesRefresh() async {
    if (!_mounted) return;
    try {
      final updatedTables = await _repository.fetchTables();
      if (!_mounted) return;
      RestaurantTable? newActiveTable = state.activeTable;
      if (newActiveTable != null) {
        final found = updatedTables.firstWhere(
          (t) => t.id == newActiveTable!.id,
          orElse: () => newActiveTable!,
        );
        newActiveTable = found;
        if (!newActiveTable.isActive) {
          state = state.copyWith(
            tables: updatedTables,
            activeTable: () => null,
            activeSessionDetails: () => null,
            selectedCustomer: () => null,
            currentStep: ServerViewStep.tableSelection,
          );
          return;
        }
      }
      state = state.copyWith(
        tables: updatedTables,
        activeTable: () => newActiveTable,
      );
    } catch (e) {
      debugPrint('Silent tables refresh error: $e');
    }
  }

  /// Silently synchronizes the open table's session in the background.
  Future<void> _handleSilentSessionRefresh() async {
    if (!_mounted || state.activeTable == null) return;
    try {
      final activeTableId = state.activeTable!.id;
      final session = await _repository.fetchActiveTableSession(activeTableId);
      if (!_mounted) return;

      // If all customers settled and table is no longer active:
      if (session.customers.isEmpty && !session.isActive) {
        final tables = await _repository.fetchTables();
        state = state.copyWith(
          tables: tables,
          activeTable: () => null,
          activeSessionDetails: () => null,
          selectedCustomer: () => null,
          currentStep: ServerViewStep.tableSelection,
        );
      } else {
        SessionCustomer? newSelectedCust = state.selectedCustomer;
        if (newSelectedCust != null &&
            !session.customers.any((c) => c.id == newSelectedCust!.id)) {
          newSelectedCust = session.customers.isNotEmpty ? session.customers.first : null;
        }

        state = state.copyWith(
          activeSessionDetails: () => session,
          selectedCustomer: () => newSelectedCust,
        );
      }
    } catch (e) {
      debugPrint('Silent session refresh note: $e');
    }
  }

  /// Open or retrieve an active table session, transitioning to Step 2: Table Context.
  /// Does NOT modify table occupancy or create default customers if the table is empty.
  Future<void> openTable(RestaurantTable table) async {
    state = state.copyWith(isLoading: true, errorMessage: () => null);

    try {
      final sessionDetails = await _repository.fetchActiveTableSession(table.id);

      state = state.copyWith(
        activeTable: () => table,
        activeSessionDetails: () => sessionDetails,
        currentStep: ServerViewStep.tableContext,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('Error opening table: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: () => 'Failed to open table: $e',
      );
    }
  }

  /// Open or retrieve table session and directly navigate to the Order Screen.
  Future<void> openTableOrderScreen(RestaurantTable table, {SessionCustomer? customer}) async {
    state = state.copyWith(isLoading: true, errorMessage: () => null);

    try {
      final sessionDetails = await _repository.fetchActiveTableSession(table.id);

      final selectedCust = customer ??
          (sessionDetails.customers.isNotEmpty
              ? sessionDetails.customers.first
              : null);

      final firstCategoryId =
          state.categories.isNotEmpty ? state.categories.first.id : null;

      state = state.copyWith(
        activeTable: () => table,
        activeSessionDetails: () => sessionDetails,
        selectedCustomer: () => selectedCust,
        selectedCategoryId: () => firstCategoryId,
        searchQuery: () => null,
        cart: {},
        orderNotes: () => null,
        currentStep: ServerViewStep.customerOrdering,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('Error opening table order screen: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: () => 'Failed to open table: $e',
      );
    }
  }

  /// Quick lookup by numeric or alphanumeric table number (e.g. "5" or "T-05").
  Future<void> openTableByNumber(String input) async {
    final query = input.trim();
    if (query.isEmpty) return;

    final normalizedQuery = query.toLowerCase();

    // Match exact or trailing number
    final match = state.tables.where((t) {
      final num = t.tableNumber.toLowerCase();
      if (num == normalizedQuery) return true;
      if (num == 't-$normalizedQuery' || num == 't-0$normalizedQuery') return true;
      final digits = num.replaceAll(RegExp(r'\D'), '');
      final queryDigits = normalizedQuery.replaceAll(RegExp(r'\D'), '');
      return digits.isNotEmpty && queryDigits.isNotEmpty && digits == queryDigits;
    }).toList();

    if (match.isEmpty) {
      state = state.copyWith(
        errorMessage: () => 'Table "$query" not found in active restaurant layout.',
      );
      return;
    }

    await openTable(match.first);
  }

  /// Return to Step 1: Table Selection (clearing active table).
  void returnToTableSelection() {
    state = state.copyWith(
      activeTable: () => null,
      activeSessionDetails: () => null,
      selectedCustomer: () => null,
      cart: {},
      currentStep: ServerViewStep.tableSelection,
      errorMessage: () => null,
    );
  }

  /// Refresh active session details (customers, orders, totals).
  Future<void> refreshActiveSession() async {
    if (state.activeTable == null) return;

    try {
      final sessionDetails =
          await _repository.fetchActiveTableSession(state.activeTable!.id);
      state = state.copyWith(
        activeSessionDetails: () => sessionDetails,
      );
    } catch (e) {
      debugPrint('Error refreshing table session: $e');
    }
  }

  /// Add a new customer to the active table session.
  /// If the table does not have an active session in the database yet,
  /// seats the customer as a pending guest without marking the table as occupied.
  Future<void> addCustomerToTable({String? name, String? phone}) async {
    if (state.activeTable == null) return;

    state = state.copyWith(isLoading: true, errorMessage: () => null);

    try {
      final sessionId = state.activeSessionDetails?.sessionId;
      if (sessionId != null && sessionId.isNotEmpty) {
        // Table already has an active DB session -> add directly to DB session
        await _repository.addCustomerToSession(
          sessionId,
          name: name,
          phone: phone,
        );

        final sessionDetails =
            await _repository.fetchActiveTableSession(state.activeTable!.id);

        state = state.copyWith(
          activeSessionDetails: () => sessionDetails,
          isLoading: false,
        );
      } else {
        // Table does NOT have an active session in DB yet.
        // We add the customer as a pending seated customer locally.
        // The table in DB remains AVAILABLE until the customer places an order!
        final currentCustomers = state.activeSessionDetails?.customers ?? [];
        final nextNum = currentCustomers.length + 1;
        final label = name?.trim().isNotEmpty == true
            ? name!.trim()
            : 'Customer $nextNum';

        final newCustomer = SessionCustomer(
          id: 'pending_${DateTime.now().millisecondsSinceEpoch}_$nextNum',
          sessionId: '',
          customerLabel: label,
          customerName: name?.trim().isNotEmpty == true ? name!.trim() : null,
          customerPhone: phone?.trim().isNotEmpty == true ? phone!.trim() : null,
          status: CustomerStatus.active,
        );

        final updatedSession = (state.activeSessionDetails ??
                TableSessionDetails(
                  tableId: state.activeTable!.id,
                  tableNumber: state.activeTable!.tableNumber,
                  seatingCapacity: state.activeTable!.seatingCapacity,
                  tableStatus: state.activeTable!.status,
                  status: 'available',
                ))
            .copyWith(
          customers: [...currentCustomers, newCustomer],
        );

        state = state.copyWith(
          activeSessionDetails: () => updatedSession,
          isLoading: false,
        );
      }
    } catch (e) {
      debugPrint('Error adding customer: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: () => 'Failed to add customer: $e',
      );
    }
  }

  /// Select customer to take an order, transitioning to Step 3: Customer Ordering Screen.
  void selectCustomerForOrdering(SessionCustomer customer) {
    if (!customer.canOrder) {
      state = state.copyWith(
        errorMessage: () =>
            'Customer "${customer.displayName}" has completed ordering and cannot place new orders.',
      );
      return;
    }

    // Categories on the LEFT: default to first category if available
    final firstCategoryId =
        state.categories.isNotEmpty ? state.categories.first.id : null;

    state = state.copyWith(
      selectedCustomer: () => customer,
      selectedCategoryId: () => firstCategoryId,
      searchQuery: () => null,
      cart: {},
      orderNotes: () => null,
      editingOrderId: () => null,
      editingOrderNumber: () => null,
      currentStep: ServerViewStep.customerOrdering,
      errorMessage: () => null,
    );
  }

  /// Start editing an existing order in full-screen POS mode (Scenario A).
  Future<bool> startEditingOrder(
      SessionCustomer customer, SessionOrderSummary order) async {
    state = state.copyWith(isLoading: true, errorMessage: () => null);

    try {
      final details = await _repository.fetchOrderDetails(order.id);
      final catalogMap = {for (var m in state.menuItems) m.id: m};

      final Map<String, CartItem> loadedCart = {};
      final rawItems = details['items'] as List<dynamic>? ?? [];
      for (final raw in rawItems) {
        final map = raw as Map<String, dynamic>;
        final menuItemId = map['menu_item_id'] as String;
        final qty = (map['quantity'] as num?)?.toInt() ?? 1;
        final instructions = map['special_instructions'] as String?;
        final unitPrice = (map['unit_price'] as num?)?.toDouble() ?? 0.0;
        final itemName = map['item_name'] as String? ?? 'Item';

        MenuItem item;
        if (catalogMap.containsKey(menuItemId)) {
          item = catalogMap[menuItemId]!;
        } else {
          item = MenuItem(
            id: menuItemId,
            categoryId: '',
            name: itemName,
            basePrice: unitPrice,
            isAvailable: true,
            isActive: true,
            displayOrder: 0,
          );
        }

        loadedCart[menuItemId] = CartItem(
          menuItem: item,
          quantity: qty,
          specialInstructions: instructions,
        );
      }

      final rawNotes = details['notes'] as String?;
      final firstCategoryId =
          state.categories.isNotEmpty ? state.categories.first.id : null;

      state = state.copyWith(
        isLoading: false,
        selectedCustomer: () => customer,
        selectedCategoryId: () => firstCategoryId,
        cart: loadedCart,
        orderNotes: () => rawNotes,
        editingOrderId: () => order.id,
        editingOrderNumber: () => order.orderNumber,
        currentStep: ServerViewStep.customerOrdering,
        errorMessage: () => null,
      );
      return true;
    } catch (e) {
      debugPrint('Failed to load order for editing: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: () => 'Failed to load order: $e',
      );
      return false;
    }
  }

  /// Return from Ordering screen back to Step 2: Table Context.
  void returnToTableContext() {
    state = state.copyWith(
      cart: {},
      orderNotes: () => null,
      editingOrderId: () => null,
      editingOrderNumber: () => null,
      searchQuery: () => null,
      currentStep: ServerViewStep.tableContext,
      errorMessage: () => null,
    );
    // Refresh to get latest orders
    refreshActiveSession();
  }

  /// Select category in the left navigation panel.
  /// Reset search query when user explicitly taps a category.
  void selectCategory(String? categoryId) {
    state = state.copyWith(
      selectedCategoryId: () => categoryId,
      searchQuery: () => null,
    );
  }

  /// Update menu search query. When non-empty, filteredMenuItems searches across all categories.
  void setSearchQuery(String? query) {
    state = state.copyWith(searchQuery: () => query);
  }

  /// Clear menu search query.
  void clearSearchQuery() {
    state = state.copyWith(searchQuery: () => null);
  }

  /// Set default dining mode for adding new items (Dine-In vs Parcel).
  void setDefaultDiningMode(bool isParcel) {
    state = state.copyWith(defaultDiningModeIsParcel: isParcel);
  }

  /// Toggle parcel status for a specific cart item.
  void toggleItemParcel(String menuItemId) {
    final updatedCart = Map<String, CartItem>.from(state.cart);
    final existing = updatedCart[menuItemId];
    if (existing != null) {
      updatedCart[menuItemId] = existing.copyWith(isParcel: !existing.isParcel);
      state = state.copyWith(cart: updatedCart);
    }
  }

  /// Mark all items in the active cart as parcel or dine-in.
  void setAllParcel(bool isParcel) {
    final updatedCart = Map<String, CartItem>.from(state.cart);
    for (final entry in updatedCart.entries) {
      updatedCart[entry.key] = entry.value.copyWith(isParcel: isParcel);
    }
    state = state.copyWith(
      cart: updatedCart,
      defaultDiningModeIsParcel: isParcel,
    );
  }

  /// Set quantity directly on card.
  void setItemQuantity(MenuItem item, int newQty) {
    final updatedCart = Map<String, CartItem>.from(state.cart);

    if (newQty <= 0) {
      updatedCart.remove(item.id);
    } else {
      final existing = updatedCart[item.id];
      updatedCart[item.id] = CartItem(
        menuItem: item,
        quantity: newQty,
        selectedAddons: existing?.selectedAddons ?? const [],
        isParcel: existing?.isParcel ?? state.defaultDiningModeIsParcel,
        specialInstructions: existing?.specialInstructions,
      );
    }

    state = state.copyWith(cart: updatedCart);
  }

  /// Add or update a configured CartItem (with specific add-ons / parcel).
  void setConfiguredItem(CartItem item) {
    final updatedCart = Map<String, CartItem>.from(state.cart);
    if (item.quantity <= 0) {
      updatedCart.remove(item.menuItem.id);
    } else {
      updatedCart[item.menuItem.id] = item;
    }
    state = state.copyWith(cart: updatedCart);
  }

  /// Increment quantity on card.
  void addItem(MenuItem item) {
    final currentQty = state.getQuantityInCart(item.id);
    setItemQuantity(item, currentQty + 1);
  }

  /// Decrement quantity on card.
  void decrementItem(String menuItemId) {
    final currentQty = state.getQuantityInCart(menuItemId);
    if (currentQty <= 0) return;

    final updatedCart = Map<String, CartItem>.from(state.cart);
    if (currentQty - 1 <= 0) {
      updatedCart.remove(menuItemId);
    } else {
      final existing = updatedCart[menuItemId]!;
      updatedCart[menuItemId] = existing.copyWith(quantity: currentQty - 1);
    }

    state = state.copyWith(cart: updatedCart);
  }

  /// Remove item completely from cart.
  void removeItem(String menuItemId) {
    final updatedCart = Map<String, CartItem>.from(state.cart);
    updatedCart.remove(menuItemId);
    state = state.copyWith(cart: updatedCart);
  }

  /// Update order notes.
  void setOrderNotes(String notes) {
    state = state.copyWith(
      orderNotes: () => notes.trim().isNotEmpty ? notes.trim() : null,
    );
  }

  /// Submit current order atomically via RPC `submit_dine_in_order`, or update existing order if in edit mode.
  Future<bool> submitOrder() async {
    if (state.isEditingOrder) {
      return await _submitUpdatedOrder();
    }

    if (state.selectedCustomer != null && !state.selectedCustomer!.canOrder) {
      state = state.copyWith(
        errorMessage: () =>
            'Customer "${state.selectedCustomer!.displayName}" has completed ordering and cannot place new orders.',
      );
      return false;
    }

    if (!state.canSubmitOrder) {
      state = state.copyWith(
        errorMessage: () => 'Please select items to place an order.',
      );
      return false;
    }

    state = state.copyWith(isSubmitting: true, errorMessage: () => null);

    try {
      final items = state.cart.values.toList();
      final hasRealSession = state.activeSessionDetails?.sessionId != null &&
          state.activeSessionDetails!.sessionId!.isNotEmpty;
      final custId = state.selectedCustomer?.id;
      final isRealCustId = custId != null && !custId.startsWith('pending');

      final result = await _repository.submitDineInOrder(
        tableId: state.activeTable!.id,
        sessionId: hasRealSession ? state.activeSessionDetails!.sessionId : null,
        sessionCustomerId: isRealCustId ? custId : null,
        customerName: state.selectedCustomer?.displayName,
        customerPhone: state.selectedCustomer?.customerPhone,
        items: items,
        notes: state.orderNotes,
      );

      // Refresh table session details from database
      final updatedDetails =
          await _repository.fetchActiveTableSession(state.activeTable!.id);

      // If we previously had other pending customers seated locally, sync them to the newly opened DB session
      if (!hasRealSession && updatedDetails.sessionId != null) {
        final remainingPending = state.activeSessionDetails?.customers.where(
              (c) => c.id.startsWith('pending') && c.id != custId,
            ) ??
            [];
        for (final pendingCust in remainingPending) {
          try {
            await _repository.addCustomerToSession(
              updatedDetails.sessionId!,
              name: pendingCust.customerName,
              phone: pendingCust.customerPhone,
            );
          } catch (e) {
            debugPrint('Error syncing pending customer: $e');
          }
        }
      }

      // Re-fetch after syncing any remaining customers
      final finalDetails = (!hasRealSession && updatedDetails.sessionId != null)
          ? await _repository.fetchActiveTableSession(state.activeTable!.id)
          : updatedDetails;

      final updatedTable = state.activeTable?.copyWith(status: 'occupied');
      final updatedTables = state.tables.map((t) {
        if (t.id == state.activeTable?.id) {
          return t.copyWith(status: 'occupied');
        }
        return t;
      }).toList();

      state = state.copyWith(
        isSubmitting: false,
        cart: {},
        orderNotes: () => null,
        tables: updatedTables,
        activeTable: () => updatedTable,
        activeSessionDetails: () => finalDetails,
        submittedOrderResult: () => result,
      );

      return true;
    } on CustomerCannotOrderException catch (e) {
      debugPrint('Order submission rejected: customer cannot order: $e');
      // Race condition: another device finished the customer while this order was being prepared.
      // Reconcile authoritative session state from database while preserving the user's cart!
      TableSessionDetails? updatedDetails;
      if (state.activeTable != null) {
        try {
          updatedDetails =
              await _repository.fetchActiveTableSession(state.activeTable!.id);
        } catch (_) {}
      }

      SessionCustomer? updatedCustomer = state.selectedCustomer;
      if (updatedDetails != null && state.selectedCustomer != null) {
        final found = updatedDetails.customers
            .where((c) => c.id == state.selectedCustomer!.id);
        if (found.isNotEmpty) {
          updatedCustomer = found.first;
        }
      }

      state = state.copyWith(
        isSubmitting: false,
        activeSessionDetails:
            updatedDetails != null ? () => updatedDetails : null,
        selectedCustomer:
            updatedCustomer != null ? () => updatedCustomer : null,
        errorMessage: () => e.message,
      );
      return false;
    } catch (e) {
      debugPrint('Order submission failed: $e');
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: () => 'Order submission failed: $e',
      );
      return false;
    }
  }

  /// Submit in-place order update when editing an existing order.
  Future<bool> _submitUpdatedOrder() async {
    if (state.cart.isEmpty) {
      state = state.copyWith(
        errorMessage: () =>
            'Order must contain at least one item. To cancel the order, use Cancel Order.',
      );
      return false;
    }

    state = state.copyWith(isSubmitting: true, errorMessage: () => null);

    try {
      final orderId = state.editingOrderId!;
      final result = await _repository.updateOrder(
        orderId,
        items: state.cart.values.toList(),
        notes: state.orderNotes,
      );

      // Refresh table session details to reflect updated order totals
      TableSessionDetails? updatedDetails;
      if (state.activeTable != null) {
        updatedDetails =
            await _repository.fetchActiveTableSession(state.activeTable!.id);
      }

      state = state.copyWith(
        isSubmitting: false,
        cart: {},
        orderNotes: () => null,
        editingOrderId: () => null,
        editingOrderNumber: () => null,
        activeSessionDetails:
            updatedDetails != null ? () => updatedDetails : null,
        submittedOrderResult: () => result,
      );

      return true;
    } catch (e) {
      debugPrint('Order update failed: $e');
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: () => 'Failed to update order: $e',
      );
      return false;
    }
  }

  /// Dismiss the order success modal.
  /// If [continueWithSameCustomer] is true, stays in ordering screen with a fresh cart.
  /// Otherwise, returns to Step 2: Table Context.
  void acknowledgeOrderSuccess({bool continueWithSameCustomer = false}) {
    state = state.copyWith(
      submittedOrderResult: () => null,
      currentStep: continueWithSameCustomer
          ? ServerViewStep.customerOrdering
          : ServerViewStep.tableContext,
    );
  }

  /// Cancel an individual order independently.
  /// Cancel an individual server order independently.
  /// If the customer has no other active orders, they are deleted automatically.
  Future<bool> cancelOrder(String orderId, {String? reason}) async {
    state = state.copyWith(isLoading: true, errorMessage: () => null);

    try {
      await _repository.cancelOrder(orderId, reason: reason);

      // Refresh session details to reflect updated cancellation state and active total
      if (state.activeTable != null) {
        final updatedDetails =
            await _repository.fetchActiveTableSession(state.activeTable!.id);
        final updatedTables = await _repository.fetchTables();

        RestaurantTable? updatedActiveTable = state.activeTable;
        final matching = updatedTables.where((t) => t.id == state.activeTable!.id);
        if (matching.isNotEmpty) {
          updatedActiveTable = matching.first;
        }

        SessionCustomer? updatedSelected = state.selectedCustomer;
        if (updatedDetails.customers.isEmpty ||
            !updatedDetails.customers.any((c) => c.id == updatedSelected?.id)) {
          updatedSelected = null;
        }

        state = state.copyWith(
          activeTable: () => updatedActiveTable,
          activeSessionDetails: () => updatedDetails,
          selectedCustomer: () => updatedSelected,
          tables: updatedTables,
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }

      return true;
    } catch (e) {
      debugPrint('Order cancellation failed: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: () => 'Cancellation failed: $e',
      );
      return false;
    }
  }

  /// Delete a session customer from table session when they have no active orders.
  Future<bool> deleteCustomer(String customerId) async {
    state = state.copyWith(isLoading: true, errorMessage: () => null);

    try {
      final isPending = customerId.startsWith('pending_');
      if (!isPending) {
        await _repository.deleteSessionCustomer(customerId);
      }

      if (state.activeTable != null) {
        TableSessionDetails? updatedDetails;
        if (!isPending) {
          updatedDetails =
              await _repository.fetchActiveTableSession(state.activeTable!.id);
        } else {
          final currentCusts = state.activeSessionDetails?.customers ?? [];
          final filtered = currentCusts.where((c) => c.id != customerId).toList();
          updatedDetails = state.activeSessionDetails?.copyWith(customers: filtered);
        }
        final updatedTables = await _repository.fetchTables();

        RestaurantTable? updatedActiveTable = state.activeTable;
        final matching = updatedTables.where((t) => t.id == state.activeTable!.id);
        if (matching.isNotEmpty) {
          updatedActiveTable = matching.first;
        }

        SessionCustomer? updatedSelected = state.selectedCustomer;
        if (state.selectedCustomer?.id == customerId) {
          updatedSelected = null;
        }

        state = state.copyWith(
          activeTable: () => updatedActiveTable,
          activeSessionDetails: () => updatedDetails,
          selectedCustomer: () => updatedSelected,
          tables: updatedTables,
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }

      return true;
    } catch (e) {
      debugPrint('Error deleting customer: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: () => 'Failed to remove customer: $e',
      );
      return false;
    }
  }

  /// Transfer a customer and all their active orders to another table.
  /// Handles both database-backed customers and local pending customers.
  Future<Map<String, dynamic>?> swapCustomerTable({
    required SessionCustomer customer,
    required RestaurantTable targetTable,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: () => null);

    try {
      final isPending = customer.id.startsWith('pending_');
      if (isPending) {
        // Customer has no active orders in DB yet; transfer locally to target table.
        final currentCusts = state.activeSessionDetails?.customers ?? [];
        final filtered = currentCusts.where((c) => c.id != customer.id).toList();
        final updatedSourceDetails = state.activeSessionDetails?.copyWith(customers: filtered);

        state = state.copyWith(activeSessionDetails: () => updatedSourceDetails);

        // Open target table and add customer
        await openTable(targetTable);
        await addCustomerToTable(
          name: customer.customerName,
          phone: customer.customerPhone,
        );

        return {
          'success': true,
          'customer_id': customer.id,
          'target_table_id': targetTable.id,
          'target_table_number': targetTable.tableNumber,
          'source_table_freed': filtered.isEmpty,
        };
      }

      // Customer is saved in database: invoke atomic RPC
      final res = await _repository.swapCustomerTable(
        customerId: customer.id,
        targetTableId: targetTable.id,
      );

      final sourceTableFreed = res['source_table_freed'] == true;

      // Refresh all tables to reflect occupancy changes
      final updatedTables = await _repository.fetchTables();

      if (sourceTableFreed) {
        // Source table was completely freed; open target table so server sees the customer there
        final updatedTargetTable = updatedTables.firstWhere(
          (t) => t.id == targetTable.id,
          orElse: () => targetTable,
        );
        final targetSessionDetails =
            await _repository.fetchActiveTableSession(targetTable.id);

        state = state.copyWith(
          tables: updatedTables,
          activeTable: () => updatedTargetTable,
          activeSessionDetails: () => targetSessionDetails,
          selectedCustomer: () => null,
          currentStep: ServerViewStep.tableContext,
          isLoading: false,
        );
      } else {
        // Source table still has other seated customers
        if (state.activeTable != null) {
          final updatedActiveTable = updatedTables.firstWhere(
            (t) => t.id == state.activeTable!.id,
            orElse: () => state.activeTable!,
          );
          final updatedDetails =
              await _repository.fetchActiveTableSession(state.activeTable!.id);

          SessionCustomer? updatedSelected = state.selectedCustomer;
          if (state.selectedCustomer?.id == customer.id) {
            updatedSelected = null;
          }

          state = state.copyWith(
            tables: updatedTables,
            activeTable: () => updatedActiveTable,
            activeSessionDetails: () => updatedDetails,
            selectedCustomer: () => updatedSelected,
            isLoading: false,
          );
        } else {
          state = state.copyWith(
            tables: updatedTables,
            isLoading: false,
          );
        }
      }

      return res;
    } catch (e) {
      debugPrint('Error swapping customer table: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: () => 'Failed to swap customer table: $e',
      );
      return null;
    }
  }

  /// Fetch order details (including line items) for an existing order.
  Future<Map<String, dynamic>?> fetchOrderDetails(String orderId) async {
    try {
      return await _repository.fetchOrderDetails(orderId);
    } catch (e) {
      debugPrint('Failed to fetch order details: $e');
      return null;
    }
  }

  /// Update an existing order in-place without creating a new order.
  Future<bool> updateExistingOrder(
    String orderId, {
    required List<CartItem> items,
    String? notes,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: () => null);

    try {
      await _repository.updateOrder(orderId, items: items, notes: notes);

      // Refresh table session details to reflect updated order totals
      if (state.activeTable != null) {
        final updatedDetails =
            await _repository.fetchActiveTableSession(state.activeTable!.id);
        state = state.copyWith(
          activeSessionDetails: () => updatedDetails,
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }

      return true;
    } catch (e) {
      debugPrint('Order update failed: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: () => 'Failed to update order: $e',
      );
      return false;
    }
  }

  /// Finish customer ordering via authoritative RPC `finish_table_session_customer`.

  ///
  /// Transitions customer from active to finished. Reconciles authoritative session
  /// details from PostgreSQL and updates local state. Idempotently succeeds if
  /// customer was already marked finished.
  Future<bool> finishCustomer(String customerId) async {
    state = state.copyWith(isLoading: true, errorMessage: () => null);

    try {
      await _repository.finishCustomer(customerId);

      // Refresh authoritative session details from database
      if (state.activeTable != null) {
        final updatedDetails =
            await _repository.fetchActiveTableSession(state.activeTable!.id);

        SessionCustomer? updatedSelected = state.selectedCustomer;
        if (state.selectedCustomer?.id == customerId) {
          final match =
              updatedDetails.customers.where((c) => c.id == customerId);
          if (match.isNotEmpty) {
            updatedSelected = match.first;
          }
        }

        state = state.copyWith(
          activeSessionDetails: () => updatedDetails,
          selectedCustomer: () => updatedSelected,
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }

      return true;
    } catch (e) {
      debugPrint('Error finishing customer: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: () => e.toString(),
      );
      return false;
    }
  }

  /// Clear error banner.
  void clearError() {
    state = state.copyWith(errorMessage: () => null);
  }

  /// Backward compatibility alias for openTable.
  Future<void> selectTable(RestaurantTable table) => openTable(table);

  /// Backward compatibility helper for setting customer information.
  void setCustomerInfo({required String name, required String phone}) {
    if (state.selectedCustomer != null) {
      final updated = SessionCustomer(
        id: state.selectedCustomer!.id,
        sessionId: state.selectedCustomer!.sessionId,
        customerLabel: name.isNotEmpty ? name : state.selectedCustomer!.customerLabel,
        customerName: name,
        customerPhone: phone,
        orders: state.selectedCustomer!.orders,
        activeOrdersCount: state.selectedCustomer!.activeOrdersCount,
        activeTotal: state.selectedCustomer!.activeTotal,
      );
      state = state.copyWith(selectedCustomer: () => updated);
    }
  }
}
