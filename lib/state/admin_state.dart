import 'package:flutter/foundation.dart';
import '../models/expense_model.dart';

enum AdminDateFilter {
  today,
  yesterday,
  thisWeek,
  thisMonth,
  custom,
}

extension AdminDateFilterExtension on AdminDateFilter {
  String get label {
    switch (this) {
      case AdminDateFilter.today:
        return 'Today';
      case AdminDateFilter.yesterday:
        return 'Yesterday';
      case AdminDateFilter.thisWeek:
        return 'This Week';
      case AdminDateFilter.thisMonth:
        return 'This Month';
      case AdminDateFilter.custom:
        return 'Custom';
    }
  }

  DateTime get startDate {
    final now = DateTime.now();
    switch (this) {
      case AdminDateFilter.today:
        return DateTime(now.year, now.month, now.day);
      case AdminDateFilter.yesterday:
        final y = now.subtract(const Duration(days: 1));
        return DateTime(y.year, y.month, y.day);
      case AdminDateFilter.thisWeek:
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return DateTime(monday.year, monday.month, monday.day);
      case AdminDateFilter.thisMonth:
        return DateTime(now.year, now.month, 1);
      case AdminDateFilter.custom:
        return DateTime(now.year, now.month, now.day);
    }
  }

  DateTime get endDate {
    final now = DateTime.now();
    switch (this) {
      case AdminDateFilter.yesterday:
        final y = now.subtract(const Duration(days: 1));
        return DateTime(y.year, y.month, y.day);
      default:
        return DateTime(now.year, now.month, now.day);
    }
  }
}

@immutable
class AdminState {
  final int selectedNavIndex;
  final AdminDateFilter dateFilter;
  final DateTime customStartDate;
  final DateTime customEndDate;

  // Dashboard
  final bool isLoadingDashboard;
  final Map<String, dynamic>? dashboardMetrics;

  // Reports
  final String selectedReportType;
  final bool isLoadingReport;
  final List<Map<String, dynamic>> reportRows;
  final bool isExporting;

  // Expenses Management
  final bool isLoadingExpenses;
  final List<ExpenseDefinition> expenseDefinitions;
  final List<ExpenseTransaction> expenseTransactions;
  final Map<String, dynamic>? expenseSummary;
  final String? selectedExpenseDefinitionFilter;
  final String? selectedExpenseSubCategoryFilter;
  final String? selectedExpenseTypeFilter;
  final String? selectedExpensePaymentMethodFilter;
  final String selectedExpenseStatusFilter; // 'all', 'active_only', 'deleted_only'

  // Menu Management
  final bool isLoadingMenu;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> menuItems;
  final List<Map<String, dynamic>> addons;
  final List<Map<String, dynamic>> offers;

  // Operations & Master Data
  final bool isLoadingTables;
  final List<Map<String, dynamic>> tables;
  final bool isLoadingCustomers;
  final List<Map<String, dynamic>> customers;
  final bool isLoadingAuditLogs;
  final List<Map<String, dynamic>> auditLogs;
  final Map<String, dynamic>? storeSettings;

  final String? errorMessage;
  final String? successMessage;

  const AdminState({
    this.selectedNavIndex = 0,
    this.dateFilter = AdminDateFilter.thisMonth,
    required this.customStartDate,
    required this.customEndDate,
    this.isLoadingDashboard = false,
    this.dashboardMetrics,
    this.selectedReportType = 'sales',
    this.isLoadingReport = false,
    this.reportRows = const [],
    this.isExporting = false,
    this.isLoadingExpenses = false,
    this.expenseDefinitions = const [],
    this.expenseTransactions = const [],
    this.expenseSummary,
    this.selectedExpenseDefinitionFilter,
    this.selectedExpenseSubCategoryFilter,
    this.selectedExpenseTypeFilter,
    this.selectedExpensePaymentMethodFilter,
    this.selectedExpenseStatusFilter = 'all',
    this.isLoadingMenu = false,
    this.categories = const [],
    this.menuItems = const [],
    this.addons = const [],
    this.offers = const [],
    this.isLoadingTables = false,
    this.tables = const [],
    this.isLoadingCustomers = false,
    this.customers = const [],
    this.isLoadingAuditLogs = false,
    this.auditLogs = const [],
    this.storeSettings,
    this.errorMessage,
    this.successMessage,
  });

  factory AdminState.initial() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return AdminState(
      customStartDate: today,
      customEndDate: today,
    );
  }

  DateTime get effectiveStartDate =>
      dateFilter == AdminDateFilter.custom ? customStartDate : dateFilter.startDate;

  DateTime get effectiveEndDate =>
      dateFilter == AdminDateFilter.custom ? customEndDate : dateFilter.endDate;

  AdminState copyWith({
    int? selectedNavIndex,
    AdminDateFilter? dateFilter,
    DateTime? customStartDate,
    DateTime? customEndDate,
    bool? isLoadingDashboard,
    Map<String, dynamic>? dashboardMetrics,
    String? selectedReportType,
    bool? isLoadingReport,
    List<Map<String, dynamic>>? reportRows,
    bool? isExporting,
    bool? isLoadingExpenses,
    List<ExpenseDefinition>? expenseDefinitions,
    List<ExpenseTransaction>? expenseTransactions,
    Map<String, dynamic>? expenseSummary,
    String? selectedExpenseDefinitionFilter,
    String? selectedExpenseSubCategoryFilter,
    String? selectedExpenseTypeFilter,
    String? selectedExpensePaymentMethodFilter,
    String? selectedExpenseStatusFilter,
    bool? isLoadingMenu,
    List<Map<String, dynamic>>? categories,
    List<Map<String, dynamic>>? menuItems,
    List<Map<String, dynamic>>? addons,
    List<Map<String, dynamic>>? offers,
    bool? isLoadingTables,
    List<Map<String, dynamic>>? tables,
    bool? isLoadingCustomers,
    List<Map<String, dynamic>>? customers,
    bool? isLoadingAuditLogs,
    List<Map<String, dynamic>>? auditLogs,
    Map<String, dynamic>? storeSettings,
    String? errorMessage,
    String? successMessage,
    bool clearError = false,
    bool clearSuccess = false,
    bool clearDefinitionFilter = false,
    bool clearSubCategoryFilter = false,
  }) {
    return AdminState(
      selectedNavIndex: selectedNavIndex ?? this.selectedNavIndex,
      dateFilter: dateFilter ?? this.dateFilter,
      customStartDate: customStartDate ?? this.customStartDate,
      customEndDate: customEndDate ?? this.customEndDate,
      isLoadingDashboard: isLoadingDashboard ?? this.isLoadingDashboard,
      dashboardMetrics: dashboardMetrics ?? this.dashboardMetrics,
      selectedReportType: selectedReportType ?? this.selectedReportType,
      isLoadingReport: isLoadingReport ?? this.isLoadingReport,
      reportRows: reportRows ?? this.reportRows,
      isExporting: isExporting ?? this.isExporting,
      isLoadingExpenses: isLoadingExpenses ?? this.isLoadingExpenses,
      expenseDefinitions: expenseDefinitions ?? this.expenseDefinitions,
      expenseTransactions: expenseTransactions ?? this.expenseTransactions,
      expenseSummary: expenseSummary ?? this.expenseSummary,
      selectedExpenseDefinitionFilter: clearDefinitionFilter
          ? null
          : (selectedExpenseDefinitionFilter ?? this.selectedExpenseDefinitionFilter),
      selectedExpenseSubCategoryFilter: (clearSubCategoryFilter || clearDefinitionFilter)
          ? null
          : (selectedExpenseSubCategoryFilter ?? this.selectedExpenseSubCategoryFilter),
      selectedExpenseTypeFilter: selectedExpenseTypeFilter ?? this.selectedExpenseTypeFilter,
      selectedExpensePaymentMethodFilter: selectedExpensePaymentMethodFilter ?? this.selectedExpensePaymentMethodFilter,
      selectedExpenseStatusFilter: selectedExpenseStatusFilter ?? this.selectedExpenseStatusFilter,
      isLoadingMenu: isLoadingMenu ?? this.isLoadingMenu,
      categories: categories ?? this.categories,
      menuItems: menuItems ?? this.menuItems,
      addons: addons ?? this.addons,
      offers: offers ?? this.offers,
      isLoadingTables: isLoadingTables ?? this.isLoadingTables,
      tables: tables ?? this.tables,
      isLoadingCustomers: isLoadingCustomers ?? this.isLoadingCustomers,
      customers: customers ?? this.customers,
      isLoadingAuditLogs: isLoadingAuditLogs ?? this.isLoadingAuditLogs,
      auditLogs: auditLogs ?? this.auditLogs,
      storeSettings: storeSettings ?? this.storeSettings,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearSuccess ? null : (successMessage ?? this.successMessage),
    );
  }
}
