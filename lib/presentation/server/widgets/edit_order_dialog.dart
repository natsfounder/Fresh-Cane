import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/models.dart';
import '../../../state/server_order_provider.dart';

/// Dialog allowing server staff to manage items inside an existing order.
/// Strictly updates the existing order in-place without creating a new order.
class EditOrderDialog extends ConsumerStatefulWidget {
  final SessionOrderSummary order;
  final String customerName;

  const EditOrderDialog({
    super.key,
    required this.order,
    required this.customerName,
  });

  static Future<bool?> show({
    required BuildContext context,
    required SessionOrderSummary order,
    required String customerName,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EditOrderDialog(
        order: order,
        customerName: customerName,
      ),
    );
  }

  @override
  ConsumerState<EditOrderDialog> createState() => _EditOrderDialogState();
}

class _EditOrderDialogState extends ConsumerState<EditOrderDialog> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  // Local state map of menuItemId -> CartItem
  final Map<String, CartItem> _editedItems = {};
  late TextEditingController _notesController;
  MenuItem? _selectedItemToAdd;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
    _loadOrderDetails();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadOrderDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final notifier = ref.read(serverOrderProvider.notifier);
    final details = await notifier.fetchOrderDetails(widget.order.id);

    if (!mounted) return;

    if (details == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load order details from server.';
      });
      return;
    }

    final serverState = ref.read(serverOrderProvider);
    final catalogMap = {for (var m in serverState.menuItems) m.id: m};

    final rawNotes = details['notes'] as String?;
    _notesController.text = rawNotes ?? '';

    final rawItems = details['items'] as List<dynamic>? ?? [];
    for (final raw in rawItems) {
      final map = raw as Map<String, dynamic>;
      final menuItemId = map['menu_item_id'] as String;
      final qty = (map['quantity'] as num?)?.toInt() ?? 1;
      final instructions = map['special_instructions'] as String?;
      final unitPrice = (map['unit_price'] as num?)?.toDouble() ?? 0.0;
      final itemName = map['item_name'] as String? ?? 'Item';

      MenuItem item;
      if (catalogMap.containsKey(menuItemId)) {
        item = catalogMap[menuItemId]!;
      } else {
        item = MenuItem(
          id: menuItemId,
          categoryId: '',
          name: itemName,
          basePrice: unitPrice,
          isAvailable: true,
          isActive: true,
          displayOrder: 0,
        );
      }

      _editedItems[menuItemId] = CartItem(
        menuItem: item,
        quantity: qty,
        specialInstructions: instructions,
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  double get _totalAmount {
    double total = 0.0;
    for (final item in _editedItems.values) {
      total += item.itemTotal;
    }
    return total;
  }

  int get _totalItemsCount {
    int count = 0;
    for (final item in _editedItems.values) {
      count += item.quantity;
    }
    return count;
  }

  void _setItemQuantity(MenuItem item, int newQty) {
    setState(() {
      if (newQty <= 0) {
        _editedItems.remove(item.id);
      } else {
        final existing = _editedItems[item.id];
        _editedItems[item.id] = CartItem(
          menuItem: item,
          quantity: newQty,
          specialInstructions: existing?.specialInstructions,
        );
      }
    });
  }

  void _addItemFromMenu(MenuItem item) {
    HapticFeedback.selectionClick();
    setState(() {
      final currentQty = _editedItems[item.id]?.quantity ?? 0;
      _editedItems[item.id] = CartItem(
        menuItem: item,
        quantity: currentQty + 1,
        specialInstructions: _editedItems[item.id]?.specialInstructions,
      );
      _selectedItemToAdd = null;
    });
  }

  Future<void> _saveChanges() async {
    if (_editedItems.isEmpty) {
      setState(() {
        _errorMessage = 'Order must contain at least one item. To cancel an order, use Cancel Order.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final notifier = ref.read(serverOrderProvider.notifier);
    final success = await notifier.updateExistingOrder(
      widget.order.id,
      items: _editedItems.values.toList(),
      notes: _notesController.text,
    );

    if (!mounted) return;

    if (success) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSaving = false;
        _errorMessage = 'Failed to update order. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverState = ref.watch(serverOrderProvider);
    final availableMenuItems = serverState.menuItems
        .where((m) => m.isActive && m.isAvailable)
        .toList();

    return Dialog(
      backgroundColor: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusLarge),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width > 620 ? 580 : MediaQuery.of(context).size.width * 0.92,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primaryGreen.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.edit_note_rounded,
                      color: AppColors.primaryDark,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Manage Order ${widget.order.orderNumber}',
                          style: AppTextStyles.h2.copyWith(
                            color: AppColors.primaryDark,
                          ),
                        ),
                        Text(
                          'Customer: ${widget.customerName}  •  Editing Existing Order',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.secondaryGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: AppColors.borderLight),
              const SizedBox(height: 12),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.errorLight,
                    borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
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

              // Body Content
              if (_isLoading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primaryGreen),
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ORDER ITEMS', style: AppTextStyles.overline),
                        const SizedBox(height: 8),

                        if (_editedItems.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                              border: Border.all(color: AppColors.borderLight),
                            ),
                            child: Center(
                              child: Text(
                                'No items in this order. Add items below or cancel order.',
                                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                              ),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _editedItems.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = _editedItems.values.elementAt(index);
                              final menuItem = item.menuItem;

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                                  border: Border.all(color: AppColors.borderLight),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            menuItem.name,
                                            style: AppTextStyles.h4.copyWith(
                                              color: AppColors.primaryDark,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${AppConstants.defaultCurrencySymbol}${menuItem.basePrice.toStringAsFixed(0)} each',
                                            style: AppTextStyles.caption.copyWith(
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Quantity Controls
                                    Row(
                                      children: [
                                        IconButton(
                                          onPressed: () => _setItemQuantity(menuItem, item.quantity - 1),
                                          icon: const Icon(Icons.remove_circle_outline_rounded),
                                          color: item.quantity == 1 ? AppColors.error : AppColors.primaryDark,
                                          iconSize: 22,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        Text(
                                          '${item.quantity}',
                                          style: AppTextStyles.h4.copyWith(
                                            color: AppColors.primaryDark,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () => _setItemQuantity(menuItem, item.quantity + 1),
                                          icon: const Icon(Icons.add_circle_outline_rounded),
                                          color: AppColors.primaryGreen,
                                          iconSize: 22,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ],
                                    ),

                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 64,
                                      child: Text(
                                        '${AppConstants.defaultCurrencySymbol}${item.itemTotal.toStringAsFixed(0)}',
                                        textAlign: TextAlign.right,
                                        style: AppTextStyles.moneySmall.copyWith(
                                          color: AppColors.primaryDark,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                        const SizedBox(height: 16),

                        // Add Item to existing order dropdown
                        Text('ADD ITEM TO THIS ORDER', style: AppTextStyles.overline),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<MenuItem>(
                          key: ValueKey(_selectedItemToAdd),
                          initialValue: _selectedItemToAdd,
                          hint: Text(
                            'Select menu item to add...',
                            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
                          ),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                              borderSide: const BorderSide(color: AppColors.borderLight),
                            ),
                          ),
                          items: availableMenuItems.map((item) {
                            return DropdownMenuItem<MenuItem>(
                              value: item,
                              child: Text(
                                '${item.name} (${AppConstants.defaultCurrencySymbol}${item.basePrice.toStringAsFixed(0)})',
                                style: AppTextStyles.bodyMedium,
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              _addItemFromMenu(val);
                            }
                          },
                        ),

                        const SizedBox(height: 16),

                        // Order Notes
                        TextField(
                          controller: _notesController,
                          style: AppTextStyles.bodyMedium,
                          decoration: InputDecoration(
                            labelText: 'Order Special Instructions / Notes',
                            hintText: 'e.g. Less spicy, Extra ice...',
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
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 12),
              const Divider(height: 1, color: AppColors.borderLight),
              const SizedBox(height: 14),

              // Total Summary Row & Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total ($_totalItemsCount ${_totalItemsCount == 1 ? 'item' : 'items'})',
                        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                      ),
                      Text(
                        '${AppConstants.defaultCurrencySymbol}${_totalAmount.toStringAsFixed(0)}',
                        style: AppTextStyles.h2.copyWith(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),

                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.borderMedium),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        child: Text(
                          'Cancel',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: (_isSaving || _isLoading) ? null : _saveChanges,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          foregroundColor: AppColors.primaryDark,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primaryDark,
                                ),
                              )
                            : Text(
                                'Save Order',
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ],
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
