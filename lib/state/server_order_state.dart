import 'package:flutter/foundation.dart' hide Category;
import '../models/models.dart';

/// Operational viewing modes for the Server POS interface.
enum ServerViewStep {
  /// Step 1: Physical table selection & numeric table entry. No menu visible.
  tableSelection,

  /// Step 2: Active Table Context. Shows seated customers, active totals,
  /// order history, cancellation actions, and "+ Add Customer".
  tableContext,

  /// Step 3: Dedicated Ordering Screen for a specific customer.
  /// Categories on the LEFT, Menu Item Cards in the CENTER, Cart on the RIGHT.
  customerOrdering,
}

/// Immutable state for the complete Fresh Cane Server Module.
@immutable
class ServerOrderState {
  final ServerViewStep currentStep;
  final List<RestaurantTable> tables;
  final List<Category> categories;
  final List<MenuItem> menuItems;
  final List<MenuAddon> availableAddons;

  /// The physical table currently opened by the server.
  final RestaurantTable? activeTable;

  /// Full aggregated session details for the active table (customers, orders, totals).
  final TableSessionDetails? activeSessionDetails;

  /// The customer currently being served in the ordering screen.
  final SessionCustomer? selectedCustomer;

  /// Active category selected in the dedicated left-side category strip.
  final String? selectedCategoryId;

  /// Uncommitted cart items for the currently selected customer.
  final Map<String, CartItem> cart;

  /// Special instructions / notes for the current order.
  final String? orderNotes;

  /// Identifier of an existing order currently being edited (null if creating a new order).
  final String? editingOrderId;

  /// Human-readable order number of the order being edited.
  final String? editingOrderNumber;

  final bool isLoading;
  final bool isSubmitting;
  final String? errorMessage;
  final Map<String, dynamic>? submittedOrderResult;
  final bool defaultDiningModeIsParcel;
  final String? searchQuery;

  const ServerOrderState({
    this.currentStep = ServerViewStep.tableSelection,
    this.tables = const [],
    this.categories = const [],
    this.menuItems = const [],
    this.availableAddons = MenuAddon.defaultAddons,
    this.activeTable,
    this.activeSessionDetails,
    this.selectedCustomer,
    this.selectedCategoryId,
    this.cart = const {},
    this.orderNotes,
    this.editingOrderId,
    this.editingOrderNumber,
    this.isLoading = false,
    this.isSubmitting = false,
    this.errorMessage,
    this.submittedOrderResult,
    this.defaultDiningModeIsParcel = false,
    this.searchQuery,
  });

  /// True if currently editing an existing placed order instead of taking a new one.
  bool get isEditingOrder => editingOrderId != null;

  /// Total count of individual physical items in the active cart.
  int get totalItemsCount =>
      cart.values.fold(0, (sum, item) => sum + item.quantity);

  /// Total count of items marked as parcel in the active cart.
  int get parcelItemsCount =>
      cart.values.where((item) => item.isParcel).fold(0, (sum, item) => sum + item.quantity);

  /// Whether all items in cart are marked as parcel.
  bool get isEntireOrderParcel =>
      cart.isNotEmpty && cart.values.every((item) => item.isParcel);

  /// Whether some items are parcel and some are dine-in.
  bool get isMixedDiningOrder =>
      cart.isNotEmpty &&
      cart.values.any((item) => item.isParcel) &&
      cart.values.any((item) => !item.isParcel);

  /// Calculated total currency amount for all items currently in cart.
  double get cartSubtotalAmount =>
      cart.values.fold(0.0, (sum, item) => sum + item.itemTotal);

  /// Compatibility alias for cartSubtotalAmount.
  double get subtotalAmount => cartSubtotalAmount;

  /// Grand total for the uncommitted cart.
  double get cartGrandTotal => cartSubtotalAmount;

  /// Compatibility alias for cartGrandTotal.
  double get grandTotalAmount => cartGrandTotal;

  /// Compatibility alias for activeTable.
  RestaurantTable? get selectedTable => activeTable;

  /// Compatibility alias for selected customer name.
  String get customerName => selectedCustomer?.displayName ?? '';

  /// Compatibility alias for selected customer phone.
  String get customerPhone => selectedCustomer?.customerPhone ?? '';

  /// Check whether order fulfills all required invariants to be submitted:
  /// 1. Table is active
  /// 2. Customer is selected and active (canOrder)
  /// 3. At least one line item is added
  /// 4. Not currently submitting
  bool get canSubmitOrder =>
      activeTable != null &&
      selectedCustomer != null &&
      selectedCustomer!.canOrder &&
      cart.isNotEmpty &&
      !isSubmitting &&
      !isLoading;

  /// Menu items filtered by search query (across all categories) or by the currently active category.
  /// Only in-stock and active items are presented for order taking.
  List<MenuItem> get filteredMenuItems {
    final availableItems = menuItems.where((m) => m.isAvailable && m.isActive).toList();

    if (searchQuery != null && searchQuery!.trim().isNotEmpty) {
      final q = searchQuery!.trim().toLowerCase();
      return availableItems.where((m) =>
          m.name.toLowerCase().contains(q) ||
          (m.description?.toLowerCase().contains(q) ?? false)
      ).toList();
    }
    if (selectedCategoryId == null) {
      return availableItems;
    }
    return availableItems.where((m) => m.categoryId == selectedCategoryId).toList();
  }

  /// Get active quantity of a specific menu item currently in cart.
  int getQuantityInCart(String menuItemId) {
    return cart[menuItemId]?.quantity ?? 0;
  }

  /// Get count of items available in a given category.
  int getItemCountForCategory(String categoryId) {
    return menuItems.where((m) => m.categoryId == categoryId && m.isAvailable && m.isActive).length;
  }

  ServerOrderState copyWith({
    ServerViewStep? currentStep,
    List<RestaurantTable>? tables,
    List<Category>? categories,
    List<MenuItem>? menuItems,
    List<MenuAddon>? availableAddons,
    RestaurantTable? Function()? activeTable,
    RestaurantTable? Function()? selectedTable,
    TableSessionDetails? Function()? activeSessionDetails,
    SessionCustomer? Function()? selectedCustomer,
    String? Function()? customerName,
    String? Function()? customerPhone,
    String? Function()? selectedCategoryId,
    Map<String, CartItem>? cart,
    String? Function()? orderNotes,
    String? Function()? editingOrderId,
    String? Function()? editingOrderNumber,
    bool? isLoading,
    bool? isSubmitting,
    String? Function()? errorMessage,
    Map<String, dynamic>? Function()? submittedOrderResult,
    bool? defaultDiningModeIsParcel,
    String? Function()? searchQuery,
  }) {
    final effectiveTable = selectedTable != null
        ? selectedTable()
        : (activeTable != null ? activeTable() : this.activeTable);

    return ServerOrderState(
      currentStep: currentStep ?? this.currentStep,
      tables: tables ?? this.tables,
      categories: categories ?? this.categories,
      menuItems: menuItems ?? this.menuItems,
      availableAddons: availableAddons ?? this.availableAddons,
      activeTable: effectiveTable,
      activeSessionDetails: activeSessionDetails != null
          ? activeSessionDetails()
          : this.activeSessionDetails,
      selectedCustomer: selectedCustomer != null
          ? selectedCustomer()
          : this.selectedCustomer,
      selectedCategoryId: selectedCategoryId != null
          ? selectedCategoryId()
          : this.selectedCategoryId,
      cart: cart ?? this.cart,
      orderNotes: orderNotes != null ? orderNotes() : this.orderNotes,
      editingOrderId:
          editingOrderId != null ? editingOrderId() : this.editingOrderId,
      editingOrderNumber: editingOrderNumber != null
          ? editingOrderNumber()
          : this.editingOrderNumber,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      submittedOrderResult: submittedOrderResult != null
          ? submittedOrderResult()
          : this.submittedOrderResult,
      defaultDiningModeIsParcel:
          defaultDiningModeIsParcel ?? this.defaultDiningModeIsParcel,
      searchQuery: searchQuery != null ? searchQuery() : this.searchQuery,
    );
  }
}
