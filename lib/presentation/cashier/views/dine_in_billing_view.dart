import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../../models/models.dart';
import '../../../state/cashier_provider.dart';
import '../../../state/cashier_state.dart';
import '../widgets/bill_summary_dialog.dart';
import '../widgets/payment_dialog.dart';
import '../widgets/receipt_dialog.dart';

/// View for Dine-In Table Billing, Payment Settlement, and Session Closure.
class DineInBillingView extends ConsumerWidget {
  const DineInBillingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cashierState = ref.watch(cashierProvider);
    final notifier = ref.read(cashierProvider.notifier);

    final allTables = cashierState.tables;
    final selectedSession = cashierState.selectedTableSession;

    // Show tables that have finished customers ready for billing, are occupied/dining, or in billing status,
    // plus the currently selected table session if any.
    final activeTables = allTables
        .where((t) =>
            t.isActive &&
            (t.hasFinishedCustomers ||
                t.status == 'billing' ||
                t.isOccupied ||
                (selectedSession != null && selectedSession.tableId == t.id)))
        .toList();

    // All seated customers in the current table session
    final sessionCustomers = selectedSession?.customers ?? [];
    final unpaidCustomers = sessionCustomers
        .where((c) => c.hasUnpaidOrders)
        .toList();

    // Preserve selected customer if valid; otherwise prioritize customers ready for billing, then dining
    final selectedCustomer = (cashierState.selectedCustomer != null &&
            sessionCustomers.any((c) => c.id == cashierState.selectedCustomer!.id))
        ? sessionCustomers.firstWhere((c) => c.id == cashierState.selectedCustomer!.id)
        : (unpaidCustomers.isNotEmpty
            ? unpaidCustomers.first
            : (sessionCustomers.isNotEmpty ? sessionCustomers.first : null));

    final customerName = selectedCustomer?.displayName ??
        (sessionCustomers.isEmpty && selectedSession != null
            ? 'No Customers'
            : 'Dine-In Customer');
    final customerPhone = selectedCustomer?.customerPhone;

    // Orders for the selected customer: show billed orders if customer is already billed, or active orders otherwise
    final displayOrders = selectedCustomer != null
        ? (selectedCustomer.isBilled
            ? selectedCustomer.orders
            : selectedCustomer.orders.where((o) => o.isActive).toList())
        : <SessionOrderSummary>[];

    // Active unbilled orders for billing calculations
    final activeOrders = selectedCustomer != null
        ? selectedCustomer.orders.where((o) => o.isActive).toList()
        : <SessionOrderSummary>[];

    final totalAmount = activeOrders.fold<double>(0.0, (sum, o) => sum + o.totalAmount);
    final totalItemsCount = activeOrders.fold<int>(0, (sum, o) => sum + o.itemsCount);
    final bill = cashierState.activeBill;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 900;
        final detailWidth = isMobile ? constraints.maxWidth : (constraints.maxWidth * 0.6);

        // Adaptive left customer rail width across mobile and tablet, landscape and portrait
        final double customerRailWidth;
        if (detailWidth >= 700) {
          customerRailWidth = 220.0;
        } else if (detailWidth >= 500) {
          customerRailWidth = 190.0;
        } else if (detailWidth >= 380) {
          customerRailWidth = 160.0;
        } else {
          customerRailWidth = 140.0;
        }

        final queueWidget = Container(
          color: AppColors.backgroundLight,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Active Tables (${activeTables.length})',
                          style: AppTextStyles.h3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Billing Queue',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: AppColors.primaryGreen),
                    onPressed: () => notifier.initialize(),
                    tooltip: 'Refresh Queue',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (cashierState.isLoading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (activeTables.isEmpty)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: const BoxDecoration(
                              color: AppColors.primaryLight,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.table_restaurant_rounded,
                              size: 40,
                              color: AppColors.primaryGreen,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No Active Tables',
                            style: AppTextStyles.h4.copyWith(
                              color: AppColors.primaryDark,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Only tables with active customer orders appear here. All tables are currently clear.',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            onPressed: () => notifier.selectMode(CashierMode.parcel),
                            icon: const Icon(Icons.takeout_dining_rounded, size: 18),
                            label: const Text('Parcel / Takeaway'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primaryGreen,
                              side: const BorderSide(color: AppColors.primaryGreen),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isMobile ? 2 : 2,
                      childAspectRatio: 1.3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: activeTables.length,
                    itemBuilder: (context, index) {
                      final table = activeTables[index];
                      final isSelected = selectedSession?.tableId == table.id;
                      final isOccupied = table.isOccupied;

                      final String tableBadgeText;
                      final Color tableBadgeColor;
                      final Color tableBadgeTextColor;

                      if (table.hasFinishedCustomers) {
                        tableBadgeText = 'READY';
                        tableBadgeColor = AppColors.primaryGreen.withValues(alpha: 0.15);
                        tableBadgeTextColor = AppColors.primaryGreen;
                      } else if (table.status == 'billing') {
                        tableBadgeText = 'BILLING';
                        tableBadgeColor = Colors.amber.withValues(alpha: 0.2);
                        tableBadgeTextColor = Colors.amber.shade900;
                      } else if (isOccupied) {
                        tableBadgeText = 'DINING';
                        tableBadgeColor = Colors.orange.withValues(alpha: 0.2);
                        tableBadgeTextColor = Colors.deepOrange;
                      } else {
                        tableBadgeText = table.status.toUpperCase();
                        tableBadgeColor = AppColors.primaryGreen.withValues(alpha: 0.15);
                        tableBadgeTextColor = AppColors.primaryGreen;
                      }

                      return InkWell(
                        onTap: () => notifier.selectTable(table),
                        borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.secondaryLight
                                : (isOccupied ? Colors.orange.shade50 : Colors.white),
                            borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primaryGreen
                                  : (isOccupied ? Colors.orange.shade300 : AppColors.borderLight),
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: AppColors.shadowSmall,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Text(
                                      'Table ${table.tableNumber}',
                                      style: AppTextStyles.h4.copyWith(
                                        color: isSelected ? AppColors.primaryGreen : AppColors.primaryDark,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: tableBadgeColor,
                                      borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                                    ),
                                    child: Text(
                                      tableBadgeText,
                                      style: AppTextStyles.caption.copyWith(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                        color: tableBadgeTextColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.people_outline_rounded, size: 14, color: AppColors.textSecondary),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Cap: ${table.seatingCapacity}',
                                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );

        final readyCount = sessionCustomers.where((c) => c.hasUnpaidOrders).length;
        final diningCount = sessionCustomers.where((c) => c.isActive).length;
        final paidCount = sessionCustomers.where((c) => c.isBilled).length;

        String sessionSubtitle = '';
        if (readyCount > 0 && diningCount > 0) {
          sessionSubtitle = '$readyCount Ready to Bill • $diningCount Dining';
        } else if (readyCount > 0) {
          sessionSubtitle = '$readyCount Customer${readyCount == 1 ? '' : 's'} Ready for Payment';
        } else if (diningCount > 0) {
          sessionSubtitle = '$diningCount Customer${diningCount == 1 ? '' : 's'} Dining In Progress';
        } else if (paidCount > 0) {
          sessionSubtitle = 'All $paidCount Customer${paidCount == 1 ? '' : 's'} Settled';
        } else {
          sessionSubtitle = '${sessionCustomers.length} Customer${sessionCustomers.length == 1 ? '' : 's'}';
        }

        final detailWidget = Container(
          color: Colors.white,
          child: selectedSession == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.touch_app_outlined, size: 48, color: AppColors.textTertiary),
                      const SizedBox(height: 8),
                      Text('Select a table to view orders & bill', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.table_restaurant_rounded, color: AppColors.primaryGreen, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Table ${selectedSession.tableNumber} Session',
                                  style: AppTextStyles.h3,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  sessionSubtitle,
                                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
                            onPressed: () => notifier.returnToDineInQueue(),
                            tooltip: 'Back to tables',
                          ),
                        ],
                      ),
                    ),

                    // Main Content Split: Left (Customers) + Right (Food Items & Settle)
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ─── Left Customer List (Responsive Rail) ─────────
                          Container(
                            width: customerRailWidth,
                            decoration: const BoxDecoration(
                              color: AppColors.backgroundLight,
                              border: Border(
                                right: BorderSide(color: AppColors.borderLight, width: 1),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.people_alt_rounded, size: 14, color: AppColors.primaryGreen),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'CUSTOMERS (${sessionCustomers.length})',
                                          style: AppTextStyles.overline.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.textSecondary,
                                            letterSpacing: 0.8,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: sessionCustomers.isEmpty
                                      ? Center(
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Text(
                                              'No customers in session',
                                              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        )
                                      : ListView.separated(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                          itemCount: sessionCustomers.length,
                                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                                          itemBuilder: (context, idx) {
                                            final c = sessionCustomers[idx];
                                            final isSelected = c.id == selectedCustomer?.id;

                                            final String statusLabel;
                                            final Color statusColor;
                                            if (c.isBilled) {
                                              statusLabel = 'PAID';
                                              statusColor = const Color(0xFF2E7D32);
                                            } else if (c.hasUnpaidOrders) {
                                              statusLabel = 'READY';
                                              statusColor = const Color(0xFF1E88E5);
                                            } else if (c.isActive) {
                                              statusLabel = 'DINING';
                                              statusColor = Colors.orange.shade800;
                                            } else {
                                              statusLabel = c.status.name.toUpperCase();
                                              statusColor = AppColors.textSecondary;
                                            }

                                            return InkWell(
                                              onTap: () {
                                                HapticFeedback.lightImpact();
                                                notifier.selectCustomer(c);
                                              },
                                              borderRadius: BorderRadius.circular(10),
                                              child: AnimatedContainer(
                                                duration: const Duration(milliseconds: 150),
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: isSelected ? AppColors.secondaryLight : Colors.white,
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color: isSelected ? AppColors.primaryGreen : AppColors.borderLight,
                                                    width: isSelected ? 1.8 : 1,
                                                  ),
                                                  boxShadow: isSelected
                                                      ? [
                                                          BoxShadow(
                                                            color: AppColors.primaryGreen.withValues(alpha: 0.15),
                                                            blurRadius: 6,
                                                            offset: const Offset(0, 2),
                                                          ),
                                                        ]
                                                      : null,
                                                ),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    // Row 1: Icon + Name + Checkmark
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.person_rounded,
                                                          size: 14,
                                                          color: isSelected ? AppColors.primaryGreen : AppColors.textSecondary,
                                                        ),
                                                        const SizedBox(width: 5),
                                                        Expanded(
                                                          child: Text(
                                                            c.displayName,
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                                              color: isSelected ? AppColors.primaryDark : AppColors.textPrimary,
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        if (isSelected) ...[
                                                          const SizedBox(width: 4),
                                                          const Icon(
                                                            Icons.check_circle_rounded,
                                                            size: 13,
                                                            color: AppColors.primaryGreen,
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                    // Row 2: Phone number if present
                                                    if (c.customerPhone != null && c.customerPhone!.trim().isNotEmpty) ...[
                                                      const SizedBox(height: 2),
                                                      Padding(
                                                        padding: const EdgeInsets.only(left: 19),
                                                        child: Text(
                                                          c.customerPhone!.trim(),
                                                          style: const TextStyle(
                                                            fontSize: 10,
                                                            color: AppColors.textSecondary,
                                                            fontWeight: FontWeight.w500,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                    const SizedBox(height: 5),
                                                    // Row 3: Status Badge + Amount
                                                    Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                          decoration: BoxDecoration(
                                                            color: statusColor.withValues(alpha: 0.12),
                                                            borderRadius: BorderRadius.circular(4),
                                                            border: Border.all(
                                                              color: statusColor.withValues(alpha: 0.3),
                                                              width: 0.8,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            statusLabel,
                                                            style: TextStyle(
                                                              fontSize: 9,
                                                              fontWeight: FontWeight.w700,
                                                              color: statusColor,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Flexible(
                                                          child: Text(
                                                            c.activeOrdersCount > 0 || c.activeTotal > 0
                                                                ? '₹${c.activeTotal.toStringAsFixed(0)}'
                                                                : '₹0',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.w800,
                                                              color: isSelected ? AppColors.primaryGreen : AppColors.textPrimary,
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    if (c.activeOrdersCount > 0) ...[
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '${c.activeOrdersCount} order${c.activeOrdersCount == 1 ? '' : 's'}',
                                                        style: const TextStyle(
                                                          fontSize: 9,
                                                          color: AppColors.textSecondary,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),

                          // ─── Right Panel: Orders, Food Items, Totals & Pay ─
                          Expanded(
                            child: Container(
                              color: Colors.white,
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Customer Subtitle in Right Pane
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    customerName,
                                                    style: AppTextStyles.h3,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (selectedCustomer != null) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: selectedCustomer.isBilled
                                                          ? const Color(0xFF2E7D32).withValues(alpha: 0.12)
                                                          : (selectedCustomer.hasUnpaidOrders
                                                              ? const Color(0xFF1E88E5).withValues(alpha: 0.12)
                                                              : Colors.orange.withValues(alpha: 0.15)),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(
                                                        color: selectedCustomer.isBilled
                                                            ? const Color(0xFF2E7D32).withValues(alpha: 0.3)
                                                            : (selectedCustomer.hasUnpaidOrders
                                                                ? const Color(0xFF1E88E5).withValues(alpha: 0.3)
                                                                : Colors.orange.withValues(alpha: 0.3)),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      selectedCustomer.isBilled
                                                          ? 'PAID'
                                                          : (selectedCustomer.hasUnpaidOrders ? 'READY TO BILL' : 'DINING'),
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w700,
                                                        color: selectedCustomer.isBilled
                                                            ? const Color(0xFF2E7D32)
                                                            : (selectedCustomer.hasUnpaidOrders
                                                                ? const Color(0xFF1E88E5)
                                                                : Colors.orange.shade800),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            if (customerPhone != null && customerPhone.isNotEmpty)
                                              Text(
                                                '+91 $customerPhone',
                                                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  // Status Notice for Dining or Paid
                                  if (selectedCustomer?.isBilled == true)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.green.shade300),
                                      ),
                                      child: Row(
                                        children: const [
                                          Icon(Icons.check_circle_rounded, size: 14, color: AppColors.primaryGreen),
                                          SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Bill settled & paid for this customer.',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF133824),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else if (selectedCustomer?.isActive == true)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.amber.shade300),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.restaurant_rounded, size: 14, color: Colors.orange.shade800),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Customer is dining. Orders placed are shown below.',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.orange.shade900,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                  const Divider(height: 1),
                                  const SizedBox(height: 8),

                                  // Order Items Breakdown
                                  Expanded(
                                    child: () {
                                      if (displayOrders.isEmpty) {
                                        return Center(
                                          child: Padding(
                                            padding: const EdgeInsets.all(24.0),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(16),
                                                  decoration: const BoxDecoration(
                                                    color: AppColors.primaryLight,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(
                                                    selectedCustomer?.isBilled == true
                                                        ? Icons.check_circle_outline_rounded
                                                        : Icons.receipt_long_outlined,
                                                    size: 40,
                                                    color: AppColors.primaryGreen,
                                                  ),
                                                ),
                                                const SizedBox(height: 16),
                                                Text(
                                                  selectedCustomer?.isBilled == true
                                                      ? 'Bill Paid & Settled'
                                                      : 'No Active Orders',
                                                  style: AppTextStyles.h4.copyWith(color: AppColors.primaryDark),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  selectedCustomer?.isBilled == true
                                                      ? 'All orders for this customer have been billed and paid.'
                                                      : 'No orders have been recorded yet for $customerName.',
                                                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }

                                      return ListView(
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        children: [
                                          if (displayOrders.length > 1)
                                            Container(
                                              margin: const EdgeInsets.only(bottom: 10),
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: AppColors.primaryLight,
                                                borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                                                border: Border.all(
                                                  color: AppColors.primaryGreen.withValues(alpha: 0.35),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      '${displayOrders.length} Orders Placed',
                                                      style: AppTextStyles.labelMedium.copyWith(
                                                        fontWeight: FontWeight.bold,
                                                        color: AppColors.primaryDark,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Flexible(
                                                    child: Text(
                                                      'Total: ₹${totalAmount.toStringAsFixed(2)}',
                                                      style: AppTextStyles.h4.copyWith(
                                                        color: AppColors.primaryGreen,
                                                        fontWeight: FontWeight.w800,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      textAlign: TextAlign.right,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ...displayOrders.map((order) {
                                            return Container(
                                              margin: const EdgeInsets.only(bottom: 10),
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: AppColors.surfaceLight,
                                                borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                                                border: Border.all(color: AppColors.borderLight),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          'Order #${order.orderNumber}',
                                                          style: AppTextStyles.h4,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        '₹${order.totalAmount.toStringAsFixed(2)}',
                                                        style: AppTextStyles.h4.copyWith(color: AppColors.primaryGreen),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          '${order.itemsCount} Item(s)',
                                                          style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Flexible(
                                                        child: Text(
                                                          'Status: ${order.status.toUpperCase()}',
                                                          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      if (order.createdAt != null) ...[
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          '• ${AppDateTime.formatTime(order.createdAt)}',
                                                          style: AppTextStyles.caption.copyWith(
                                                            color: AppColors.textSecondary,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    order.itemsSummary.isNotEmpty
                                                        ? order.itemsSummary
                                                        : 'Order items summary not available.',
                                                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                                                    maxLines: 3,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            );
                                          }),
                                        ],
                                      );
                                    }(),
                                  ),
                                  const Divider(),

                                  // Action Controls (Generate Bill / Settle)
                                  if (cashierState.errorMessage != null) ...[
                                    Text(
                                      cashierState.errorMessage!,
                                      style: AppTextStyles.caption.copyWith(color: AppColors.error),
                                    ),
                                    const SizedBox(height: 8),
                                  ],

                                  if (selectedCustomer?.isBilled == true)
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryLight,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.3)),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.check_circle_rounded, color: AppColors.primaryGreen, size: 18),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Bill Settled (₹${selectedCustomer?.activeTotal.toStringAsFixed(2) ?? '0.00'})',
                                            style: const TextStyle(
                                              color: AppColors.primaryDark,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else if (selectedCustomer?.isFinished == true && activeOrders.isNotEmpty) ...[
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (bill == null) ...[
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton.icon(
                                              onPressed: cashierState.isSubmitting
                                                  ? null
                                                  : () async {
                                                      final combinedItemsSummary = activeOrders
                                                          .map((o) => o.itemsSummary)
                                                          .where((s) => s.isNotEmpty)
                                                          .join('; ');

                                                      final combinedOrder = SessionOrderSummary(
                                                        id: activeOrders.first.id,
                                                        orderNumber: activeOrders.length > 1
                                                            ? '${activeOrders.first.orderNumber} (+${activeOrders.length - 1} more)'
                                                            : activeOrders.first.orderNumber,
                                                        status: activeOrders.first.status,
                                                        totalAmount: totalAmount,
                                                        itemsCount: totalItemsCount,
                                                        itemsSummary: combinedItemsSummary,
                                                      );

                                                      final result = await BillSummaryDialog.show(
                                                         context: context,
                                                         order: combinedOrder,
                                                         customerName: customerName,
                                                       );
                                                       if (result != null) {
                                                         await notifier.generateBillForOrder(
                                                           activeOrders.first.id,
                                                         );
                                                       }
                                                    },
                                              icon: const Icon(Icons.receipt_long_rounded),
                                              label: Text(
                                                activeOrders.length > 1
                                                    ? 'Generate Bill (${activeOrders.length} Orders)'
                                                    : 'Generate Bill',
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppColors.primaryGreen,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                              ),
                                            ),
                                          ),
                                        ] else ...[
                                          Container(
                                            width: double.infinity,
                                            margin: const EdgeInsets.only(bottom: 8),
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: AppColors.primaryLight,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: AppColors.primaryGreen),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.receipt_long_rounded, color: AppColors.primaryGreen, size: 20),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        'Bill #${bill.billNumber}',
                                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primaryDark),
                                                      ),
                                                      Text(
                                                        'Generated at ${AppDateTime.formatTime(bill.createdAt)} • Amount: ₹${bill.finalAmount.toStringAsFixed(2)}',
                                                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton.icon(
                                              onPressed: cashierState.isSubmitting
                                                  ? null
                                                  : () async {
                                                      final payments = await PaymentDialog.show(
                                                        context: context,
                                                        bill: bill,
                                                      );
                                                      if (payments != null && payments.isNotEmpty) {
                                                        final success = await notifier.settleBill(
                                                          bill.id,
                                                          payments,
                                                        );
                                                        if (success && context.mounted) {
                                                          final firstPmt = payments.first;
                                                          final paymentObj = Payment(
                                                            id: 'pmt_${DateTime.now().millisecondsSinceEpoch}',
                                                            billId: bill.id,
                                                            paymentMethod: firstPmt['method'] as String? ?? 'cash',
                                                            amount: bill.finalAmount,
                                                            cashTendered: (firstPmt['cash_tendered'] as num?)?.toDouble(),
                                                            changeReturned: (firstPmt['cash_tendered'] as num?) != null ? ((firstPmt['cash_tendered'] as num).toDouble() - bill.finalAmount) : null,
                                                            transactionReference: firstPmt['transaction_reference'] as String?,
                                                            receivedBy: 'cashier',
                                                            status: 'completed',
                                                            createdAt: DateTime.now(),
                                                          );
                                                          final settledTableNumber = selectedSession.tableNumber;
                                                          ReceiptDialog.show(
                                                            context,
                                                            bill: bill,
                                                            payment: paymentObj,
                                                            onFinish: () {
                                                              final currentSession = ref.read(cashierProvider).selectedTableSession;
                                                              final customers = currentSession?.customers ?? [];
                                                              final hasActiveDining = customers.any((c) =>
                                                                  c.isActive ||
                                                                  c.orders.any((o) => o.isActive) ||
                                                                  c.hasUnpaidOrders);
                                                              final remainingUnpaid = customers
                                                                  .where((c) => c.hasUnpaidOrders)
                                                                  .toList();

                                                              if (hasActiveDining) {
                                                                if (context.mounted) {
                                                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                                    SnackBar(
                                                                      content: Row(
                                                                        children: [
                                                                          const Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
                                                                          const SizedBox(width: 8),
                                                                          Expanded(
                                                                            child: Text(
                                                                              '✓ Bill settled for $customerName. Remaining customer(s) still dining at Table $settledTableNumber.',
                                                                              style: const TextStyle(fontWeight: FontWeight.w600),
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                      backgroundColor: const Color(0xFF266540),
                                                                      duration: const Duration(seconds: 4),
                                                                      behavior: SnackBarBehavior.floating,
                                                                    ),
                                                                  );
                                                                }
                                                              } else if (remainingUnpaid.isEmpty) {
                                                                notifier.returnToDineInQueue();
                                                                if (context.mounted) {
                                                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                                    SnackBar(
                                                                      content: Row(
                                                                        children: [
                                                                          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                                                                          const SizedBox(width: 8),
                                                                          Expanded(
                                                                            child: Text(
                                                                              '✓ All bills settled. Table $settledTableNumber closed and freed automatically.',
                                                                              style: const TextStyle(fontWeight: FontWeight.w600),
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                      backgroundColor: const Color(0xFF133824),
                                                                      duration: const Duration(seconds: 4),
                                                                      behavior: SnackBarBehavior.floating,
                                                                    ),
                                                                  );
                                                                }
                                                              }
                                                            },
                                                          );
                                                        }
                                                      }
                                                    },
                                              icon: const Icon(Icons.payments_rounded),
                                              label: Text('Settle (₹${bill.finalAmount.toStringAsFixed(2)})'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF266540),
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(vertical: 14),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                elevation: 2,
                                                shadowColor: const Color(0xFF266540).withValues(alpha: 0.3),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ] else if (selectedCustomer?.isActive == true && activeOrders.isNotEmpty) ...[
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade50,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.amber.shade400),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.hourglass_top_rounded, color: Colors.orange.shade800, size: 22),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Dining In Progress — Server Must Finish Order',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color: Colors.orange.shade900,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'The server has not marked $customerName as finished yet. Bills can only be generated after the server marks this customer as finished.',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.orange.shade900,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
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

        if (isMobile) {
          if (selectedSession == null) {
            return queueWidget;
          } else {
            return detailWidget;
          }
        }

        return Row(
          children: [
            Expanded(flex: 4, child: queueWidget),
            const VerticalDivider(width: 1),
            Expanded(flex: 6, child: detailWidget),
          ],
        );
      },
    );
  }
}
