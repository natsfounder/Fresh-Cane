import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/responsive.dart';
import '../../../models/models.dart';
import '../../../state/server_order_provider.dart';

/// Modal dialog allowing server to transfer a customer and their active orders
/// to another table in the restaurant.
class SwapTableDialog extends ConsumerStatefulWidget {
  final SessionCustomer customer;
  final String currentTableNumber;
  final String currentTableId;

  const SwapTableDialog({
    super.key,
    required this.customer,
    required this.currentTableNumber,
    required this.currentTableId,
  });

  /// Show the dialog responsive to screen size.
  static Future<Map<String, dynamic>?> show({
    required BuildContext context,
    required SessionCustomer customer,
    required String currentTableNumber,
    required String currentTableId,
  }) {
    final isTablet = context.isTablet || context.isDesktop;

    if (isTablet) {
      return showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusXL),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
            child: SwapTableDialog(
              customer: customer,
              currentTableNumber: currentTableNumber,
              currentTableId: currentTableId,
            ),
          ),
        ),
      );
    } else {
      return showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        barrierColor: Colors.black54,
        backgroundColor: Colors.transparent,
        builder: (_) => FractionallySizedBox(
          heightFactor: 0.88,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppColors.radiusXL),
              ),
            ),
            child: SwapTableDialog(
              customer: customer,
              currentTableNumber: currentTableNumber,
              currentTableId: currentTableId,
            ),
          ),
        ),
      );
    }
  }

  @override
  ConsumerState<SwapTableDialog> createState() => _SwapTableDialogState();
}

class _SwapTableDialogState extends ConsumerState<SwapTableDialog> {
  RestaurantTable? _selectedTargetTable;
  bool _isSwapping = false;
  String? _errorMessage;

  Future<void> _handleConfirmSwap() async {
    if (_selectedTargetTable == null || _isSwapping) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _isSwapping = true;
      _errorMessage = null;
    });

    final target = _selectedTargetTable!;

    try {
      final result = await ref
          .read(serverOrderProvider.notifier)
          .swapCustomerTable(
            customer: widget.customer,
            targetTable: target,
          );

      if (!mounted) return;

      if (result != null && result['success'] == true) {
        Navigator.of(context).pop(result);
      } else {
        final err = ref.read(serverOrderProvider).errorMessage ??
            'Failed to transfer customer to Table ${target.tableNumber}';
        setState(() {
          _errorMessage = err;
          _isSwapping = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error swapping table: $e';
        _isSwapping = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderState = ref.watch(serverOrderProvider);
    final allTables = orderState.tables;

    // Filter out the current table where the customer is already seated and sort
    final destinationTables = allTables
        .where((t) => t.id != widget.currentTableId && t.isActive)
        .toList()
      ..sort((a, b) => a.tableNumber.compareTo(b.tableNumber));

    final activeOrders = widget.customer.orders.where((o) => o.isActive).toList();
    final activeTotal = widget.customer.activeTotal;

    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth >= 600 ? 4 : (screenWidth >= 380 ? 3 : 2);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── Header ───────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primaryGreen.withValues(alpha: 0.16),
                      AppColors.secondaryGreen.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                ),
                child: const Icon(
                  Icons.swap_horiz_rounded,
                  color: AppColors.primaryGreen,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Swap Customer Table',
                      style: AppTextStyles.h3.copyWith(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Move customer & active orders to a new table',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 22),
                onPressed: _isSwapping ? null : () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surfaceLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ─── Customer Snapshot Banner ──────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(AppColors.radiusMedium),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primaryLight,
                  child: const Icon(
                    Icons.person_rounded,
                    color: AppColors.primaryDark,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.customer.displayName,
                        style: AppTextStyles.labelLarge.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.borderLight),
                            ),
                            child: Text(
                              'Current: Table ${widget.currentTableNumber}',
                              style: AppTextStyles.caption.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            activeOrders.isEmpty
                                ? '• No orders yet'
                                : '• ${activeOrders.length} ${activeOrders.length == 1 ? 'order' : 'orders'} (${AppConstants.defaultCurrencySymbol}${activeTotal.toStringAsFixed(0)})',
                            style: AppTextStyles.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: activeOrders.isEmpty
                                  ? AppColors.textSecondary
                                  : AppColors.secondaryGreen,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ─── Destination Tables Title ──────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Select Destination Table',
                style: AppTextStyles.labelLarge.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark,
                ),
              ),
              Text(
                '${destinationTables.length} tables',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ─── Tables Grid ───────────────────────────────────────────
          Expanded(
            child: destinationTables.isEmpty
                ? Center(
                    child: Text(
                      'No other dining tables available.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                : GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.15,
                    ),
                    itemCount: destinationTables.length,
                    itemBuilder: (context, index) {
                      final table = destinationTables[index];
                      final isSelected = _selectedTargetTable?.id == table.id;

                      return _DestinationTableCard(
                        table: table,
                        isSelected: isSelected,
                        onTap: () {
                          if (_isSwapping) return;
                          HapticFeedback.selectionClick();
                          setState(() {
                            _selectedTargetTable = table;
                            _errorMessage = null;
                          });
                        },
                      );
                    },
                  ),
          ),

          // ─── Target Explanation / Status Banner ────────────────────
          if (_selectedTargetTable != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _selectedTargetTable!.isAvailable
                    ? AppColors.primaryLight
                    : AppColors.statusOccupiedBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _selectedTargetTable!.isAvailable
                      ? AppColors.primaryGreen.withValues(alpha: 0.35)
                      : AppColors.statusOccupied.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _selectedTargetTable!.isAvailable
                        ? Icons.check_circle_rounded
                        : Icons.info_outline_rounded,
                    size: 18,
                    color: _selectedTargetTable!.isAvailable
                        ? AppColors.primaryDark
                        : AppColors.statusOccupied,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedTargetTable!.isAvailable
                          ? 'Table ${_selectedTargetTable!.tableNumber} is empty. A new dining session will be opened for ${widget.customer.displayName}.'
                          : 'Table ${_selectedTargetTable!.tableNumber} has active guests. ${widget.customer.displayName} will be merged into Table ${_selectedTargetTable!.tableNumber}.',
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: _selectedTargetTable!.isAvailable
                            ? AppColors.primaryDark
                            : AppColors.statusOccupied,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ─── Error Message Banner ──────────────────────────────────
          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 18,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // ─── Actions Row ───────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSwapping ? null : () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.borderLight),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed:
                      (_selectedTargetTable == null || _isSwapping)
                          ? null
                          : _handleConfirmSwap,
                  icon: _isSwapping
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.swap_horiz_rounded, size: 20),
                  label: Text(
                    _isSwapping
                        ? 'Transferring...'
                        : _selectedTargetTable == null
                            ? 'Select a Table'
                            : 'Swap to Table ${_selectedTargetTable!.tableNumber}',
                    style: AppTextStyles.labelLarge.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.borderLight,
                    disabledForegroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DestinationTableCard extends StatelessWidget {
  final RestaurantTable table;
  final bool isSelected;
  final VoidCallback onTap;

  const _DestinationTableCard({
    required this.table,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAvailable = table.isAvailable;

    final Color bg;
    final Color border;
    final Color textPrimary;
    final Color badgeBg;
    final Color badgeText;
    final String statusLabel;

    if (isSelected) {
      bg = AppColors.primaryGreen.withValues(alpha: 0.12);
      border = AppColors.primaryGreen;
      textPrimary = AppColors.primaryDark;
      badgeBg = AppColors.primaryGreen;
      badgeText = Colors.white;
      statusLabel = 'SELECTED';
    } else if (isAvailable) {
      bg = Colors.white;
      border = AppColors.borderLight;
      textPrimary = AppColors.textPrimary;
      badgeBg = AppColors.secondaryLight;
      badgeText = AppColors.secondaryGreen;
      statusLabel = 'AVAILABLE';
    } else {
      bg = AppColors.warmSurface;
      border = AppColors.statusOccupied.withValues(alpha: 0.3);
      textPrimary = AppColors.textPrimary;
      badgeBg = AppColors.statusOccupiedBg;
      badgeText = AppColors.statusOccupied;
      statusLabel = 'OCCUPIED';
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: border,
            width: isSelected ? 2.0 : 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primaryGreen.withValues(alpha: 0.20),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : AppColors.shadowSmall,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.table_restaurant_rounded,
                  size: 16,
                  color: isSelected ? AppColors.primaryDark : AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  table.tableNumber,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              '${table.seatingCapacity} seats',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: badgeText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
