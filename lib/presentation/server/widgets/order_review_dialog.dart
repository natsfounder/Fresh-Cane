import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../state/server_order_provider.dart';

/// Modal dialog providing a complete pre-submission review of the dine-in order.
class OrderReviewDialog extends ConsumerStatefulWidget {
  const OrderReviewDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const OrderReviewDialog(),
    );
  }

  @override
  ConsumerState<OrderReviewDialog> createState() => _OrderReviewDialogState();
}

class _OrderReviewDialogState extends ConsumerState<OrderReviewDialog> {
  late TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    final currentState = ref.read(serverOrderProvider);
    _notesController = TextEditingController(text: currentState.orderNotes);
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleConfirm() async {
    ref
        .read(serverOrderProvider.notifier)
        .setOrderNotes(_notesController.text.trim());

    final success =
        await ref.read(serverOrderProvider.notifier).submitOrder();

    if (success && mounted) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
    }
  }

  void _appendNote(String text) {
    final current = _notesController.text.trim();
    if (current.isEmpty) {
      _notesController.text = text;
    } else if (!current.contains(text)) {
      _notesController.text = '$current, $text';
    }
    _notesController.selection = TextSelection.fromPosition(
      TextPosition(offset: _notesController.text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderState = ref.watch(serverOrderProvider);
    final table = orderState.activeTable;
    final customer = orderState.selectedCustomer;
    final cartItems = orderState.cart.values.toList();
    final isSubmitting = orderState.isSubmitting;
    final errorMessage = orderState.errorMessage;

    final double baseTotal = cartItems.fold(
      0.0,
      (sum, item) => sum + (item.menuItem.basePrice * item.quantity),
    );
    final double addonsTotal = cartItems.fold(
      0.0,
      (sum, item) => sum + (item.addonsPricePerUnit * item.quantity),
    );

    return Dialog(
      backgroundColor: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusLarge),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width > 600 ? 560 : MediaQuery.of(context).size.width * 0.92,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
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
                      color: AppColors.secondaryLight,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.secondaryGreen.withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
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
                          orderState.isEditingOrder
                              ? 'Review Updated Order'
                              : 'Review Order',
                          style: AppTextStyles.h2.copyWith(
                            color: AppColors.primaryDark,
                          ),
                        ),
                        Text(
                          orderState.isEditingOrder
                              ? 'Editing Order #${orderState.editingOrderNumber} · ${customer?.displayName ?? ""}'
                              : 'Confirm before placing order',
                          style: AppTextStyles.caption.copyWith(
                            color: orderState.isEditingOrder
                                ? AppColors.secondaryGreen
                                : AppColors.textSecondary,
                            fontWeight: orderState.isEditingOrder
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textSecondary),
                    onPressed: isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Error banner
              if (errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.errorLight,
                    borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errorMessage,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Scrollable Middle Body (Never overflows when keyboard opens)
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Table & Customer Context + Order-Level Dining Mode
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius:
                              BorderRadius.circular(AppColors.radiusMedium),
                          border: Border.all(color: AppColors.borderLight),
                        ),
                        child: Row(
                          children: [
                            // Table badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppColors.primaryGreen,
                                borderRadius: BorderRadius.circular(
                                    AppColors.radiusSmall),
                              ),
                              child: Text(
                                table?.tableNumber ?? 'N/A',
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Customer info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    customer?.displayName ?? 'Customer',
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                  if (customer?.customerPhone != null &&
                                      customer!.customerPhone!.isNotEmpty)
                                    Text(
                                      '+91 ${customer.customerPhone}',
                                      style: AppTextStyles.caption.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            // Quick Order-Level Parcel / Dine-In Toggle
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius:
                                    BorderRadius.circular(AppColors.radiusSmall),
                                border:
                                    Border.all(color: AppColors.borderLight),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      ref
                                          .read(serverOrderProvider.notifier)
                                          .setAllParcel(false);
                                    },
                                    borderRadius: const BorderRadius.horizontal(
                                        left: Radius.circular(8)),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: !orderState.isEntireOrderParcel
                                            ? AppColors.primaryGreen
                                            : Colors.transparent,
                                        borderRadius:
                                            const BorderRadius.horizontal(
                                                left: Radius.circular(7)),
                                      ),
                                      child: Text(
                                        '🍽️ Dine-In',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: !orderState.isEntireOrderParcel
                                              ? Colors.white
                                              : AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      ref
                                          .read(serverOrderProvider.notifier)
                                          .setAllParcel(true);
                                    },
                                    borderRadius: const BorderRadius.horizontal(
                                        right: Radius.circular(8)),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: orderState.isEntireOrderParcel
                                            ? const Color(0xFFEA580C)
                                            : Colors.transparent,
                                        borderRadius:
                                            const BorderRadius.horizontal(
                                                right: Radius.circular(7)),
                                      ),
                                      child: Text(
                                        '📦 Parcel',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: orderState.isEntireOrderParcel
                                              ? Colors.white
                                              : AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Itemized List Header
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius:
                              BorderRadius.circular(AppColors.radiusSmall),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: Text(
                                'Item',
                                style: AppTextStyles.caption.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                'Qty',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.caption.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'Price',
                                textAlign: TextAlign.right,
                                style: AppTextStyles.caption.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'Total',
                                textAlign: TextAlign.right,
                                style: AppTextStyles.caption.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Itemized List
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: cartItems.length,
                        separatorBuilder: (_, _) => const Divider(
                            height: 1, color: AppColors.borderLight),
                        itemBuilder: (context, index) {
                          final item = cartItems[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 4,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  item.menuItem.name,
                                                  style: AppTextStyles.bodyMedium
                                                      .copyWith(
                                                    fontWeight: FontWeight.w600,
                                                    color:
                                                        AppColors.primaryDark,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              // Interactive 1-tap parcel toggle for this item
                                              InkWell(
                                                onTap: () {
                                                  HapticFeedback.selectionClick();
                                                  ref
                                                      .read(serverOrderProvider
                                                          .notifier)
                                                      .toggleItemParcel(
                                                          item.menuItem.id);
                                                },
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 5,
                                                          vertical: 1.5),
                                                  decoration: BoxDecoration(
                                                    color: item.isParcel
                                                        ? const Color(0xFFFFF7ED)
                                                        : AppColors.primaryLight,
                                                    borderRadius:
                                                        BorderRadius.circular(4),
                                                    border: Border.all(
                                                      color: item.isParcel
                                                          ? const Color(0xFFFED7AA)
                                                          : AppColors.primaryGreen
                                                              .withValues(
                                                                  alpha: 0.3),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        item.isParcel
                                                            ? '📦 PARCEL'
                                                            : '🍽️ DINE',
                                                        style: TextStyle(
                                                          fontSize: 9,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: item.isParcel
                                                              ? const Color(
                                                                  0xFFEA580C)
                                                              : AppColors
                                                                  .primaryDark,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 2),
                                                      Icon(
                                                        Icons.swap_horiz_rounded,
                                                        size: 10,
                                                        color: item.isParcel
                                                            ? const Color(
                                                                0xFFEA580C)
                                                            : AppColors
                                                                .primaryDark,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (item.selectedAddons.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              item.selectedAddons
                                                  .map((a) =>
                                                      '+${a.name} (+₹${a.price.toStringAsFixed(0)})')
                                                  .join(', '),
                                              style: AppTextStyles.caption
                                                  .copyWith(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.primaryGreen,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        '×${item.quantity}',
                                        textAlign: TextAlign.center,
                                        style:
                                            AppTextStyles.bodyMedium.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '${AppConstants.defaultCurrencySymbol}${item.effectiveUnitPrice.toStringAsFixed(0)}',
                                        textAlign: TextAlign.right,
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '${AppConstants.defaultCurrencySymbol}${item.itemTotal.toStringAsFixed(0)}',
                                        textAlign: TextAlign.right,
                                        style:
                                            AppTextStyles.bodyMedium.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.primaryGreen,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (item.specialInstructions != null &&
                                    item.specialInstructions!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '📝 ${item.specialInstructions}',
                                    style: AppTextStyles.caption.copyWith(
                                      fontStyle: FontStyle.italic,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),

                      // Quick Note Chips
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          'Less ice',
                          'Extra spicy',
                          'No sugar',
                          'Pack separately',
                        ].map((label) {
                          return ActionChip(
                            label: Text(label,
                                style: AppTextStyles.caption.copyWith(
                                    color: AppColors.textPrimary)),
                            onPressed: () => _appendNote(label),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: AppColors.woodMist,
                            side: BorderSide(
                                color: AppColors.woodBrown
                                    .withValues(alpha: 0.2)),
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),

                      // Kitchen Notes Input
                      TextFormField(
                        controller: _notesController,
                        maxLines: 2,
                        minLines: 1,
                        style: AppTextStyles.bodyMedium,
                        decoration: InputDecoration(
                          labelText: 'Kitchen / Table Notes',
                          hintText: 'e.g. Customer allergic to nuts',
                          hintStyle: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textHint),
                          isDense: true,
                          prefixIcon: const Icon(Icons.edit_note_rounded,
                              size: 20, color: AppColors.primaryGreen),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppColors.radiusMedium),
                            borderSide:
                                const BorderSide(color: AppColors.borderLight),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppColors.radiusMedium),
                            borderSide: const BorderSide(
                                color: AppColors.primaryGreen, width: 1.8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Total Section (Pinned at bottom)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.secondaryLight,
                  borderRadius:
                      BorderRadius.circular(AppColors.radiusMedium),
                  border: Border.all(
                    color: AppColors.secondaryGreen.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${orderState.totalItemsCount} items · ${orderState.parcelItemsCount == 0 ? "Dine-In" : orderState.parcelItemsCount == orderState.totalItemsCount ? "All Parcel" : "${orderState.totalItemsCount - orderState.parcelItemsCount} Dine, ${orderState.parcelItemsCount} Parcel"}',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (addonsTotal > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2, bottom: 2),
                            child: Text(
                              'Base: ₹${baseTotal.toStringAsFixed(0)}  +  Add-ons: ₹${addonsTotal.toStringAsFixed(0)}',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.primaryGreen,
                                fontWeight: FontWeight.w700,
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                        Text(
                          'Order Total',
                          style: AppTextStyles.labelLarge.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${AppConstants.defaultCurrencySymbol}${orderState.grandTotalAmount.toStringAsFixed(2)}',
                      style: AppTextStyles.h1.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.borderMedium),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Back',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: isSubmitting ? null : _handleConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                        elevation: 1,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                        ),
                      ),
                      child: isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              orderState.isEditingOrder
                                  ? 'Save & Update Order'
                                  : 'Confirm & Submit',
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
}
