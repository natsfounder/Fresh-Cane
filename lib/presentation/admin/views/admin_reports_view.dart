import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../../models/settlement_model.dart';
import '../../../services/report_export_service.dart';
import '../../../state/admin_provider.dart';
import '../../../state/admin_state.dart';
import '../../../state/settlement_provider.dart';

class AdminReportsView extends ConsumerStatefulWidget {
  const AdminReportsView({super.key});

  @override
  ConsumerState<AdminReportsView> createState() => _AdminReportsViewState();
}

class _AdminReportsViewState extends ConsumerState<AdminReportsView> {
  // 0: Settlement, 1: Sales, 2: Expenses
  int _primarySection = 0;

  final _searchController = TextEditingController();
  String _filterQuery = '';

  DateTime _customFromDate = DateTime.now();
  DateTime _customToDate = DateTime.now();

  final List<Map<String, String>> _reportTypes = [
    {'id': 'sales', 'name': 'Sales Report'},
    {'id': 'product', 'name': 'Product-wise'},
    {'id': 'category', 'name': 'Category-wise'},
    {'id': 'server', 'name': 'Server-wise'},
    {'id': 'payment', 'name': 'Payment-wise'},
    {'id': 'table', 'name': 'Table-wise'},
    {'id': 'order_type', 'name': 'Order Type'},
    {'id': 'cancellation', 'name': 'Cancellations'},
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _customFromDate = DateTime(now.year, now.month, 1);
    _customToDate = DateTime(now.year, now.month, now.day);
    Future.microtask(() {
      ref.read(adminProvider.notifier).loadReportData();
      ref.read(settlementProvider.notifier).loadSettlementData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminProvider);
    final notifier = ref.read(adminProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Primary Section Navigation: Settlement | Sales | Expenses
          _buildPrimarySectionNavigation(),
          const SizedBox(height: 12),

          // 2. Active Section Body
          Expanded(
            child: _primarySection == 0
                ? _buildSettlementSection(context)
                : _primarySection == 1
                    ? _buildSalesSection(context, state, notifier)
                    : _buildExpensesSection(context, state, notifier),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PRIMARY SECTION TABS: SETTLEMENT | SALES | EXPENSES
  // ===========================================================================

  Widget _buildPrimarySectionNavigation() {
    final tabs = [
      {'title': 'Settlement', 'icon': Icons.account_balance_wallet_rounded, 'idx': 0},
      {'title': 'Sales Reports', 'icon': Icons.trending_up_rounded, 'idx': 1},
      {'title': 'Expense Reports', 'icon': Icons.receipt_long_rounded, 'idx': 2},
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: tabs.map((t) {
          final isSel = _primarySection == t['idx'];
          return Expanded(
            child: InkWell(
              onTap: () {
                setState(() => _primarySection = t['idx'] as int);
                if (t['idx'] == 0) {
                  ref.read(settlementProvider.notifier).loadSettlementData();
                } else if (t['idx'] == 1) {
                  ref.read(adminProvider.notifier).loadReportData();
                } else if (t['idx'] == 2) {
                  ref.read(adminProvider.notifier).loadExpenseData();
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                decoration: BoxDecoration(
                  color: isSel ? const Color(0xFF266540) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isSel
                      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)]
                      : null,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      t['icon'] as IconData,
                      size: 16,
                      color: isSel ? Colors.white : Colors.grey.shade700,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        t['title'] as String,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                          color: isSel ? Colors.white : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ===========================================================================
  // SECTION 1: SETTLEMENT REPORT (DAILY & MONTHLY PAYMENT-POSITION)
  // ===========================================================================

  Widget _buildSettlementSection(BuildContext context) {
    final sState = ref.watch(settlementProvider);
    final sNotifier = ref.read(settlementProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sub-Controls: Daily vs Monthly toggle + Date navigator + Export
        _buildSettlementControlBar(context, sState, sNotifier),
        const SizedBox(height: 12),

        // Main Settlement Body
        Expanded(
          child: sState.isLoading
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: AppColors.primaryGreen),
                      SizedBox(height: 12),
                      Text('Calculating financial settlement...', style: TextStyle(fontSize: 13, color: Colors.grey)),
                    ],
                  ),
                )
              : sState.viewMode == 'daily'
                  ? _buildDailySettlementView(sState)
                  : _buildMonthlySettlementView(sState),
        ),
      ],
    );
  }

  Widget _buildSettlementControlBar(
    BuildContext context,
    SettlementState sState,
    SettlementNotifier sNotifier,
  ) {
    final isDaily = sState.viewMode == 'daily';
    final currentLabel = isDaily
        ? DateFormat('EEE, dd MMM yyyy').format(sState.selectedDate)
        : DateFormat('MMMM yyyy').format(sState.selectedMonth);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          // Daily vs Monthly Toggle
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F8F4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildModePill('Daily', isDaily, () => sNotifier.setViewMode('daily')),
                _buildModePill('Monthly', !isDaily, () => sNotifier.setViewMode('monthly')),
              ],
            ),
          ),

          // Date / Month Navigator
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 22),
                tooltip: isDaily ? 'Previous Day' : 'Previous Month',
                onPressed: () {
                  if (isDaily) {
                    sNotifier.setDate(sState.selectedDate.subtract(const Duration(days: 1)));
                  } else {
                    sNotifier.setMonth(DateTime(sState.selectedMonth.year, sState.selectedMonth.month - 1, 1));
                  }
                },
              ),
              InkWell(
                onTap: () async {
                  if (isDaily) {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: sState.selectedDate,
                      firstDate: DateTime(2025),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) sNotifier.setDate(picked);
                  } else {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: sState.selectedMonth,
                      firstDate: DateTime(2025),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDatePickerMode: DatePickerMode.year,
                    );
                    if (picked != null) {
                      sNotifier.setMonth(DateTime(picked.year, picked.month, 1));
                    }
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFF2D6A4F)),
                      const SizedBox(width: 6),
                      Text(
                        currentLabel,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1B4332)),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, size: 22),
                tooltip: isDaily ? 'Next Day' : 'Next Month',
                onPressed: () {
                  if (isDaily) {
                    sNotifier.setDate(sState.selectedDate.add(const Duration(days: 1)));
                  } else {
                    sNotifier.setMonth(DateTime(sState.selectedMonth.year, sState.selectedMonth.month + 1, 1));
                  }
                },
              ),
            ],
          ),

          // Action Buttons: Refresh + Export
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20, color: Color(0xFF2D6A4F)),
                tooltip: 'Recalculate Settlement',
                onPressed: () => sNotifier.loadSettlementData(),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: 'Export Settlement',
                icon: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF266540),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.download_rounded, size: 14, color: Colors.white),
                      SizedBox(width: 4),
                      Text('Export', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                onSelected: (val) => _exportSettlement(val == 'pdf', sState),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'excel', child: Text('Export Excel (.xlsx)')),
                  PopupMenuItem(value: 'pdf', child: Text('Export PDF (.pdf)')),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModePill(String title, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF266540) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  // --- DAILY SETTLEMENT VIEW ---
  Widget _buildDailySettlementView(SettlementState sState) {
    final summary = sState.dailySummary ?? SettlementDailySummary(date: sState.selectedDate);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Formula & Position Headline Cards (Cash & UPI independent)
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              return isWide
                  ? Row(
                      children: [
                        Expanded(child: _buildPositionCard('CASH POSITION', summary.openingCash, summary.salesCash, summary.expensesCash, summary.closingCash, const Color(0xFF2E7D32))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildPositionCard('UPI POSITION', summary.openingUpi, summary.salesUpi, summary.expensesUpi, summary.closingUpi, const Color(0xFF1565C0))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildPositionCard('TOTAL POSITION', summary.openingTotal, summary.salesTotal, summary.expensesTotal, summary.closingTotal, const Color(0xFF1B4332))),
                      ],
                    )
                  : Column(
                      children: [
                        _buildPositionCard('CASH POSITION', summary.openingCash, summary.salesCash, summary.expensesCash, summary.closingCash, const Color(0xFF2E7D32)),
                        const SizedBox(height: 10),
                        _buildPositionCard('UPI POSITION', summary.openingUpi, summary.salesUpi, summary.expensesUpi, summary.closingUpi, const Color(0xFF1565C0)),
                        const SizedBox(height: 10),
                        _buildPositionCard('TOTAL POSITION', summary.openingTotal, summary.salesTotal, summary.expensesTotal, summary.closingTotal, const Color(0xFF1B4332)),
                      ],
                    );
            },
          ),
          const SizedBox(height: 16),

          // 2. Timeline of Today's Transactions
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.history_rounded, size: 18, color: Color(0xFF2D6A4F)),
                      const SizedBox(width: 8),
                      Text(
                        'Today\'s Transaction Timeline (${sState.dailyTransactions.length} records)',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1B4332)),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (sState.dailyTransactions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(28.0),
                    child: Center(
                      child: Text('No sales or expenses recorded on this date.', style: TextStyle(color: Colors.grey)),
                    ),
                  )
                else
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F8F4)),
                        columns: const [
                          DataColumn(label: Text('Time', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Type', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Description', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Method', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Cash (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('UPI (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Total (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: [
                          ...sState.dailyTransactions.map((t) {
                            final timeStr = DateFormat('hh:mm a').format(t.timestamp);
                            final isSale = t.isSale;
                            final cashVal = t.cashAmount;
                            final upiVal = t.upiAmount;

                            return DataRow(
                              cells: [
                                DataCell(Text(timeStr, style: const TextStyle(fontSize: 12))),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isSale ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isSale ? '+ SALE' : '- EXPENSE',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isSale ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(Text(t.description, style: const TextStyle(fontWeight: FontWeight.w500))),
                                DataCell(Text(t.paymentMethod.toUpperCase(), style: const TextStyle(fontSize: 11))),
                                DataCell(Text(cashVal > 0 ? '${isSale ? '+' : '-'}₹${cashVal.toStringAsFixed(2)}' : '-')),
                                DataCell(Text(upiVal > 0 ? '${isSale ? '+' : '-'}₹${upiVal.toStringAsFixed(2)}' : '-')),
                                DataCell(Text(
                                  '${isSale ? '+' : '-'}₹${t.amount.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isSale ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                                  ),
                                )),
                              ],
                            );
                          }),
                          // Gross Total Bottom Row
                          DataRow(
                            color: WidgetStateProperty.all(const Color(0xFFE8F5E9)),
                            cells: [
                              const DataCell(Text('GROSS TOTAL', style: TextStyle(fontWeight: FontWeight.bold))),
                              const DataCell(Text('')),
                              const DataCell(Text('Today\'s Net Movement', style: TextStyle(fontWeight: FontWeight.bold))),
                              const DataCell(Text('')),
                              DataCell(Text('₹${summary.netCash.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))),
                              DataCell(Text('₹${summary.netUpi.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))),
                              DataCell(Text('₹${summary.netTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B4332)))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPositionCard(
    String title,
    double opening,
    double sales,
    double expenses,
    double closing,
    Color accentColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accentColor, letterSpacing: 0.5),
              ),
              Icon(Icons.account_balance_wallet_outlined, size: 16, color: accentColor),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '₹${closing.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: accentColor),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _buildFormulaRow('Opening Balance', '₹${opening.toStringAsFixed(2)}', Colors.grey.shade700),
          _buildFormulaRow('+ Sales', '+₹${sales.toStringAsFixed(2)}', const Color(0xFF2E7D32)),
          _buildFormulaRow('− Expenses', '−₹${expenses.toStringAsFixed(2)}', const Color(0xFFC62828)),
          const SizedBox(height: 4),
          _buildFormulaRow('= Closing Balance', '₹${closing.toStringAsFixed(2)}', accentColor, isBold: true),
        ],
      ),
    );
  }

  Widget _buildFormulaRow(String label, String value, Color color, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: 12, color: color, fontWeight: isBold ? FontWeight.bold : FontWeight.w600)),
        ],
      ),
    );
  }

  // --- MONTHLY SETTLEMENT VIEW ---
  Widget _buildMonthlySettlementView(SettlementState sState) {
    final days = sState.monthlyDays;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F8F4)),
              columns: const [
                DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Cash Sales (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Cash Exp (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Cash Net (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('UPI Sales (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('UPI Exp (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('UPI Net (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Total Net (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: [
                ...days.map((d) {
                  final dateStr = DateFormat('dd MMM yyyy (EEE)').format(d.date);
                  final hasActivity = d.salesTotal > 0 || d.expensesTotal > 0;

                  return DataRow(
                    cells: [
                      DataCell(Text(dateStr, style: TextStyle(fontWeight: hasActivity ? FontWeight.bold : FontWeight.normal))),
                      DataCell(Text(d.salesCash > 0 ? '₹${d.salesCash.toStringAsFixed(2)}' : '-')),
                      DataCell(Text(d.expensesCash > 0 ? '₹${d.expensesCash.toStringAsFixed(2)}' : '-')),
                      DataCell(Text('₹${d.netCash.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: d.netCash >= 0 ? const Color(0xFF2E7D32) : const Color(0xFFC62828)))),
                      DataCell(Text(d.salesUpi > 0 ? '₹${d.salesUpi.toStringAsFixed(2)}' : '-')),
                      DataCell(Text(d.expensesUpi > 0 ? '₹${d.expensesUpi.toStringAsFixed(2)}' : '-')),
                      DataCell(Text('₹${d.netUpi.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: d.netUpi >= 0 ? const Color(0xFF1565C0) : const Color(0xFFC62828)))),
                      DataCell(Text('₹${d.netTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B4332)))),
                    ],
                  );
                }),
                // Bottom Gross Totals Row
                DataRow(
                  color: WidgetStateProperty.all(const Color(0xFFE8F5E9)),
                  cells: [
                    const DataCell(Text('GROSS TOTALS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    DataCell(Text('₹${sState.grossMonthlyCashSales.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text('₹${sState.grossMonthlyCashExpenses.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text('₹${sState.grossMonthlyCashNet.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2E7D32)))),
                    DataCell(Text('₹${sState.grossMonthlyUpiSales.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text('₹${sState.grossMonthlyUpiExpenses.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text('₹${sState.grossMonthlyUpiNet.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1565C0)))),
                    DataCell(Text('₹${sState.grossMonthlyTotalNet.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1B4332)))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _exportSettlement(bool isPdf, SettlementState sState) async {
    try {
      if (sState.viewMode == 'daily') {
        final summary = sState.dailySummary ?? SettlementDailySummary(date: sState.selectedDate);
        final dateStr = DateFormat('dd MMM yyyy').format(sState.selectedDate);

        final headers = ['Time', 'Type', 'Description', 'Method', 'Cash (₹)', 'UPI (₹)', 'Total (₹)'];
        final rows = <List<dynamic>>[];

        // Opening balance row
        rows.add([
          '00:00',
          'OPENING BALANCE',
          'Natural Opening Rollover',
          'ALL',
          summary.openingCash,
          summary.openingUpi,
          summary.openingTotal,
        ]);

        for (final t in sState.dailyTransactions) {
          rows.add([
            DateFormat('hh:mm a').format(t.timestamp),
            t.isSale ? 'SALE' : 'EXPENSE',
            t.description,
            t.paymentMethod.toUpperCase(),
            t.cashAmount,
            t.upiAmount,
            t.isSale ? t.amount : -t.amount,
          ]);
        }

        // Closing balance row
        rows.add([
          '23:59',
          'CLOSING BALANCE',
          'Opening + Sales - Expenses',
          'ALL',
          summary.closingCash,
          summary.closingUpi,
          summary.closingTotal,
        ]);

        // Gross Totals summary row
        rows.add([
          'GROSS TOTALS',
          'NET DAILY MOVEMENT',
          'Sales: ₹${summary.salesTotal.toStringAsFixed(2)} | Exp: ₹${summary.expensesTotal.toStringAsFixed(2)}',
          'ALL',
          summary.netCash,
          summary.netUpi,
          summary.netTotal,
        ]);

        if (isPdf) {
          await ReportExportService.exportToPdf(
            reportTitle: 'Daily Settlement Report',
            dateRangeStr: dateStr,
            headers: headers,
            rows: rows,
          );
        } else {
          await ReportExportService.exportToExcel(
            reportTitle: 'Daily Settlement Report',
            dateRangeStr: dateStr,
            headers: headers,
            rows: rows,
          );
        }
      } else {
        final monthStr = DateFormat('MMMM yyyy').format(sState.selectedMonth);
        final headers = ['Date', 'Cash Sales', 'Cash Exp', 'Cash Net', 'UPI Sales', 'UPI Exp', 'UPI Net', 'Total Net'];
        final rows = sState.monthlyDays.map((d) => [
          DateFormat('yyyy-MM-dd').format(d.date),
          d.salesCash,
          d.expensesCash,
          d.netCash,
          d.salesUpi,
          d.expensesUpi,
          d.netUpi,
          d.netTotal,
        ]).toList();

        // Bottom Gross Row
        rows.add([
          'GROSS TOTALS',
          sState.grossMonthlyCashSales,
          sState.grossMonthlyCashExpenses,
          sState.grossMonthlyCashNet,
          sState.grossMonthlyUpiSales,
          sState.grossMonthlyUpiExpenses,
          sState.grossMonthlyUpiNet,
          sState.grossMonthlyTotalNet,
        ]);

        if (isPdf) {
          await ReportExportService.exportToPdf(
            reportTitle: 'Monthly Settlement Report',
            dateRangeStr: monthStr,
            headers: headers,
            rows: rows,
          );
        } else {
          await ReportExportService.exportToExcel(
            reportTitle: 'Monthly Settlement Report',
            dateRangeStr: monthStr,
            headers: headers,
            rows: rows,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settlement report exported successfully!'), backgroundColor: AppColors.primaryGreen),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  // ===========================================================================
  // SECTION 2: SALES REPORTS (THE 9 OPERATIONAL SALES REPORTS)
  // ===========================================================================

  Widget _buildSalesSection(BuildContext context, AdminState state, AdminNotifier notifier) {
    final filteredRows = state.reportRows.where((r) {
      if (_filterQuery.isEmpty) return true;
      final q = _filterQuery.toLowerCase();
      return r.values.any((v) => v != null && v.toString().toLowerCase().contains(q));
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Report Type Selector Chips
        _buildReportTypeSelector(state, notifier),
        const SizedBox(height: 10),

        // 1.1 Period Filter Bar (Daily | Monthly | Custom Date Range)
        _buildPeriodFilterBar(context, state, notifier),
        const SizedBox(height: 10),

        // 2. Filter & Export Control Panel
        _buildFilterAndExportHeader(context, state, notifier, filteredRows.length),
        const SizedBox(height: 12),

        // 3. Main Data Table Container
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: state.isLoadingReport
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: AppColors.primaryGreen),
                        SizedBox(height: 12),
                        Text('Loading report data from database...', style: TextStyle(fontSize: 13, color: Colors.grey)),
                      ],
                    ),
                  )
                : filteredRows.isEmpty
                    ? _buildEmptyState(state, notifier)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: _buildDataTable(state.selectedReportType, filteredRows),
                            ),
                          ),
                        ),
                      ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // SECTION 3: EXPENSE REPORTS (TRANSACTIONS & CATEGORY BREAKDOWN)
  // ===========================================================================

  Widget _buildExpensesSection(BuildContext context, AdminState state, AdminNotifier notifier) {
    final expenses = state.expenseTransactions;
    final total = expenses.fold<double>(0.0, (sum, e) => sum + e.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header summary
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 450;
              return isCompact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('EXPENSE REPORT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text('Total Recorded: ₹${total.toStringAsFixed(2)} (${expenses.length} bills)',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F2E1E))),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: () => notifier.setNavIndex(2),
                          icon: const Icon(Icons.open_in_new, size: 14),
                          label: const Text('Open Expense Desk'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF266540),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('EXPENSE REPORT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                              const SizedBox(height: 4),
                              Text('Total Recorded: ₹${total.toStringAsFixed(2)} (${expenses.length} bills)',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F2E1E)),
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => notifier.setNavIndex(2),
                          icon: const Icon(Icons.open_in_new, size: 14),
                          label: const Text('Open Expense Desk'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF266540),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    );
            },
          ),
        ),
        const SizedBox(height: 12),

        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: expenses.isEmpty
                ? const Center(child: Text('No expenses recorded.', style: TextStyle(color: Colors.grey)))
                : ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F8F4)),
                          columns: const [
                            DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Method', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Amount (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Sub-Expenses Breakdown', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Notes', style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: expenses.map((e) {
                            return DataRow(
                              cells: [
                                DataCell(Text(DateFormat('dd MMM yyyy').format(e.expenseDate))),
                                DataCell(Text(e.expenseName, style: const TextStyle(fontWeight: FontWeight.bold))),
                                DataCell(Text(e.paymentMethod.toUpperCase())),
                                DataCell(Text('₹${e.amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFC62828)))),
                                DataCell(Text(e.hasSubExpenses ? e.subExpensesSummary : '-')),
                                DataCell(Text(e.displayNotes.isNotEmpty ? e.displayNotes : '-')),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // EXISTING SALES REPORTS HELPERS (REPORT SELECTOR, HEADERS, DATATABLE)
  // ===========================================================================

  Widget _buildReportTypeSelector(AdminState state, AdminNotifier notifier) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _reportTypes.map((rt) {
          final isSelected = state.selectedReportType == rt['id'];
          return Padding(
            padding: const EdgeInsets.only(right: 6.0),
            child: FilterChip(
              selected: isSelected,
              label: Text(
                rt['name']!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              ),
              backgroundColor: Colors.white,
              selectedColor: const Color(0xFF266540),
              checkmarkColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: isSelected ? const Color(0xFF266540) : Colors.grey.shade300,
                ),
              ),
              onSelected: (_) => notifier.setReportType(rt['id']!),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPeriodFilterBar(
    BuildContext context,
    AdminState state,
    AdminNotifier notifier,
  ) {
    final activeRangeStr = state.dateFilter == AdminDateFilter.custom
        ? '${DateFormat('dd-MM-yyyy').format(state.effectiveStartDate)} → ${DateFormat('dd-MM-yyyy').format(state.effectiveEndDate)}'
        : state.dateFilter == AdminDateFilter.today
            ? DateFormat('dd-MM-yyyy').format(state.effectiveStartDate)
            : '${DateFormat('dd-MM-yyyy').format(state.effectiveStartDate)} → ${DateFormat('dd-MM-yyyy').format(state.effectiveEndDate)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Period:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildPeriodChip(
                    label: 'Daily',
                    isSelected: state.dateFilter == AdminDateFilter.today,
                    onTap: () {
                      notifier.setDateFilter(AdminDateFilter.today);
                      notifier.loadReportData();
                    },
                  ),
                  const SizedBox(width: 6),
                  _buildPeriodChip(
                    label: 'Monthly',
                    isSelected: state.dateFilter == AdminDateFilter.thisMonth,
                    onTap: () {
                      notifier.setDateFilter(AdminDateFilter.thisMonth);
                      notifier.loadReportData();
                    },
                  ),
                  const SizedBox(width: 6),
                  _buildPeriodChip(
                    label: 'Custom',
                    isSelected: state.dateFilter == AdminDateFilter.custom,
                    onTap: () {
                      notifier.setDateFilter(
                        AdminDateFilter.custom,
                        customStart: _customFromDate,
                        customEnd: _customToDate,
                      );
                      notifier.loadReportData();
                    },
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.date_range_rounded, size: 12, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 4),
                    Text(
                      activeRangeStr,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (state.dateFilter == AdminDateFilter.custom) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                _buildDatePickerField(
                  label: 'From Date',
                  date: _customFromDate,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _customFromDate,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() => _customFromDate = picked);
                    }
                  },
                ),
                const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey),
                _buildDatePickerField(
                  label: 'To Date',
                  date: _customToDate,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _customToDate,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() => _customToDate = picked);
                    }
                  },
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF266540),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    final start = DateTime(_customFromDate.year, _customFromDate.month, _customFromDate.day);
                    final end = DateTime(_customToDate.year, _customToDate.month, _customToDate.day);
                    if (start.isAfter(end)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('From Date cannot be after To Date.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    notifier.setDateFilter(
                      AdminDateFilter.custom,
                      customStart: start,
                      customEnd: end,
                    );
                    notifier.loadReportData();
                  },
                  child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPeriodChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF266540) : const Color(0xFFF1F3F4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF266540) : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildDatePickerField({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label: ',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
            ),
            Text(
              DateFormat('dd-MM-yyyy').format(date),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1B4332)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.calendar_today, size: 14, color: Color(0xFF1B4332)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterAndExportHeader(
    BuildContext context,
    AdminState state,
    AdminNotifier notifier,
    int recordCount,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _filterQuery = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Search in results...',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                  suffixIcon: _filterQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _filterQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF8F9FA),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$recordCount records',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF266540)),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'Export',
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF266540),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text('Export', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            onSelected: (val) => notifier.exportCurrentReport(isPdf: val == 'pdf'),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'excel', child: Text('Export Excel (.xlsx)')),
              PopupMenuItem(value: 'pdf', child: Text('Export PDF (.pdf)')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AdminState state, AdminNotifier notifier) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'No records found for selected period',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildDataTable(String reportType, List<Map<String, dynamic>> rows) {
    switch (reportType) {
      case 'sales':
        final totalSales = rows.fold<double>(0.0, (sum, r) => sum + (num.tryParse(r['final_amount']?.toString() ?? r['total_amount']?.toString() ?? '0') ?? 0).toDouble());
        return DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F8F4)),
          columns: const [
            DataColumn(label: Text('Date & Time', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Bill No', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Order Type', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Table', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Discount', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Total', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Payment', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: [
            ...rows.map((r) {
              final dtStr = r['created_at'] != null
                  ? AppDateTime.formatDateTime(r['created_at'])
                  : (r['date'] ?? '');
              return DataRow(
                cells: [
                  DataCell(Text(dtStr)),
                  DataCell(Text(r['bill_number'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(Text((r['order_type'] ?? '').toString().toUpperCase())),
                  DataCell(Text(r['table_number'] ?? '-')),
                  DataCell(Text(ReportExportService.formatCurrency(r['discount_amount']))),
                  DataCell(Text(
                    ReportExportService.formatCurrency(r['final_amount'] ?? r['total_amount']),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B4332)),
                  )),
                  DataCell(Text((r['payment_method'] ?? 'cash').toString().toUpperCase())),
                ],
              );
            }),
            if (rows.isNotEmpty)
              DataRow(
                color: WidgetStateProperty.all(const Color(0xFFE8F5E9)),
                cells: [
                  DataCell(Text('GROSS TOTAL (${rows.length} bills)', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B4332)))),
                  const DataCell(Text('-')),
                  const DataCell(Text('-')),
                  const DataCell(Text('-')),
                  const DataCell(Text('-')),
                  DataCell(Text(
                    ReportExportService.formatCurrency(totalSales),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B4332)),
                  )),
                  const DataCell(Text('-')),
                ],
              ),
          ],
        );

      case 'payment':
        final totalTx = rows.fold<int>(0, (sum, r) => sum + (int.tryParse(r['transaction_count']?.toString() ?? '0') ?? 0));
        final totalAmount = rows.fold<double>(0.0, (sum, r) => sum + (num.tryParse(r['total_amount']?.toString() ?? '0') ?? 0).toDouble());
        return DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F8F4)),
          columns: const [
            DataColumn(label: Text('Payment Method', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Transactions Count', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Total Collected', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: [
            ...rows.map((r) {
              return DataRow(
                cells: [
                  DataCell(Text((r['payment_method'] ?? '').toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(Text(r['transaction_count']?.toString() ?? '0')),
                  DataCell(Text(
                    ReportExportService.formatCurrency(r['total_amount']),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B4332)),
                  )),
                ],
              );
            }),
            if (rows.isNotEmpty)
              DataRow(
                color: WidgetStateProperty.all(const Color(0xFFE8F5E9)),
                cells: [
                  const DataCell(Text('GROSS TOTAL', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B4332)))),
                  DataCell(Text('$totalTx', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B4332)))),
                  DataCell(Text(
                    ReportExportService.formatCurrency(totalAmount),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B4332)),
                  )),
                ],
              ),
          ],
        );

      default:
        // Generic fallback for other sub-types (Product, Category, Server, Table, Order Type, Offer, Cancellation)
        if (rows.isEmpty) return const SizedBox();
        final keys = rows.first.keys.toList();
        return DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F8F4)),
          columns: keys.map((k) => DataColumn(label: Text(k.replaceAll('_', ' ').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
          rows: [
            ...rows.map((r) {
              return DataRow(
                cells: keys.map((k) {
                  final val = r[k];
                  if (k.contains('amount') || k.contains('sales') || k.contains('total') || k.contains('loss')) {
                    return DataCell(Text(ReportExportService.formatCurrency(val), style: const TextStyle(fontWeight: FontWeight.bold)));
                  }
                  return DataCell(Text(val?.toString() ?? '-'));
                }).toList(),
              );
            }),
            if (rows.isNotEmpty)
              DataRow(
                color: WidgetStateProperty.all(const Color(0xFFE8F5E9)),
                cells: keys.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final k = entry.value;
                  if (idx == 0) {
                    return DataCell(Text('GROSS TOTAL (${rows.length} rows)', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B4332))));
                  }
                  if (k.contains('amount') || k.contains('sales') || k.contains('total') || k.contains('loss') || k.contains('share')) {
                    final colSum = rows.fold<double>(0.0, (sum, r) => sum + (num.tryParse(r[k]?.toString() ?? '0') ?? 0).toDouble());
                    return DataCell(Text(ReportExportService.formatCurrency(colSum), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B4332))));
                  }
                  if (k.contains('quantity') || k.contains('count') || k.contains('bills') || k.contains('orders') || k.contains('items')) {
                    final colCount = rows.fold<int>(0, (sum, r) => sum + (int.tryParse(r[k]?.toString() ?? '0') ?? 0));
                    return DataCell(Text('$colCount', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B4332))));
                  }
                  return const DataCell(Text('-'));
                }).toList(),
              ),
          ],
        );
    }
  }
}
