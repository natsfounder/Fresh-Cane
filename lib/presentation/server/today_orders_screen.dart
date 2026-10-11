import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_time_utils.dart';
import '../../core/theme/responsive.dart';
import '../../models/today_order_model.dart';
import '../../state/today_orders_provider.dart';

/// Screen displaying the authenticated Server's orders for today's business day.
///
/// Features:
/// - Screen title: "Today's Orders"
/// - Isolates strictly to the authenticated Server and current Asia/Kolkata business day.
/// - Header summary metrics: Total Orders, Billable Total, Cancelled Count.
/// - Order cards with order #, dine-in table badge or PARCEL badge, customer details,
///   IST creation time, items summary, and billable total.
/// - Cancelled orders clearly marked with CANCELLED badge, ₹0 billable amount, strike-through,
///   and cancellation reason.
/// - Non-destructive pull-to-refresh.
/// - Polished empty state.
class TodayOrdersScreen extends ConsumerWidget {
  const TodayOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(todayOrdersProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.primaryGreen,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.primaryGradient,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          tooltip: 'Back',
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Today's Orders",
              style: AppTextStyles.h2.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Server Order History  •  Asia/Kolkata Business Day',
              style: AppTextStyles.caption.copyWith(
                color: Colors.white.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: state.isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: () {
              HapticFeedback.lightImpact();
              ref.read(todayOrdersProvider.notifier).refresh();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ─── Header Metrics Summary Bar ─────────────────────────────────
            _buildMetricsSummary(context, state),

            // ─── Orders List or Empty/Loading/Error View ────────────────────
            Expanded(
              child: _buildBody(context, ref, state),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsSummary(BuildContext context, TodayOrdersState state) {
    final padding = Responsive.screenPadding(context);
    final isCompact = Responsive.isCompact(context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: padding.horizontal / 2,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: const Border(
          bottom: BorderSide(color: AppColors.borderLight, width: 1),
        ),
        boxShadow: AppColors.shadowSmall,
      ),
      child: isCompact
          ? Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: _buildMetricCard(
                    title: 'BILLABLE TOTAL',
                    value:
                        '${AppConstants.defaultCurrencySymbol}${state.totalBillableAmount.toStringAsFixed(0)}',
                    subtitle: 'Active Revenue',
                    valueColor: AppColors.primaryGreen,
                    isHighlighted: true,
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        title: 'CUSTOMERS',
                        value: '${state.totalCustomersCount}',
                        subtitle: '${state.totalOrdersCount} orders',
                        valueColor: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'CANCELLED',
                        value: '${state.cancelledOrdersCount}',
                        subtitle: 'Excluded (₹0)',
                        valueColor: state.cancelledOrdersCount > 0
                            ? AppColors.error
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                // Customers Card
                Expanded(
                  child: _buildMetricCard(
                    title: 'CUSTOMERS',
                    value: '${state.totalCustomersCount}',
                    subtitle: '${state.totalOrdersCount} orders',
                    valueColor: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(width: 10),

                // Billable Total Card
                Expanded(
                  flex: 2,
                  child: _buildMetricCard(
                    title: 'BILLABLE TOTAL',
                    value:
                        '${AppConstants.defaultCurrencySymbol}${state.totalBillableAmount.toStringAsFixed(0)}',
                    subtitle: 'Active Revenue',
                    valueColor: AppColors.primaryGreen,
                    isHighlighted: true,
                  ),
                ),
                const SizedBox(width: 10),

                // Cancelled Orders Card
                Expanded(
                  child: _buildMetricCard(
                    title: 'CANCELLED',
                    value: '${state.cancelledOrdersCount}',
                    subtitle: 'Excluded (₹0)',
                    valueColor: state.cancelledOrdersCount > 0
                            ? AppColors.error
                            : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required Color valueColor,
    bool isHighlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isHighlighted ? AppColors.secondaryLight : AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.radiusMedium),
        border: Border.all(
          color: isHighlighted
              ? AppColors.secondaryGreen.withValues(alpha: 0.5)
              : AppColors.borderLight,
        ),
        boxShadow: isHighlighted ? AppColors.glowGreen : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.overline.copyWith(
              color: isHighlighted ? AppColors.primaryDark : AppColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: AppTextStyles.h2.copyWith(
                color: valueColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textTertiary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, WidgetRef ref, TodayOrdersState state) {
    if (state.isLoading && state.visibleOrders.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryGreen),
        ),
      );
    }

    if (state.errorMessage != null && state.visibleOrders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: AppColors.error,
              ),
              const SizedBox(height: 12),
              Text(
                state.errorMessage!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () =>
                    ref.read(todayOrdersProvider.notifier).loadOrders(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (state.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => ref.read(todayOrdersProvider.notifier).refresh(),
        color: AppColors.primaryGreen,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.15),
            Center(
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: AppColors.secondaryLight,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.secondaryGreen.withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  size: 52,
                  color: AppColors.primaryGreen,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No orders today',
              textAlign: TextAlign.center,
              style: AppTextStyles.h2.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Orders you create during today\'s\nbusiness day will appear here.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(todayOrdersProvider.notifier).refresh(),
      color: AppColors.primaryGreen,
      child: ListView.builder(
        padding: Responsive.screenPadding(context),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.visibleOrders.length,
        itemBuilder: (context, index) {
          final order = state.visibleOrders[index];
          return _TodayOrderCard(order: order);
        },
      ),
    );
  }
}

class _TodayOrderCard extends StatelessWidget {
  final TodayOrder order;

  const _TodayOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final isCancelled = order.isCancelled;
    final isParcel = order.tableNumber.trim().isEmpty ||
        order.tableNumber.toUpperCase() == 'PARCEL';
    final timeStr = AppDateTime.formatTime(order.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isCancelled ? AppColors.surface : AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppColors.radiusLarge),
        border: Border.all(
          color: isCancelled
              ? AppColors.borderLight
              : AppColors.woodBrown.withValues(alpha: 0.15),
        ),
        boxShadow: isCancelled ? null : AppColors.shadowSmall,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header: Order Number + Time (Row 1) & Badges (Row 2) ──────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Order Number
                Expanded(
                  child: Text(
                    order.orderNumber,
                    style: AppTextStyles.h3.copyWith(
                      color: isCancelled ? AppColors.textTertiary : AppColors.textPrimary,
                      decoration: isCancelled ? TextDecoration.lineThrough : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),

                // Order Time (IST)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      timeStr,
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Badges Row (Table / Parcel + Bill Number)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Table or Parcel Badge
                if (isParcel)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.infoLight,
                      borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                      border: Border.all(
                        color: AppColors.info.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.takeout_dining_rounded,
                          size: 12,
                          color: AppColors.info,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'PARCEL',
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: AppColors.info,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isCancelled
                          ? AppColors.borderLight
                          : AppColors.secondaryLight,
                      borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                      border: Border.all(
                        color: isCancelled
                            ? AppColors.borderMedium
                            : AppColors.secondaryGreen.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      order.tableNumber.startsWith('Table')
                          ? order.tableNumber
                          : 'Table ${order.tableNumber}',
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isCancelled
                            ? AppColors.textSecondary
                            : AppColors.primaryDark,
                      ),
                    ),
                  ),

                if (order.billNumber != null && order.billNumber!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                      border: Border.all(
                        color: AppColors.primaryGreen.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      'BILL: ${order.billNumber}',
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // ─── Customer Details & Items Summary ─────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline_rounded,
                            size: 14,
                            color: isCancelled
                                ? AppColors.textTertiary
                                : AppColors.textPrimary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            order.customerName,
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isCancelled
                                  ? AppColors.textTertiary
                                  : AppColors.textPrimary,
                            ),
                          ),
                          if (order.customerPhone != null &&
                              order.customerPhone!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              '+91 ${order.customerPhone}',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (order.itemsSummary.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          order.itemsSummary,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: isCancelled
                                ? AppColors.textTertiary
                                : AppColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                // ─── Amount Column ─────────────────────────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (isCancelled) ...[
                      Text(
                        '${AppConstants.defaultCurrencySymbol}${order.rawAmount.toStringAsFixed(0)}',
                        style: AppTextStyles.h2.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppColors.error,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      Text(
                        'CANCELLED',
                        style: AppTextStyles.caption.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.error,
                          fontSize: 10,
                        ),
                      ),
                    ] else
                      Text(
                        '${AppConstants.defaultCurrencySymbol}${order.billableAmount.toStringAsFixed(0)}',
                        style: AppTextStyles.h2.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // ─── Cancelled Order Status Ribbon ────────────────────────────
            if (isCancelled) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cancel_outlined,
                      size: 14,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'CANCELLED (Billable: ₹0)',
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: AppColors.error,
                      ),
                    ),
                    if (order.cancellationReason != null &&
                        order.cancellationReason!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '• ${order.cancellationReason}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(
                            fontStyle: FontStyle.italic,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
