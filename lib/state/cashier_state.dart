import 'package:flutter/foundation.dart' hide Category;
import '../models/models.dart';

/// Operational modes for Cashier terminal.
enum CashierMode {
  none,
  dineIn,
  parcel,
  expenses,
}

/// Navigation steps within Cashier workflow.
enum CashierStep {
  modeSelection,
  dineInQueue,
  tableDetail,
  parcelCustomer,
  parcelOrdering,
  billReview,
  paymentSettlement,
  receiptSuccess,
}

/// Immutable state for Cashier POS workflow.
@immutable
class CashierState {
  final CashierMode activeMode;
  final CashierStep currentStep;
  final bool isLoading;
  final bool isSubmitting;
  final String? errorMessage;

  // Catalog
  final List<Category> categories;
  final List<MenuItem> menuItems;
  final List<MenuAddon> availableAddons;

  // Dine-In State
  final List<RestaurantTable> tables;
  final TableSessionDetails? selectedTableSession;
  final SessionCustomer? selectedCustomer;
  final SessionOrderSummary? selectedOrder;

  // Bill & Payment State
  final Bill? activeBill;
  final Map<String, dynamic>? paymentResult;

  // Parcel State
  final String? parcelCustomerName;
  final String? parcelCustomerPhone;
  final Map<String, CartItem> parcelCart;
  final String? selectedCategoryId;
  final String? parcelNotes;

  const CashierState({
    this.activeMode = CashierMode.none,
    this.currentStep = CashierStep.modeSelection,
    this.isLoading = false,
    this.isSubmitting = false,
    this.errorMessage,
    this.categories = const [],
    this.menuItems = const [],
    this.availableAddons = const [],
    this.tables = const [],
    this.selectedTableSession,
    this.selectedCustomer,
    this.selectedOrder,
    this.activeBill,
    this.paymentResult,
    this.parcelCustomerName,
    this.parcelCustomerPhone,
    this.parcelCart = const {},
    this.selectedCategoryId,
    this.parcelNotes,
  });

  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;

  double get parcelCartSubtotal {
    double total = 0.0;
    for (final item in parcelCart.values) {
      total += item.itemTotal;
    }
    return total;
  }

  int get parcelCartCount {
    int count = 0;
    for (final item in parcelCart.values) {
      count += item.quantity;
    }
    return count;
  }

  List<MenuItem> get filteredMenuItems {
    final availableItems = menuItems.where((m) => m.isAvailable && m.isActive).toList();
    if (selectedCategoryId == null || selectedCategoryId!.isEmpty) {
      return availableItems;
    }
    return availableItems.where((m) => m.categoryId == selectedCategoryId).toList();
  }

  CashierState copyWith({
    CashierMode? activeMode,
    CashierStep? currentStep,
    bool? isLoading,
    bool? isSubmitting,
    ValueGetter<String?>? errorMessage,
    List<Category>? categories,
    List<MenuItem>? menuItems,
    List<MenuAddon>? availableAddons,
    List<RestaurantTable>? tables,
    ValueGetter<TableSessionDetails?>? selectedTableSession,
    ValueGetter<SessionCustomer?>? selectedCustomer,
    ValueGetter<SessionOrderSummary?>? selectedOrder,
    ValueGetter<Bill?>? activeBill,
    ValueGetter<Map<String, dynamic>?>? paymentResult,
    ValueGetter<String?>? parcelCustomerName,
    ValueGetter<String?>? parcelCustomerPhone,
    Map<String, CartItem>? parcelCart,
    ValueGetter<String?>? selectedCategoryId,
    ValueGetter<String?>? parcelNotes,
  }) {
    return CashierState(
      activeMode: activeMode ?? this.activeMode,
      currentStep: currentStep ?? this.currentStep,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      categories: categories ?? this.categories,
      menuItems: menuItems ?? this.menuItems,
      availableAddons: availableAddons ?? this.availableAddons,
      tables: tables ?? this.tables,
      selectedTableSession: selectedTableSession != null
          ? selectedTableSession()
          : this.selectedTableSession,
      selectedCustomer: selectedCustomer != null
          ? selectedCustomer()
          : this.selectedCustomer,
      selectedOrder:
          selectedOrder != null ? selectedOrder() : this.selectedOrder,
      activeBill: activeBill != null ? activeBill() : this.activeBill,
      paymentResult:
          paymentResult != null ? paymentResult() : this.paymentResult,
      parcelCustomerName: parcelCustomerName != null
          ? parcelCustomerName()
          : this.parcelCustomerName,
      parcelCustomerPhone: parcelCustomerPhone != null
          ? parcelCustomerPhone()
          : this.parcelCustomerPhone,
      parcelCart: parcelCart ?? this.parcelCart,
      selectedCategoryId: selectedCategoryId != null
          ? selectedCategoryId()
          : this.selectedCategoryId,
      parcelNotes: parcelNotes != null ? parcelNotes() : this.parcelNotes,
    );
  }
}
