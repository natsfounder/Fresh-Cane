import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/models.dart';

/// Confirmation dialog for cancelling an individual order independently.
class CancelOrderDialog extends StatefulWidget {
  final SessionOrderSummary order;
  final String customerName;

  const CancelOrderDialog({
    super.key,
    required this.order,
    required this.customerName,
  });

  static Future<String?> show({
    required BuildContext context,
    required SessionOrderSummary order,
    required String customerName,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => CancelOrderDialog(
        order: order,
        customerName: customerName,
      ),
    );
  }

  @override
  State<CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends State<CancelOrderDialog> {
  final _reasonController =
      TextEditingController(text: 'Customer requested change');

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusLarge),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width > 460 ? 420 : MediaQuery.of(context).size.width * 0.92,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.errorLight,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.cancel_outlined,
                      color: AppColors.error,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Cancel this order?',
                      style: AppTextStyles.h2.copyWith(
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Order detail card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Column(
                  children: [
                    _row('Order Number', widget.order.orderNumber, bold: true),
                    const SizedBox(height: 8),
                    _row('Customer', widget.customerName),
                    const SizedBox(height: 8),
                    if (widget.order.itemsSummary.isNotEmpty) ...[
                      _row('Items', widget.order.itemsSummary),
                      const SizedBox(height: 8),
                    ],
                    _row(
                      'Order Amount',
                      '${AppConstants.defaultCurrencySymbol}${widget.order.totalAmount.toStringAsFixed(0)}',
                      bold: true,
                      color: AppColors.error,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Reason
              TextField(
                controller: _reasonController,
                style: AppTextStyles.bodyMedium,
                decoration: InputDecoration(
                  labelText: 'Cancellation Reason',
                  hintText: 'e.g. Customer changed mind',
                  hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                    borderSide: const BorderSide(color: AppColors.borderLight),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                    borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.8),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.borderMedium),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Keep Order',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppColors.radiusLarge),
                            ),
                            title: Row(
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  color: AppColors.error,
                                  size: 26,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Confirm Cancellation',
                                    style: AppTextStyles.h3.copyWith(
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            content: Text(
                              'Are you sure you want to cancel Order ${widget.order.orderNumber} for ${widget.customerName}?\n\nThis action cannot be undone.',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: Text(
                                  'Keep Order',
                                  style: AppTextStyles.labelMedium.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.error,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                                  ),
                                ),
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: Text(
                                  'Yes, Cancel Order',
                                  style: AppTextStyles.labelMedium.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );

                        if (confirmed == true && context.mounted) {
                          final reason = _reasonController.text.trim();
                          Navigator.of(context).pop(
                              reason.isNotEmpty ? reason : 'Cancelled by server');
                        }
                      },
                      child: Text(
                        'Cancel Order',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value,
      {bool bold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: color ?? AppColors.primaryDark,
            ),
          ),
        ),
      ],
    );
  }
}
