import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../../services/report_export_service.dart';
import '../../../state/admin_provider.dart';
import '../../../state/admin_state.dart';

class AdminDashboardView extends ConsumerWidget {
  const AdminDashboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminProvider);
    final notifier = ref.read(adminProvider.notifier);

    if (state.isLoadingDashboard && state.dashboardMetrics == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primaryGreen),
            SizedBox(height: 12),
            Text('Loading live dashboard metrics...', style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      );
    }

    final metrics = state.dashboardMetrics ?? {};
    final totalSales = (metrics['total_sales'] as num?)?.toDouble() ?? 0.0;
    final totalBills = (metrics['total_bills'] as num?)?.toInt() ?? 0;
    final activeOrders = (metrics['active_orders'] as num?)?.toInt() ?? 0;
    final billingOrders = (metrics['billing_orders'] as num?)?.toInt() ?? 0;
    final cancelledOrders = (metrics['cancelled_orders'] as num?)?.toInt() ?? 0;
    final totalTables = (metrics['total_tables'] as num?)?.toInt() ?? 0;
    final occupiedTables = (metrics['occupied_tables'] as num?)?.toInt() ?? 0;
    final totalProducts = (metrics['total_products'] as num?)?.toInt() ?? 0;
    final activeProducts = (metrics['active_products'] as num?)?.toInt() ?? 0;
    final totalCategories = (metrics['total_categories'] as num?)?.toInt() ?? 0;
    final activeServers = (metrics['active_servers'] as num?)?.toInt() ?? 0;

    final salesTrend = (metrics['sales_trend'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final paymentBreakdown = (metrics['payment_breakdown'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final recentBills = (metrics['recent_bills'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return RefreshIndicator(
      color: AppColors.primaryGreen,
      onRefresh: () => notifier.loadDashboard(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date Filter Ribbon
            _buildDateFilterBar(context, state, notifier),
            const SizedBox(height: 16),

            // Top Sales & Operational KPI Cards
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 700;
                final crossAxisCount = isWide ? 4 : 2;
                return GridView.count(
                  crossAxisCount: crossAxisCount,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: isWide ? 1.6 : 1.15,
                  children: [
                    _buildKpiCard(
                      title: 'Net Revenue',
                      value: ReportExportService.formatCurrency(totalSales),
                      subtitle: '$totalBills paid bills',
                      icon: Icons.payments_outlined,
                      color: AppColors.primaryGreen,
                      bgColor: AppColors.primaryLight,
                    ),
                    _buildKpiCard(
                      title: 'Live Orders',
                      value: '$activeOrders',
                      subtitle: '$billingOrders ready for bill',
                      icon: Icons.receipt_long_outlined,
                      color: const Color(0xFF1976D2),
                      bgColor: const Color(0xFFE3F2FD),
                    ),
                    _buildKpiCard(
                      title: 'Tables Occupied',
                      value: '$occupiedTables / $totalTables',
                      subtitle: '${totalTables - occupiedTables} available',
                      icon: Icons.table_bar_outlined,
                      color: const Color(0xFFE65100),
                      bgColor: const Color(0xFFFFF3E0),
                    ),
                    _buildKpiCard(
                      title: 'Active Products',
                      value: '$activeProducts / $totalProducts',
                      subtitle: '$totalCategories categories',
                      icon: Icons.inventory_2_outlined,
                      color: const Color(0xFF6A1B9A),
                      bgColor: const Color(0xFFF3E5F5),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),

            // Secondary KPI Strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Flexible(
                    child: _buildSubStatItem(
                      label: 'Total Bills',
                      val: '$totalBills bills',
                      icon: Icons.receipt_long_outlined,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                  Container(height: 24, width: 1, color: Colors.grey.shade300),
                  Flexible(
                    child: _buildSubStatItem(
                      label: 'Cancelled',
                      val: '$cancelledOrders orders',
                      icon: Icons.cancel_outlined,
                      color: AppColors.error,
                    ),
                  ),
                  Container(height: 24, width: 1, color: Colors.grey.shade300),
                  Flexible(
                    child: _buildSubStatItem(
                      label: 'Staff Active',
                      val: '$activeServers staff',
                      icon: Icons.badge_outlined,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Sales Trend & Payment Method Distribution
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 850;
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: _buildSalesTrendCard(salesTrend),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 4,
                        child: _buildPaymentBreakdownCard(paymentBreakdown),
                      ),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      _buildSalesTrendCard(salesTrend),
                      const SizedBox(height: 14),
                      _buildPaymentBreakdownCard(paymentBreakdown),
                    ],
                  );
                }
              },
            ),
            const SizedBox(height: 20),

            // Recent Paid Bills List
            _buildRecentBillsCard(recentBills),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildDateFilterBar(
    BuildContext context,
    AdminState state,
    AdminNotifier notifier,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ...AdminDateFilter.values.map((filter) {
            final isSelected = state.dateFilter == filter;
            return Padding(
              padding: const EdgeInsets.only(right: 6.0),
              child: ChoiceChip(
                label: Text(filter.label),
                selected: isSelected,
                selectedColor: AppColors.primaryGreen,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 12,
                ),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected ? AppColors.primaryGreen : Colors.grey.shade300,
                  ),
                ),
                onSelected: (selected) {
                  if (selected) {
                    if (filter == AdminDateFilter.custom) {
                      _pickCustomDateRange(context, state, notifier);
                    } else {
                      notifier.setDateFilter(filter);
                    }
                  }
                },
              ),
            );
          }),
          if (state.dateFilter == AdminDateFilter.custom)
            Padding(
              padding: const EdgeInsets.only(left: 6.0),
              child: Text(
                '${state.customStartDate.toIso8601String().substring(0, 10)} - ${state.customEndDate.toIso8601String().substring(0, 10)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryGreen,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickCustomDateRange(
    BuildContext context,
    AdminState state,
    AdminNotifier notifier,
  ) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: state.customStartDate,
        end: state.customEndDate,
      ),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryGreen,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      notifier.setDateFilter(
        AdminDateFilter.custom,
        customStart: picked.start,
        customEnd: picked.end,
      );
    }
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubStatItem({
    required String label,
    required String val,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                val,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSalesTrendCard(List<Map<String, dynamic>> trend) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Sales & Billing Trend',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${trend.length} active dates',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (trend.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              alignment: Alignment.center,
              child: Text(
                'No transaction data recorded for this date range.',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: trend.length,
              separatorBuilder: (_, __) => Divider(color: Colors.grey.shade100, height: 12),
              itemBuilder: (context, index) {
                final item = trend[index];
                final dateStr = item['date'] ?? '';
                final sales = (item['total_sales'] as num?)?.toDouble() ?? 0.0;
                final billsCount = (item['bills_count'] as num?)?.toInt() ?? 0;

                return Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        dateStr.toString(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$billsCount bills',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const Spacer(),
                    Text(
                      ReportExportService.formatCurrency(sales),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPaymentBreakdownCard(List<Map<String, dynamic>> payments) {
    final totalAmount = payments.fold<double>(
      0.0,
      (sum, p) => sum + (((p['total_amount'] ?? p['amount']) as num?)?.toDouble() ?? 0.0),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment Methods',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (payments.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              alignment: Alignment.center,
              child: Text(
                'No payment records found.',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            )
          else
            ...payments.map((p) {
              final method = (p['payment_method'] ?? p['method'] ?? 'cash').toString().toUpperCase();
              final amount = ((p['total_amount'] ?? p['amount']) as num?)?.toDouble() ?? 0.0;
              final count = ((p['transaction_count'] ?? p['count']) as num?)?.toInt() ?? 0;
              final pct = totalAmount > 0 ? (amount / totalAmount) : 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              method.contains('UPI') ? Icons.qr_code_2 : Icons.money,
                              size: 15,
                              color: AppColors.primaryGreen,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              method,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '($count)',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                        Text(
                          ReportExportService.formatCurrency(amount),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        backgroundColor: Colors.grey.shade100,
                        color: AppColors.primaryGreen,
                        minHeight: 5,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRecentBillsCard(List<Map<String, dynamic>> bills) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Paid Bills',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${bills.length} latest',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (bills.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Center(
                child: Text(
                  'No recent bills recorded.',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: bills.length,
              separatorBuilder: (_, __) => Divider(color: Colors.grey.shade100, height: 10),
              itemBuilder: (context, index) {
                final bill = bills[index];
                final billNo = bill['bill_number'] ?? '';
                final customer = bill['customer_name'] ?? 'Walk-In';
                final amount = (bill['final_amount'] as num?)?.toDouble() ?? 0.0;
                final timeStr = AppDateTime.formatTime(bill['created_at']);

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primaryLight,
                    child: const Icon(Icons.receipt, color: AppColors.primaryGreen, size: 16),
                  ),
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        billNo.toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      if (bill['is_edited'] == true || (bill['notes']?.toString().contains('[EDITED]') ?? false)) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFF59E0B)),
                          ),
                          child: const Text(
                            'EDITED',
                            style: TextStyle(
                              color: Color(0xFFB45309),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '$customer • ${(bill['payment_method'] ?? 'cash').toString().toUpperCase()} • $timeStr',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  trailing: Text(
                    ReportExportService.formatCurrency(amount),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
