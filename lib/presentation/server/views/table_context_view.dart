import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/responsive.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../../models/models.dart';
import '../../../state/server_order_provider.dart';
import '../widgets/add_customer_dialog.dart';
import '../widgets/cancel_order_dialog.dart';
import '../widgets/edit_order_bottom_sheet.dart';
import '../widgets/finish_customer_dialog.dart';
import '../widgets/swap_table_dialog.dart';

/// Step 2: Table Context Screen.
///
/// Displays the active table session, seated customers, individual order histories,
/// active billable totals (excluding cancelled orders), order cancellation actions,
/// and "+ Add Customer" capability.
class TableContextView extends ConsumerWidget {
  const TableContextView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderState = ref.watch(serverOrderProvider);
    final table = orderState.activeTable;
    final sessionDetails = orderState.activeSessionDetails;
    final isLoading = orderState.isLoading;

    if (table == null) {
      return const Scaffold(
        body: Center(child: Text('No table active')),
      );
    }

    final customers = sessionDetails?.customers ?? [];
    final activeOrdersCount = sessionDetails?.activeOrdersCount ?? 0;
    final activeTotal = sessionDetails?.activeTotal ?? 0.0;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Table Context Top Header ─────────────────────────────────
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 500;

                return Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: Responsive.value(context,
                        mobile: 10.0, tablet: 20.0),
                    vertical: Responsive.value(context,
                        mobile: 8.0, tablet: 14.0),
                  ),
                  decoration: const BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x30000000),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top row: Back + Table Badge + Session Info + Refresh
                      Row(
                        children: [
                          // Back Button to Table Selection
                          IconButton(
                            icon: const Icon(Icons.arrow_back_rounded,
                                color: Colors.white, size: 22),
                            tooltip: 'Change Table',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              ref
                                  .read(serverOrderProvider.notifier)
                                  .returnToTableSelection();
                            },
                          ),
                          const SizedBox(width: 6),

                          // Table Name Badge — glass pill
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.secondaryGreen,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.secondaryGreen
                                      .withValues(alpha: 0.3),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Text(
                              table.tableNumber,
                              style: AppTextStyles.h3.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Session Summary Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${customers.length} Customer${customers.length == 1 ? '' : 's'}  •  $activeOrdersCount Order${activeOrdersCount == 1 ? '' : 's'}',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (!isCompact)
                                  Text(
                                    '${table.seatingCapacity} Seats  •  Dine-In Session',
                                    style: AppTextStyles.caption.copyWith(
                                      color:
                                          Colors.white.withValues(alpha: 0.7),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          // Active Billable Total Indicator (inline on wider screens)
                          if (!isCompact)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius:
                                    BorderRadius.circular(AppColors.radiusMedium),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'ACTIVE TOTAL',
                                    style: AppTextStyles.overline.copyWith(
                                      color:
                                          Colors.white.withValues(alpha: 0.8),
                                    ),
                                  ),
                                  Text(
                                    '${AppConstants.defaultCurrencySymbol}${activeTotal.toStringAsFixed(0)}',
                                    style: AppTextStyles.moneyLarge.copyWith(
                                      color: AppColors.secondaryBright,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(width: 4),

                          // Refresh Button
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded,
                                color: Colors.white70, size: 22),
                            tooltip: 'Refresh Session',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              ref
                                  .read(serverOrderProvider.notifier)
                                  .refreshActiveSession();
                            },
                          ),
                        ],
                      ),

                      // Mobile: Show Active Total in a second row
                      if (isCompact) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${table.seatingCapacity} Seats  •  Dine-In',
                              style: AppTextStyles.caption.copyWith(
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Total: ${AppConstants.defaultCurrencySymbol}${activeTotal.toStringAsFixed(0)}',
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: AppColors.secondaryBright,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),

            // ─── All Customers Finished / Billing Ready Banner ─────────────
            if (sessionDetails != null &&
                (sessionDetails.isBilling ||
                    (customers.isNotEmpty &&
                        customers.every((c) => !c.canOrder))))
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.statusBillingReadyBg,
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.statusBillingReadyBorder,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.hourglass_top_rounded,
                      color: AppColors.statusBillingReady,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'All customers finished • Waiting for Cashier billing',
                            style: AppTextStyles.labelMedium.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF92400E),
                            ),
                          ),
                          Text(
                            'Table remains occupied. Cashier will generate bill and process payment.',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.statusBillingReady,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.statusBillingReadyBorder,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'OCCUPIED',
                        style: AppTextStyles.statusBadge.copyWith(
                          color: const Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ─── Actions Strip: Add Customer ──────────────────────────────
            Builder(
              builder: (context) {
                final isNarrow = MediaQuery.of(context).size.width < 450;
                return Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isNarrow ? 14 : 24,
                    vertical: isNarrow ? 10 : 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    border: Border(
                      bottom: BorderSide(color: AppColors.borderLight),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.group_outlined,
                          color: AppColors.primaryGreen, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Seated Customers',
                          style: AppTextStyles.h3.copyWith(
                            color: AppColors.primaryDark,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          HapticFeedback.lightImpact();
                          final nextNum = customers.length + 1;
                          final result = await AddCustomerDialog.show(
                            context: context,
                            suggestedLabel: 'Customer $nextNum',
                          );

                          if (result != null) {
                            await ref
                                .read(serverOrderProvider.notifier)
                                .addCustomerToTable(
                                  name: result['name'],
                                  phone: result['phone'],
                                );
                          }
                        },
                        icon: const Icon(Icons.person_add_rounded, size: 18),
                        label: Text(isNarrow ? 'Add' : '+ Add Customer'),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                              horizontal: isNarrow ? 12 : 18,
                              vertical: isNarrow ? 8 : 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // ─── Customers & Orders List ───────────────────────────────────
            Expanded(
              child: isLoading && sessionDetails == null
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryGreen,
                      ),
                    )
                  : customers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.group_off_rounded,
                                    size: 48, color: AppColors.primaryGreen),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No customers seated yet.',
                                style: AppTextStyles.h3.copyWith(
                                  color: AppColors.primaryDark,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  final result = await AddCustomerDialog.show(
                                    context: context,
                                    suggestedLabel: 'Customer 1',
                                  );
                                  if (result != null) {
                                    await ref
                                        .read(serverOrderProvider.notifier)
                                        .addCustomerToTable(
                                          name: result['name'],
                                          phone: result['phone'],
                                        );
                                  }
                                },
                                icon: const Icon(Icons.add),
                                label: const Text('Add Customer 1'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: Responsive.screenPadding(context),
                          itemCount: customers.length,
                          itemBuilder: (context, index) {
                            final customer = customers[index];
                            return _CustomerOrderCard(
                              customer: customer,
                              tableNumber: table.tableNumber,
                              tableId: table.id,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerOrderCard extends ConsumerStatefulWidget {
  final SessionCustomer customer;
  final String tableNumber;
  final String tableId;

  const _CustomerOrderCard({
    required this.customer,
    required this.tableNumber,
    required this.tableId,
  });

  @override
  ConsumerState<_CustomerOrderCard> createState() => _CustomerOrderCardState();
}

class _CustomerOrderCardState extends ConsumerState<_CustomerOrderCard> {
  bool _isFinishing = false;

  Future<void> _handleSwapTable() async {
    HapticFeedback.lightImpact();

    final result = await SwapTableDialog.show(
      context: context,
      customer: widget.customer,
      currentTableNumber: widget.tableNumber,
      currentTableId: widget.tableId,
    );

    if (result != null && mounted) {
      final targetNum = result['target_table_number'] ?? 'target';
      final sourceFreed = result['source_table_freed'] == true;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✓ ${widget.customer.displayName} swapped to Table $targetNum successfully!',
            style: AppTextStyles.labelMedium.copyWith(color: Colors.white),
          ),
          backgroundColor: AppColors.primaryGreen,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusSmall),
          ),
          action: !sourceFreed
              ? SnackBarAction(
                  label: 'View Table $targetNum',
                  textColor: Colors.white,
                  onPressed: () {
                    final allTables = ref.read(serverOrderProvider).tables;
                    final target = allTables.firstWhere(
                      (t) => t.id == result['target_table_id'],
                      orElse: () => allTables.first,
                    );
                    ref.read(serverOrderProvider.notifier).openTable(target);
                  },
                )
              : null,
        ),
      );
    }
  }

  Future<void> _handleFinishCustomer() async {
    HapticFeedback.lightImpact();

    final confirmed = await FinishCustomerDialog.show(
      context: context,
      customer: widget.customer,
    );

    if (confirmed != true || !mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    setState(() {
      _isFinishing = true;
    });

    try {
      final success = await ref
          .read(serverOrderProvider.notifier)
          .finishCustomer(widget.customer.id);

      if (!mounted) return;

      if (success) {
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              '✓ ${widget.customer.displayName} finished ordering. Ready for Cashier.',
              style: AppTextStyles.labelMedium.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.primaryDark,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppColors.radiusSmall),
            ),
          ),
        );
      } else {
        final err = ref.read(serverOrderProvider).errorMessage ??
            'Failed to finish customer';
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              err,
              style: AppTextStyles.labelMedium.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppColors.radiusSmall),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            'Error finishing customer: $e',
            style: AppTextStyles.labelMedium.copyWith(color: Colors.white),
          ),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusSmall),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isFinishing = false;
        });
      }
    }
  }

  Widget _buildStatusBadge(CustomerStatus status) {
    Color fg;
    Color bg;
    String label;
    IconData? icon;

    switch (status) {
      case CustomerStatus.active:
        label = 'ACTIVE';
        fg = AppColors.secondaryGreen;
        bg = AppColors.secondaryLight;
        break;
      case CustomerStatus.finished:
        label = 'FINISHED';
        fg = AppColors.primaryDark;
        bg = AppColors.primaryLight;
        icon = Icons.check_rounded;
        break;
      case CustomerStatus.billed:
        label = 'BILLED';
        fg = AppColors.statusBilled;
        bg = AppColors.statusBilledBg;
        break;
      case CustomerStatus.closed:
        label = 'CLOSED';
        fg = AppColors.statusClosed;
        bg = AppColors.statusClosedBg;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: fg.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.customer;
    final orders = customer.orders;
    final activeOrders = orders.where((o) => o.isActive).toList();
    final canOrder = customer.canOrder;
    final isFinished = customer.isFinished;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppColors.radiusLarge),
        border: Border.all(
          color: isFinished
              ? AppColors.primaryGreen.withValues(alpha: 0.25)
              : AppColors.borderLight,
        ),
        boxShadow: [
          ...AppColors.shadowSmall,
          if (isFinished)
            BoxShadow(
              color: AppColors.primaryGreen.withValues(alpha: 0.08),
              blurRadius: 12,
              spreadRadius: -2,
            ),
        ],
      ),
      child: Padding(
        padding: Responsive.cardPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Customer Header Row ──────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar with status indicator
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: canOrder
                        ? LinearGradient(colors: [
                            AppColors.secondaryGreen.withValues(alpha: 0.15),
                            AppColors.primaryGreen.withValues(alpha: 0.08),
                          ])
                        : null,
                    color: canOrder ? null : AppColors.primaryLight,
                    border: Border.all(
                      color: canOrder
                          ? AppColors.secondaryGreen.withValues(alpha: 0.3)
                          : AppColors.primaryGreen.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    canOrder
                        ? Icons.person_outline_rounded
                        : Icons.check_circle_rounded,
                    color:
                        canOrder ? AppColors.secondaryGreen : AppColors.primaryDark,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              customer.displayName,
                              style: AppTextStyles.h3.copyWith(
                                color: AppColors.primaryDark,
                                fontWeight: FontWeight.w800,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildStatusBadge(customer.status),
                          if (canOrder && activeOrders.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () async {
                                HapticFeedback.lightImpact();
                                final targetOrder = activeOrders.first;
                                final updated = await EditOrderBottomSheet.show(
                                  context: context,
                                  customer: customer,
                                  order: targetOrder,
                                );
                                if (updated == true && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '✓ Order #${targetOrder.orderNumber} updated successfully!',
                                        style: AppTextStyles.labelMedium.copyWith(color: Colors.white),
                                      ),
                                      backgroundColor: AppColors.primaryGreen,
                                    ),
                                  );
                                }
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.primaryGreen.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.edit_outlined,
                                      size: 13,
                                      color: AppColors.primaryDark,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Edit Order',
                                      style: AppTextStyles.caption.copyWith(
                                        color: AppColors.primaryDark,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (customer.customerPhone != null &&
                          customer.customerPhone!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '+91 ${customer.customerPhone}',
                          style: AppTextStyles.caption,
                        ),
                      ],
                      const SizedBox(height: 3),
                      if (isFinished)
                        Text(
                          'Waiting for Cashier billing',
                          style: AppTextStyles.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryDark,
                          ),
                        )
                      else if (customer.isBilled || customer.isClosed)
                        Text(
                          'Billed / Closed by Cashier',
                          style: AppTextStyles.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.statusClosed,
                          ),
                        )
                      else
                        Text(
                          activeOrders.isEmpty
                              ? 'No active orders'
                              : '${activeOrders.length} Active Order${activeOrders.length == 1 ? '' : 's'}  •  Total ${AppConstants.defaultCurrencySymbol}${customer.activeTotal.toStringAsFixed(0)}',
                          style: AppTextStyles.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: activeOrders.isEmpty
                                ? AppColors.textSecondary
                                : AppColors.secondaryGreen,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            // ─── Orders History Section for this Customer ─────────────────
            if (orders.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Divider(height: 1, color: AppColors.borderLight),
              const SizedBox(height: 10),
              Text('ORDER HISTORY', style: AppTextStyles.overline),
              const SizedBox(height: 8),

              ...orders.map((order) {
                final isCancelled = order.isCancelled;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isCancelled
                        ? AppColors.tintedSurface.withValues(alpha: 0.5)
                        : AppColors.warmSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isCancelled
                          ? AppColors.borderMedium
                          : AppColors.borderLight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Row: Order Number, Status Pill, and Amount
                      Row(
                        children: [
                          // Order Number & Status Pill
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        order.orderNumber,
                                        style: AppTextStyles.h4.copyWith(
                                          color: isCancelled
                                              ? AppColors.textTertiary
                                              : AppColors.primaryDark,
                                          decoration: isCancelled
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isCancelled
                                            ? AppColors.statusCancelledBg
                                            : AppColors.statusActiveBg,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isCancelled ? 'CANCELLED' : 'ACTIVE',
                                        style: AppTextStyles.statusBadge.copyWith(
                                          color: isCancelled
                                              ? AppColors.statusCancelled
                                              : AppColors.secondaryGreen,
                                        ),
                                      ),
                                    ),
                                    if (order.createdAt != null) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        '• ${AppDateTime.formatTime(order.createdAt)}',
                                        style: AppTextStyles.caption.copyWith(
                                          color: AppColors.textSecondary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                    if (order.billNumber != null && order.billNumber!.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryLight,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.4)),
                                        ),
                                        child: Text(
                                          'BILL: ${order.billNumber}',
                                          style: AppTextStyles.caption.copyWith(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.primaryDark,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (order.itemsSummary.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    order.itemsSummary,
                                    style: AppTextStyles.caption.copyWith(
                                      color: isCancelled
                                          ? AppColors.textTertiary
                                          : AppColors.textSecondary,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),

                          const SizedBox(width: 8),

                          // Order Amount
                          Text(
                            '${AppConstants.defaultCurrencySymbol}${order.totalAmount.toStringAsFixed(0)}',
                            style: AppTextStyles.moneySmall.copyWith(
                              color: isCancelled
                                  ? AppColors.textTertiary
                                  : AppColors.primaryDark,
                              decoration: isCancelled
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ],
                      ),

                      // Bottom Row: Edit & Cancel Order Action Buttons (only for active orders)
                      if (!isCancelled && canOrder) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                HapticFeedback.lightImpact();
                                final updated = await EditOrderBottomSheet.show(
                                  context: context,
                                  customer: customer,
                                  order: order,
                                );
                                if (updated == true && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '✓ Order #${order.orderNumber} updated successfully!',
                                        style: AppTextStyles.labelMedium.copyWith(color: Colors.white),
                                      ),
                                      backgroundColor: AppColors.primaryGreen,
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 14,
                              ),
                              label: Text(
                                'Edit Order',
                                style: AppTextStyles.labelSmall.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primaryDark,
                                side: BorderSide(
                                  color: AppColors.primaryGreen.withValues(alpha: 0.5),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final reason = await CancelOrderDialog.show(
                                  context: context,
                                  order: order,
                                  customerName: customer.displayName,
                                );

                                if (reason != null) {
                                  HapticFeedback.mediumImpact();
                                  final success = await ref
                                      .read(serverOrderProvider.notifier)
                                      .cancelOrder(order.id, reason: reason);
                                  if (success && context.mounted) {
                                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('✓ Order ${order.orderNumber} cancelled successfully.'),
                                        backgroundColor: AppColors.error,
                                        duration: const Duration(seconds: 3),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(
                                Icons.cancel_outlined,
                                size: 14,
                              ),
                              label: Text(
                                'Cancel',
                                style: AppTextStyles.labelSmall.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.error,
                                side: BorderSide(
                                  color: AppColors.error.withValues(alpha: 0.3),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],

            // ─── Billable Total & Finished Informational Notice ───────────
            if (isFinished) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.warmSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Billable Total',
                      style: AppTextStyles.h4,
                    ),
                    Text(
                      '${AppConstants.defaultCurrencySymbol}${customer.activeTotal.toStringAsFixed(0)}',
                      style: AppTextStyles.moneyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.primaryGreen.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 16, color: AppColors.primaryDark),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ordering completed • Waiting for Cashier billing',
                        style: AppTextStyles.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ─── Customer Card Action Buttons Row ─────────────────────────
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // [Swap Table] Button
                OutlinedButton.icon(
                  onPressed: _isFinishing ? null : _handleSwapTable,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                  label: Text(
                    'Swap Table',
                    style: AppTextStyles.labelMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryDark,
                    side: BorderSide(
                      color: AppColors.primaryGreen.withValues(alpha: 0.5),
                      width: 1.2,
                    ),
                    backgroundColor: AppColors.warmSurface,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),

                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // [Cancel] Button - when customer has no active orders, delete instantly
                    if (activeOrders.isEmpty) ...[
                      OutlinedButton.icon(
                        onPressed: _isFinishing
                            ? null
                            : () async {
                                HapticFeedback.mediumImpact();
                                await ref
                                    .read(serverOrderProvider.notifier)
                                    .deleteCustomer(customer.id);
                              },
                        icon: const Icon(Icons.cancel_outlined, size: 16),
                        label: Text(
                          'Cancel',
                          style: AppTextStyles.labelMedium.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.error,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: BorderSide(
                            color: AppColors.error.withValues(alpha: 0.4),
                            width: 1.2,
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],

                    // [+ Take Order / + New Order] Button - restored when canOrder
                    if (canOrder)
                      ElevatedButton.icon(
                        onPressed: _isFinishing
                            ? null
                            : () {
                                HapticFeedback.lightImpact();
                                ref
                                    .read(serverOrderProvider.notifier)
                                    .selectCustomerForOrdering(customer);
                              },
                        icon: const Icon(Icons.add_shopping_cart_rounded,
                            size: 18),
                        label: Text(
                          activeOrders.isEmpty ? 'Take Order' : 'New Order',
                          style: AppTextStyles.labelMedium.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),

                    // [✓ Finish] Button - only when customer has placed orders
                    if (canOrder && activeOrders.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _isFinishing ? null : _handleFinishCustomer,
                        icon: _isFinishing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      AppColors.primaryDark),
                                ),
                              )
                            : const Icon(Icons.check_circle_outline_rounded,
                                size: 18),
                        label: Text(
                          _isFinishing ? 'Finishing...' : '✓ Finish',
                          style: AppTextStyles.labelMedium.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryDark,
                          side: const BorderSide(
                              color: AppColors.primaryGreen, width: 1.5),
                          backgroundColor: AppColors.primaryLight,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],

                    if (!canOrder)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color:
                                  AppColors.primaryGreen.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded,
                                size: 18, color: AppColors.primaryDark),
                            const SizedBox(width: 6),
                            Text(
                              '✓ Finished',
                              style: AppTextStyles.labelMedium.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
