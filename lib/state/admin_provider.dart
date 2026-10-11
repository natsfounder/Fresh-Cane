import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/utils/date_time_utils.dart';
import '../models/expense_model.dart';
import '../repositories/admin_repository.dart';
import '../repositories/expense_repository.dart';
import '../services/report_export_service.dart';
import 'admin_state.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository();
});

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepository();
});

final adminProvider = NotifierProvider<AdminNotifier, AdminState>(() {
  return AdminNotifier();
});

class AdminNotifier extends Notifier<AdminState> {
  AdminRepository get _repository => ref.read(adminRepositoryProvider);
  ExpenseRepository get _expenseRepo => ref.read(expenseRepositoryProvider);

  @override
  AdminState build() {
    // Initial fetch for dashboard metrics
    Future.microtask(() => loadDashboard());
    return AdminState.initial();
  }

  void setNavIndex(int index) {
    state = state.copyWith(selectedNavIndex: index);
    if (index == 0) {
      loadDashboard();
    } else if (index == 1) {
      loadReportData();
    } else if (index == 2) {
      loadExpenseData();
    } else if (index == 3) {
      loadMenuData();
    } else if (index == 4) {
      loadTables();
    } else if (index == 6) {
      loadAuditLogs();
    } else if (index == 7) {
      loadStoreSettings();
    }
  }

  void setDateFilter(AdminDateFilter filter, {DateTime? customStart, DateTime? customEnd}) {
    state = state.copyWith(
      dateFilter: filter,
      customStartDate: customStart ?? state.customStartDate,
      customEndDate: customEnd ?? state.customEndDate,
    );
    // Reload active view data
    if (state.selectedNavIndex == 0) {
      loadDashboard();
    } else if (state.selectedNavIndex == 1) {
      loadReportData();
    } else if (state.selectedNavIndex == 2) {
      loadExpenseReport();
    }
  }

  // ---------------------------------------------------------------------------
  // DASHBOARD
  // ---------------------------------------------------------------------------

  Future<void> loadDashboard() async {
    state = state.copyWith(isLoadingDashboard: true, clearError: true);
    try {
      final metrics = await _repository.fetchDashboardMetrics(
        startDate: state.effectiveStartDate,
        endDate: state.effectiveEndDate,
      );
      state = state.copyWith(
        isLoadingDashboard: false,
        dashboardMetrics: metrics,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingDashboard: false,
        errorMessage: 'Failed to load dashboard metrics: $e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // REPORTS
  // ---------------------------------------------------------------------------

  void setReportType(String reportType) {
    if (state.selectedReportType != reportType) {
      state = state.copyWith(selectedReportType: reportType);
      loadReportData();
    }
  }

  Future<void> loadReportData() async {
    state = state.copyWith(isLoadingReport: true, clearError: true);
    try {
      final rows = await _repository.fetchReportData(
        reportType: state.selectedReportType,
        startDate: state.effectiveStartDate,
        endDate: state.effectiveEndDate,
      );
      state = state.copyWith(
        isLoadingReport: false,
        reportRows: rows,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingReport: false,
        errorMessage: 'Failed to load report data: $e',
      );
    }
  }

  Future<void> exportCurrentReport({required bool isPdf}) async {
    if (state.reportRows.isEmpty) {
      state = state.copyWith(errorMessage: 'No data to export for this report.');
      return;
    }

    state = state.copyWith(isExporting: true, clearError: true);
    try {
      final type = state.selectedReportType;
      final start = state.effectiveStartDate.toIso8601String().substring(0, 10);
      final end = state.effectiveEndDate.toIso8601String().substring(0, 10);
      final rangeStr = start == end ? start : '$start to $end';

      List<String> headers = [];
      List<List<dynamic>> rows = [];
      String reportTitle = 'Report';
      Map<String, dynamic> summary = {};

      switch (type) {
        case 'sales':
          reportTitle = 'Sales Report';
          headers = ['Date & Time', 'Bill No', 'Order Type', 'Table', 'Items', 'Total (₹)', 'Payment', 'Customer'];
          rows = state.reportRows.map((r) => [
            r['created_at'] != null ? AppDateTime.formatDateTime(r['created_at']) : (r['date'] ?? ''),
            r['bill_number'] ?? '',
            r['order_type'] ?? '',
            r['table_number'] ?? '-',
            r['item_count'] ?? 0,
            ReportExportService.formatCurrency(r['final_amount'] ?? r['total_amount']),
            (r['payment_method'] ?? 'cash').toString().toUpperCase(),
            r['customer_name'] ?? 'Walk-in',
          ]).toList();
          final totalSales = state.reportRows.fold<double>(0.0, (sum, r) => sum + (num.tryParse(r['final_amount']?.toString() ?? r['total_amount']?.toString() ?? '0') ?? 0).toDouble());
          final totalItems = state.reportRows.fold<int>(0, (sum, r) => sum + (int.tryParse(r['item_count']?.toString() ?? '0') ?? 0));
          summary = {
            'Total Bills': state.reportRows.length,
            'Total Items': totalItems,
            'Gross Total': ReportExportService.formatCurrency(totalSales),
          };
          rows.add([
            'GROSS TOTAL',
            '${state.reportRows.length} Bills',
            '-',
            '-',
            totalItems,
            ReportExportService.formatCurrency(totalSales),
            '-',
            '-',
          ]);
          break;

        case 'product':
          reportTitle = 'Product Sales Report';
          headers = ['Product', 'Category', 'Qty Sold', 'Gross Sales (₹)', 'Net Sales (₹)'];
          rows = state.reportRows.map((r) => [
            r['product_name'] ?? '',
            r['category_name'] ?? '',
            r['quantity_sold'] ?? 0,
            ReportExportService.formatCurrency(r['gross_sales'] ?? r['net_sales']),
            ReportExportService.formatCurrency(r['net_sales'] ?? r['gross_sales']),
          ]).toList();
          final totalQty = state.reportRows.fold<int>(0, (sum, r) => sum + (int.tryParse(r['quantity_sold']?.toString() ?? '0') ?? 0));
          final totalGross = state.reportRows.fold<double>(0.0, (sum, r) => sum + (num.tryParse(r['gross_sales']?.toString() ?? r['net_sales']?.toString() ?? '0') ?? 0).toDouble());
          final totalNet = state.reportRows.fold<double>(0.0, (sum, r) => sum + (num.tryParse(r['net_sales']?.toString() ?? r['gross_sales']?.toString() ?? '0') ?? 0).toDouble());
          summary = {
            'Total Products': state.reportRows.length,
            'Total Qty': totalQty,
            'Gross Total': ReportExportService.formatCurrency(totalNet),
          };
          rows.add([
            'GROSS TOTAL',
            '${state.reportRows.length} Products',
            totalQty,
            ReportExportService.formatCurrency(totalGross),
            ReportExportService.formatCurrency(totalNet),
          ]);
          break;

        case 'category':
          reportTitle = 'Category Sales Report';
          headers = ['Category', 'Quantity Sold', 'Gross Sales (₹)', 'Net Sales (₹)'];
          rows = state.reportRows.map((r) => [
            r['category_name'] ?? '',
            r['quantity_sold'] ?? 0,
            ReportExportService.formatCurrency(r['gross_sales'] ?? r['net_sales']),
            ReportExportService.formatCurrency(r['net_sales'] ?? r['gross_sales']),
          ]).toList();
          final catQty = state.reportRows.fold<int>(0, (sum, r) => sum + (int.tryParse(r['quantity_sold']?.toString() ?? '0') ?? 0));
          final catGross = state.reportRows.fold<double>(0.0, (sum, r) => sum + (num.tryParse(r['gross_sales']?.toString() ?? r['net_sales']?.toString() ?? '0') ?? 0).toDouble());
          final catNet = state.reportRows.fold<double>(0.0, (sum, r) => sum + (num.tryParse(r['net_sales']?.toString() ?? r['gross_sales']?.toString() ?? '0') ?? 0).toDouble());
          summary = {
            'Total Categories': state.reportRows.length,
            'Total Quantity': catQty,
            'Gross Total': ReportExportService.formatCurrency(catNet),
          };
          rows.add([
            'GROSS TOTAL',
            catQty,
            ReportExportService.formatCurrency(catGross),
            ReportExportService.formatCurrency(catNet),
          ]);
          break;

        case 'server':
          reportTitle = 'Server Operational Report';
          headers = ['Server Name', 'Role', 'Bills Handled', 'Total Sales (₹)'];
          rows = state.reportRows.map((r) => [
            r['server_name'] ?? '',
            r['server_role'] ?? '',
            r['bills_handled'] ?? 0,
            ReportExportService.formatCurrency(r['total_sales']),
          ]).toList();
          final srvBills = state.reportRows.fold<int>(0, (sum, r) => sum + (int.tryParse(r['bills_handled']?.toString() ?? '0') ?? 0));
          final srvSales = state.reportRows.fold<double>(0.0, (sum, r) => sum + (num.tryParse(r['total_sales']?.toString() ?? '0') ?? 0).toDouble());
          summary = {
            'Total Staff': state.reportRows.length,
            'Bills Handled': srvBills,
            'Gross Total': ReportExportService.formatCurrency(srvSales),
          };
          rows.add([
            'GROSS TOTAL',
            '${state.reportRows.length} Staff',
            srvBills,
            ReportExportService.formatCurrency(srvSales),
          ]);
          break;

        case 'payment':
          reportTitle = 'Payment Method Report';
          headers = ['Payment Method', 'Transactions', 'Total Collected (₹)'];
          rows = state.reportRows.map((r) => [
            (r['payment_method'] ?? '').toString().toUpperCase(),
            r['transaction_count'] ?? 0,
            ReportExportService.formatCurrency(r['total_amount']),
          ]).toList();
          final payTx = state.reportRows.fold<int>(0, (sum, r) => sum + (int.tryParse(r['transaction_count']?.toString() ?? '0') ?? 0));
          final payTotal = state.reportRows.fold<double>(0.0, (sum, r) => sum + (num.tryParse(r['total_amount']?.toString() ?? '0') ?? 0).toDouble());
          summary = {
            'Total Transactions': payTx,
            'Gross Total': ReportExportService.formatCurrency(payTotal),
          };
          rows.add([
            'GROSS TOTAL',
            payTx,
            ReportExportService.formatCurrency(payTotal),
          ]);
          break;

        case 'table':
          reportTitle = 'Table Utilization & Sales Report';
          headers = ['Table No', 'Sessions / Bills', 'Total Sales (₹)'];
          rows = state.reportRows.map((r) => [
            r['table_number'] ?? '',
            r['bills_count'] ?? 0,
            ReportExportService.formatCurrency(r['total_sales']),
          ]).toList();
          final tblBills = state.reportRows.fold<int>(0, (sum, r) => sum + (int.tryParse(r['bills_count']?.toString() ?? '0') ?? 0));
          final tblSales = state.reportRows.fold<double>(0.0, (sum, r) => sum + (num.tryParse(r['total_sales']?.toString() ?? '0') ?? 0).toDouble());
          summary = {
            'Total Tables': state.reportRows.length,
            'Total Sessions': tblBills,
            'Gross Total': ReportExportService.formatCurrency(tblSales),
          };
          rows.add([
            'GROSS TOTAL',
            tblBills,
            ReportExportService.formatCurrency(tblSales),
          ]);
          break;

        case 'order_type':
          reportTitle = 'Order Type Breakdown Report';
          headers = ['Order Type', 'Orders Count', 'Total Sales (₹)'];
          rows = state.reportRows.map((r) => [
            (r['order_type'] ?? '').toString().toUpperCase(),
            r['order_count'] ?? 0,
            ReportExportService.formatCurrency(r['total_sales']),
          ]).toList();
          final otOrders = state.reportRows.fold<int>(0, (sum, r) => sum + (int.tryParse(r['order_count']?.toString() ?? '0') ?? 0));
          final otSales = state.reportRows.fold<double>(0.0, (sum, r) => sum + (num.tryParse(r['total_sales']?.toString() ?? '0') ?? 0).toDouble());
          summary = {
            'Total Orders': otOrders,
            'Gross Total': ReportExportService.formatCurrency(otSales),
          };
          rows.add([
            'GROSS TOTAL',
            otOrders,
            ReportExportService.formatCurrency(otSales),
          ]);
          break;

        case 'offer':
          reportTitle = 'Offers & Discounts Report';
          headers = ['Offer / Reason', 'Discount Type', 'Orders Applied', 'Total Discount Given (₹)'];
          rows = state.reportRows.map((r) => [
            r['offer_name'] ?? '',
            r['discount_type'] ?? '',
            r['orders_count'] ?? 0,
            ReportExportService.formatCurrency(r['total_discount_amount']),
          ]).toList();
          final offOrders = state.reportRows.fold<int>(0, (sum, r) => sum + (int.tryParse(r['orders_count']?.toString() ?? '0') ?? 0));
          final offDisc = state.reportRows.fold<double>(0.0, (sum, r) => sum + (num.tryParse(r['total_discount_amount']?.toString() ?? '0') ?? 0).toDouble());
          summary = {
            'Offers Applied': offOrders,
            'Gross Total': ReportExportService.formatCurrency(offDisc),
          };
          rows.add([
            'GROSS TOTAL',
            '-',
            offOrders,
            ReportExportService.formatCurrency(offDisc),
          ]);
          break;

        case 'cancellation':
          reportTitle = 'Cancellation & Void Report';
          headers = ['Date & Time', 'Table', 'Status', 'Items Cancelled', 'Approx Loss (₹)'];
          rows = state.reportRows.map((r) => [
            r['cancelled_at'] ?? '',
            r['table_number'] ?? '-',
            (r['order_status'] ?? '').toString().toUpperCase(),
            r['items_count'] ?? 0,
            ReportExportService.formatCurrency(r['estimated_amount']),
          ]).toList();
          final canItems = state.reportRows.fold<int>(0, (sum, r) => sum + (int.tryParse(r['items_count']?.toString() ?? '0') ?? 0));
          final canLoss = state.reportRows.fold<double>(0.0, (sum, r) => sum + (num.tryParse(r['estimated_amount']?.toString() ?? '0') ?? 0).toDouble());
          summary = {
            'Cancelled Events': state.reportRows.length,
            'Items Cancelled': canItems,
            'Gross Total Loss': ReportExportService.formatCurrency(canLoss),
          };
          rows.add([
            'GROSS TOTAL',
            '-',
            '${state.reportRows.length} Cancelled',
            canItems,
            ReportExportService.formatCurrency(canLoss),
          ]);
          break;
      }

      final ExportResult result;
      if (isPdf) {
        result = await ReportExportService.exportToPdf(
          reportTitle: reportTitle,
          dateRangeStr: rangeStr,
          headers: headers,
          rows: rows,
          summaryData: summary,
        );
      } else {
        result = await ReportExportService.exportToExcel(
          reportTitle: reportTitle,
          dateRangeStr: rangeStr,
          headers: headers,
          rows: rows,
        );
      }

      state = state.copyWith(
        isExporting: false,
        successMessage: 'Downloaded to ${result.folderName}: ${result.fileName}',
      );
    } catch (e) {
      state = state.copyWith(
        isExporting: false,
        errorMessage: 'Failed to export report: $e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // MENU MANAGEMENT
  // ---------------------------------------------------------------------------

  Future<void> loadMenuData() async {
    state = state.copyWith(isLoadingMenu: true, clearError: true);
    try {
      final categories = await _repository.fetchCategories();
      final menuItems = await _repository.fetchMenuItems();
      final addons = await _repository.fetchAddons();
      final offers = await _repository.fetchOffers();

      state = state.copyWith(
        isLoadingMenu: false,
        categories: categories,
        menuItems: menuItems,
        addons: addons,
        offers: offers,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingMenu: false,
        errorMessage: 'Failed to load menu data: $e',
      );
    }
  }

  Future<void> toggleProductAvailability(String id, bool isAvailable) async {
    try {
      await _repository.toggleMenuItemAvailability(id, isAvailable);
      // Local state update
      final updated = state.menuItems.map((item) {
        if (item['id'] == id) {
          return {...item, 'is_available': isAvailable};
        }
        return item;
      }).toList();
      state = state.copyWith(menuItems: updated);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update availability: $e');
    }
  }

  Future<void> saveMenuItem({
    String? id,
    required String name,
    required String categoryId,
    required double basePrice,
    String? description,
    bool isAvailable = true,
    bool isActive = true,
    String? imageUrl,
  }) async {
    try {
      await _repository.saveMenuItem(
        id: id,
        name: name,
        categoryId: categoryId,
        basePrice: basePrice,
        description: description,
        isAvailable: isAvailable,
        isActive: isActive,
        imageUrl: imageUrl,
      );
      await loadMenuData();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to save product: $e');
      rethrow;
    }
  }

  Future<String> uploadMenuItemImage({
    required Uint8List bytes,
    String? fileName,
    String? mimeType,
  }) async {
    return await _repository.uploadMenuItemImage(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
  }

  Future<void> deleteMenuItemImage(String imageUrl) async {
    await _repository.deleteMenuItemImage(imageUrl);
  }

  Future<void> saveCategory({
    String? id,
    required String name,
    required String slug,
    int displayOrder = 0,
    bool isActive = true,
  }) async {
    try {
      await _repository.saveCategory(
        id: id,
        name: name,
        slug: slug,
        displayOrder: displayOrder,
        isActive: isActive,
      );
      await loadMenuData();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to save category: $e');
      rethrow;
    }
  }

  Future<void> toggleCategoryActive(String id, bool isActive) async {
    try {
      await _repository.toggleCategoryActive(id, isActive);
      await loadMenuData();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update category: $e');
    }
  }

  Future<void> saveAddon({
    String? id,
    required String name,
    required double price,
    String? menuItemId,
    bool isAvailable = true,
  }) async {
    try {
      await _repository.saveAddon(
        id: id,
        name: name,
        price: price,
        menuItemId: menuItemId,
        isAvailable: isAvailable,
      );
      await loadMenuData();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to save add-on: $e');
      rethrow;
    }
  }

  Future<void> toggleAddonAvailability(String id, bool isAvailable) async {
    try {
      await _repository.toggleAddonAvailability(id, isAvailable);
      await loadMenuData();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update add-on: $e');
    }
  }

  Future<void> deleteAddon(String id) async {
    try {
      await _repository.deleteAddon(id);
      await loadMenuData();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to delete add-on: $e');
      rethrow;
    }
  }

  Future<void> saveOffer({
    String? id,
    required String title,
    required String code,
    required String discountType,
    required double discountValue,
    List<String> applicableProductIds = const [],
    int buyQuantity = 1,
    int getQuantity = 1,
    double minOrderAmount = 0.0,
    double? maxDiscountAmount,
    DateTime? startDate,
    DateTime? endDate,
    bool isActive = true,
  }) async {
    try {
      await _repository.saveOffer(
        id: id,
        title: title,
        code: code,
        discountType: discountType,
        discountValue: discountValue,
        applicableProductIds: applicableProductIds,
        buyQuantity: buyQuantity,
        getQuantity: getQuantity,
        minOrderAmount: minOrderAmount,
        maxDiscountAmount: maxDiscountAmount,
        startDate: startDate,
        endDate: endDate,
        isActive: isActive,
      );
      await loadMenuData();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to save offer: $e');
      rethrow;
    }
  }

  Future<void> toggleOfferActive(String id, bool isActive) async {
    try {
      await _repository.toggleOfferActive(id, isActive);
      await loadMenuData();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update offer: $e');
    }
  }

  Future<void> deleteOffer(String id) async {
    try {
      await _repository.deleteOffer(id);
      await loadMenuData();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to delete offer: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // TABLES
  // ---------------------------------------------------------------------------

  Future<void> loadTables() async {
    state = state.copyWith(isLoadingTables: true, clearError: true);
    try {
      final tables = await _repository.fetchTables();
      state = state.copyWith(isLoadingTables: false, tables: tables);
    } catch (e) {
      state = state.copyWith(
        isLoadingTables: false,
        errorMessage: 'Failed to load tables: $e',
      );
    }
  }

  Future<void> toggleTableActive(String id, bool isActive) async {
    try {
      await _repository.toggleTableActive(id, isActive);
      await loadTables();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update table: $e');
    }
  }

  Future<void> saveTable({
    String? id,
    required String tableNumber,
    required int seatingCapacity,
    bool isActive = true,
  }) async {
    try {
      await _repository.saveTable(
        id: id,
        tableNumber: tableNumber,
        seatingCapacity: seatingCapacity,
        isActive: isActive,
      );
      await loadTables();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to save table: $e');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // CUSTOMERS
  // ---------------------------------------------------------------------------

  Future<void> loadCustomers() async {
    state = state.copyWith(isLoadingCustomers: true, clearError: true);
    try {
      final customers = await _repository.fetchCustomers();
      state = state.copyWith(isLoadingCustomers: false, customers: customers);
    } catch (e) {
      state = state.copyWith(
        isLoadingCustomers: false,
        errorMessage: 'Failed to load customers: $e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // AUDIT LOGS
  // ---------------------------------------------------------------------------

  Future<void> loadAuditLogs() async {
    state = state.copyWith(isLoadingAuditLogs: true, clearError: true);
    try {
      final logs = await _repository.fetchAuditLogs();
      state = state.copyWith(isLoadingAuditLogs: false, auditLogs: logs);
    } catch (e) {
      state = state.copyWith(
        isLoadingAuditLogs: false,
        errorMessage: 'Failed to load audit logs: $e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // SETTINGS
  // ---------------------------------------------------------------------------

  Future<void> loadStoreSettings() async {
    try {
      final settings = await _repository.fetchStoreSettings();
      state = state.copyWith(storeSettings: settings);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to load store settings: $e');
    }
  }

  Future<void> updateStoreSettings(Map<String, dynamic> data) async {
    try {
      final currentId = state.storeSettings?['id'] as String?;
      if (currentId != null) {
        await _repository.updateStoreSettings(currentId, data);
        await loadStoreSettings();
        state = state.copyWith(successMessage: 'Settings updated successfully.');
      }
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update settings: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // EXPENSES MANAGEMENT & REPORTS
  // ---------------------------------------------------------------------------

  Future<void> loadExpenseData() async {
    state = state.copyWith(isLoadingExpenses: true, clearError: true);
    await Future.wait([
      loadExpenseDefinitions(quiet: true),
      loadExpenseReport(quiet: true),
    ]);
    state = state.copyWith(isLoadingExpenses: false);
  }

  Future<void> loadExpenseDefinitions({bool quiet = false}) async {
    if (!quiet) state = state.copyWith(isLoadingExpenses: true, clearError: true);
    try {
      final defs = await _expenseRepo.fetchExpenseDefinitions();
      state = state.copyWith(
        isLoadingExpenses: quiet ? state.isLoadingExpenses : false,
        expenseDefinitions: defs,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingExpenses: false,
        errorMessage: 'Failed to load expense definitions: $e',
      );
    }
  }

  Future<void> loadExpenseReport({bool quiet = false}) async {
    if (!quiet) state = state.copyWith(isLoadingExpenses: true, clearError: true);
    try {
      final res = await _expenseRepo.fetchExpenseReport(
        startDate: state.effectiveStartDate,
        endDate: state.effectiveEndDate,
        definitionId: state.selectedExpenseDefinitionFilter,
        expenseType: state.selectedExpenseTypeFilter,
        paymentMethod: state.selectedExpensePaymentMethodFilter,
        filterStatus: state.selectedExpenseStatusFilter,
      );

      state = state.copyWith(
        isLoadingExpenses: quiet ? state.isLoadingExpenses : false,
        expenseTransactions: res['transactions'] as List<ExpenseTransaction>,
        expenseSummary: res['summary'] as Map<String, dynamic>?,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingExpenses: false,
        errorMessage: 'Failed to load expense report: $e',
      );
    }
  }

  void setExpenseFilters({
    String? definitionId,
    String? expenseType,
    String? paymentMethod,
    String? statusFilter,
    bool clearDefinition = false,
  }) {
    state = state.copyWith(
      selectedExpenseDefinitionFilter: clearDefinition ? null : definitionId,
      clearDefinitionFilter: clearDefinition,
      clearSubCategoryFilter: true,
      selectedExpenseTypeFilter: expenseType,
      selectedExpensePaymentMethodFilter: paymentMethod,
      selectedExpenseStatusFilter: statusFilter ?? state.selectedExpenseStatusFilter,
    );
    loadExpenseReport();
  }

  void setExpenseSubCategoryFilter(String? subCategory) {
    if (subCategory == null || subCategory.isEmpty) {
      state = state.copyWith(clearSubCategoryFilter: true);
    } else {
      state = state.copyWith(selectedExpenseSubCategoryFilter: subCategory);
    }
  }

  Future<void> createExpenseDefinition({
    required String name,
    String? description,
    required String expenseType,
    required String frequency,
    required DateTime startDate,
    bool isActive = true,
    List<String>? subExpenses,
  }) async {
    try {
      await _expenseRepo.createExpenseDefinition(
        name: name,
        description: description,
        expenseType: expenseType,
        frequency: frequency,
        startDate: startDate,
        isActive: isActive,
        subExpenses: subExpenses,
      );
      state = state.copyWith(successMessage: 'Expense definition created successfully.');
      await loadExpenseDefinitions();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to create definition: $e');
    }
  }

  Future<void> updateExpenseDefinition({
    required String id,
    required String name,
    String? description,
    required String expenseType,
    required String frequency,
    required DateTime startDate,
    required bool isActive,
    List<String>? subExpenses,
  }) async {
    try {
      await _expenseRepo.updateExpenseDefinition(
        id: id,
        name: name,
        description: description,
        expenseType: expenseType,
        frequency: frequency,
        startDate: startDate,
        isActive: isActive,
        subExpenses: subExpenses,
      );
      state = state.copyWith(successMessage: 'Expense definition updated successfully.');
      await loadExpenseDefinitions();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update definition: $e');
    }
  }

  Future<void> toggleExpenseDefinitionStatus(String id, bool isActive) async {
    try {
      await _expenseRepo.toggleExpenseDefinitionActive(id, isActive);
      state = state.copyWith(
        successMessage: isActive ? 'Definition activated.' : 'Definition deactivated.',
      );
      await loadExpenseDefinitions();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to change definition status: $e');
    }
  }

  Future<void> exportExpenseReportToExcel() async {
    final subCat = state.selectedExpenseSubCategoryFilter;
    var transactions = state.expenseTransactions;
    if (subCat != null && subCat.isNotEmpty) {
      transactions = transactions.where((t) =>
        t.subExpenses.any((s) => s.name.trim().toLowerCase() == subCat.trim().toLowerCase())
      ).toList();
    }

    if (transactions.isEmpty) {
      state = state.copyWith(errorMessage: 'No expense records to export.');
      return;
    }

    state = state.copyWith(isExporting: true, clearError: true);
    try {
      final startStr = DateFormat('yyyy-MM-dd').format(state.effectiveStartDate);
      final endStr = DateFormat('yyyy-MM-dd').format(state.effectiveEndDate);
      final rangeStr = startStr == endStr ? startStr : '$startStr to $endStr';

      final headers = [
        'Expense Name',
        'Subcategory',
        'Type',
        'Frequency',
        'Period',
        'Recorded Date & Time',
        'Amount',
        'Payment Method',
        'Sub-Expenses Breakdown',
        'Notes',
        'Recorded By',
        'Status',
      ];

      final rows = transactions.map((t) {
        double itemAmount = t.amount;
        String subCatText = '-';
        if (subCat != null && subCat.isNotEmpty) {
          final matchingSub = t.subExpenses.where((s) => s.name.trim().toLowerCase() == subCat.trim().toLowerCase()).firstOrNull;
          if (matchingSub != null) {
            itemAmount = matchingSub.amount;
            subCatText = matchingSub.name;
          }
        }
        return [
          t.expenseName,
          subCatText,
          t.expenseType.toUpperCase(),
          t.frequency,
          t.applicablePeriod ?? '-',
          DateFormat('yyyy-MM-dd hh:mm a').format(t.createdAt),
          itemAmount,
          t.paymentMethodLabel,
          t.hasSubExpenses ? t.subExpensesSummary : '-',
          t.displayNotes.isNotEmpty ? t.displayNotes : '-',
          t.recordedByName,
          t.status.toUpperCase(),
        ];
      }).toList();

      double grossExpenseTotal = 0.0;
      for (final t in transactions) {
        if (!t.isDeleted && t.status != 'deleted') {
          if (subCat != null && subCat.isNotEmpty) {
            final matchingSub = t.subExpenses.where((s) => s.name.trim().toLowerCase() == subCat.trim().toLowerCase()).firstOrNull;
            grossExpenseTotal += (matchingSub?.amount ?? 0.0);
          } else {
            grossExpenseTotal += t.amount;
          }
        }
      }

      rows.add([
        'GROSS TOTAL',
        subCat ?? 'ALL',
        '-',
        '-',
        '-',
        '${transactions.length} Records',
        ReportExportService.formatCurrency(grossExpenseTotal),
        '-',
        '-',
        '-',
        '-',
        'ACTIVE TOTAL',
      ]);

      final reportTitle = (subCat != null && subCat.isNotEmpty)
          ? 'Expense Report ($subCat)'
          : 'Expense Report';

      final result = await ReportExportService.exportToExcel(
        reportTitle: reportTitle,
        dateRangeStr: rangeStr,
        headers: headers,
        rows: rows,
      );
      state = state.copyWith(
        isExporting: false,
        successMessage: 'Downloaded to ${result.folderName}: ${result.fileName}',
      );
    } catch (e) {
      state = state.copyWith(isExporting: false, errorMessage: 'Failed to download Excel: $e');
    }
  }

  Future<void> exportExpenseReportToPdf() async {
    final subCat = state.selectedExpenseSubCategoryFilter;
    var transactions = state.expenseTransactions;
    if (subCat != null && subCat.isNotEmpty) {
      transactions = transactions.where((t) =>
        t.subExpenses.any((s) => s.name.trim().toLowerCase() == subCat.trim().toLowerCase())
      ).toList();
    }

    if (transactions.isEmpty) {
      state = state.copyWith(errorMessage: 'No expense records to export.');
      return;
    }

    state = state.copyWith(isExporting: true, clearError: true);
    try {
      final startStr = DateFormat('yyyy-MM-dd').format(state.effectiveStartDate);
      final endStr = DateFormat('yyyy-MM-dd').format(state.effectiveEndDate);
      final rangeStr = startStr == endStr ? startStr : '$startStr to $endStr';

      final headers = [
        'Expense',
        'Subcategory',
        'Date & Time',
        'Amount',
        'Mode',
        'Notes',
        'By',
        'Status',
      ];

      double subActiveTotal = 0.0;
      double subDeletedTotal = 0.0;
      int subActiveCount = 0;
      int subDeletedCount = 0;

      final rows = transactions.map((t) {
        double itemAmount = t.amount;
        String subCatText = '-';
        if (subCat != null && subCat.isNotEmpty) {
          final matchingSub = t.subExpenses.where((s) => s.name.trim().toLowerCase() == subCat.trim().toLowerCase()).firstOrNull;
          if (matchingSub != null) {
            itemAmount = matchingSub.amount;
            subCatText = matchingSub.name;
          }
        }
        final isDel = t.isDeleted || t.status == 'deleted';
        if (isDel) {
          subDeletedTotal += itemAmount;
          subDeletedCount++;
        } else {
          subActiveTotal += itemAmount;
          subActiveCount++;
        }

        String detailNotes = t.displayNotes;
        if (t.hasSubExpenses) {
          detailNotes = detailNotes.isNotEmpty
              ? '[${t.subExpensesSummary}] $detailNotes'
              : t.subExpensesSummary;
        }
        return [
          t.expenseName,
          subCatText,
          DateFormat('dd/MM/yy hh:mm a').format(t.createdAt),
          'INR ${itemAmount.toStringAsFixed(2)}',
          t.paymentMethodLabel,
          detailNotes.isNotEmpty ? detailNotes : '-',
          t.recordedByName,
          t.status.toUpperCase(),
        ];
      }).toList();

      rows.add([
        'GROSS TOTAL',
        subCat ?? 'ALL',
        '${transactions.length} Records',
        'INR ${subActiveTotal.toStringAsFixed(2)}',
        '-',
        '-',
        '-',
        'ACTIVE TOTAL',
      ]);

      final summary = state.expenseSummary;
      final summaryMap = (subCat != null && subCat.isNotEmpty)
          ? {
              'Subcategory Total': 'INR ${subActiveTotal.toStringAsFixed(2)}',
              'Active Count': '$subActiveCount',
              'Deleted Total': 'INR ${subDeletedTotal.toStringAsFixed(2)}',
              'Deleted Count': '$subDeletedCount',
            }
          : (summary != null
              ? {
                  'Active Expenses': 'INR ${((summary['total_active_amount'] ?? summary['total_expenses'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                  'Active Count': '${summary['total_active_count'] ?? summary['transactions_count'] ?? transactions.where((t) => !t.isDeleted).length}',
                  'Deleted Expenses': 'INR ${((summary['total_deleted_amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                }
              : null);

      final reportTitle = (subCat != null && subCat.isNotEmpty)
          ? 'Expense Report ($subCat)'
          : 'Expense Report';

      final result = await ReportExportService.exportToPdf(
        reportTitle: reportTitle,
        dateRangeStr: rangeStr,
        headers: headers,
        rows: rows,
        summaryData: summaryMap,
      );
      state = state.copyWith(
        isExporting: false,
        successMessage: 'Downloaded to ${result.folderName}: ${result.fileName}',
      );
    } catch (e) {
      state = state.copyWith(isExporting: false, errorMessage: 'Failed to download PDF: $e');
    }
  }
}
