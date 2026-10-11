import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/responsive.dart';
import '../../../models/models.dart';
import '../../../state/server_order_provider.dart';

/// Modal dialog allowing server to select an available dining table.
/// Occupied tables are clearly designated and cannot be chosen.
class TablePickerSheet extends ConsumerWidget {
  const TablePickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    final isTablet = context.isTablet || context.isDesktop;

    if (isTablet) {
      return showDialog(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusXL),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 520),
            child: const TablePickerSheet(),
          ),
        ),
      );
    } else {
      return showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppColors.radiusXL),
          ),
        ),
        builder: (_) => const FractionallySizedBox(
          heightFactor: 0.75,
          child: TablePickerSheet(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderState = ref.watch(serverOrderProvider);
    final tables = orderState.tables.where((t) => t.isActive).toList();
    final selectedTable = orderState.selectedTable;

    final availableCount = tables.where((t) => t.isAvailable).length;
    final occupiedCount = tables.where((t) => t.isOccupied).length;

    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth >= 600 ? 5 : (screenWidth >= 380 ? 4 : 3);

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primaryGreen.withValues(alpha: 0.14),
                      AppColors.secondaryGreen.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                ),
                child: const Icon(
                  Icons.table_restaurant_rounded,
                  color: AppColors.primaryGreen,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Dining Table',
                      style: AppTextStyles.h3.copyWith(
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$availableCount available · $occupiedCount occupied',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surfaceLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Table Grid
          Expanded(
            child: tables.isEmpty
                ? Center(
                    child: Text(
                      'No active tables found.',
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
                      childAspectRatio: 1.0,
                    ),
                    itemCount: tables.length,
                    itemBuilder: (context, index) {
                      final table = tables[index];
                      final isSelected = selectedTable?.id == table.id;
                      final isAvailable = table.isAvailable;

                      return _TableCard(
                        table: table,
                        isSelected: isSelected,
                        onTap: () {
                          if (isAvailable) {
                            HapticFeedback.mediumImpact();
                            ref
                                .read(serverOrderProvider.notifier)
                                .selectTable(table);
                            Navigator.of(context).pop();
                          } else {
                            HapticFeedback.heavyImpact();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Table ${table.tableNumber} is currently occupied.',
                                ),
                                duration: const Duration(seconds: 2),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  final RestaurantTable table;
  final bool isSelected;
  final VoidCallback onTap;

  const _TableCard({
    required this.table,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAvailable = table.isAvailable;

    final Color bg;
    final Color border;
    final Color textColor;
    final Color statusBg;
    final Color statusText;

    if (isSelected) {
      bg = AppColors.primaryGreen.withValues(alpha: 0.10);
      border = AppColors.primaryGreen;
      textColor = AppColors.primaryDark;
      statusBg = AppColors.primaryGreen;
      statusText = Colors.white;
    } else if (isAvailable) {
      bg = Colors.white;
      border = AppColors.borderLight;
      textColor = AppColors.primaryDark;
      statusBg = AppColors.secondaryGreen.withValues(alpha: 0.12);
      statusText = AppColors.primaryGreen;
    } else {
      bg = const Color(0xFFFAFAFA);
      border = AppColors.borderLight;
      textColor = AppColors.textSecondary;
      statusBg = AppColors.warning.withValues(alpha: 0.12);
      statusText = AppColors.warning;
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppColors.radiusMedium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppColors.radiusMedium),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppColors.radiusMedium),
            border: Border.all(
              color: border,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected ? AppColors.glowGreen : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Table number
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    table.tableNumber,
                    style: AppTextStyles.h4.copyWith(
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: AppColors.primaryGreen,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),

              // Seats
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.people_alt_outlined,
                    size: 12,
                    color: textColor.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${table.seatingCapacity} seats',
                    style: AppTextStyles.caption.copyWith(
                      color: textColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                ),
                child: Text(
                  isAvailable ? 'OPEN' : 'IN USE',
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    color: statusText,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
