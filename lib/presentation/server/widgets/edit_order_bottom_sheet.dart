import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/models.dart';
import '../../../state/server_order_provider.dart';

/// In-place Order Management Sheet allowing servers to manage, edit quantities,
/// toggle Parcel, and add flavours/add-ons for an existing order without leaving TableContextView.
class EditOrderBottomSheet extends ConsumerStatefulWidget {
  final SessionCustomer customer;
  final SessionOrderSummary order;

  const EditOrderBottomSheet({
    super.key,
    required this.customer,
    required this.order,
  });

  static Future<bool?> show({
    required BuildContext context,
    required SessionCustomer customer,
    required SessionOrderSummary order,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditOrderBottomSheet(
        customer: customer,
        order: order,
      ),
    );
  }

  @override
  ConsumerState<EditOrderBottomSheet> createState() =>
      _EditOrderBottomSheetState();
}

class _EditableLineItem {
  final String menuItemId;
  final String itemName;
  final String categoryName;
  final double baseUnitPrice;
  int quantity;
  bool isParcel;
  List<MenuAddon> selectedAddons;
  String? instructions;

  _EditableLineItem({
    required this.menuItemId,
    required this.itemName,
    required this.categoryName,
    required this.baseUnitPrice,
    required this.quantity,
    this.isParcel = false,
    this.selectedAddons = const [],
    this.instructions,
  });

  double get addonsPricePerUnit =>
      selectedAddons.fold(0.0, (sum, a) => sum + a.price);

  double get effectiveUnitPrice => baseUnitPrice + addonsPricePerUnit;

  double get itemTotal => effectiveUnitPrice * quantity;
}

class _EditOrderBottomSheetState extends ConsumerState<EditOrderBottomSheet> {
  bool _isLoading = true;
  String? _errorMessage;
  List<_EditableLineItem> _items = [];
  late TextEditingController _notesController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
    _loadOrder();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadOrder() async {
    try {
      final details = await ref
          .read(serverOrderProvider.notifier)
          .fetchOrderDetails(widget.order.id);

      if (details == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load order details from server.';
        });
        return;
      }

      final rawNotes = details['notes'] as String?;
      if (rawNotes != null && rawNotes.isNotEmpty) {
        _notesController.text = rawNotes;
      }

      final rawItems = details['items'] as List<dynamic>? ?? [];
      final orderState = ref.read(serverOrderProvider);
      final availableAddons = orderState.availableAddons;
      final menuItems = orderState.menuItems;
      final List<_EditableLineItem> loaded = [];

      for (final raw in rawItems) {
        final map = raw as Map<String, dynamic>;
        final menuItemId = map['menu_item_id'] as String;
        final itemName = map['item_name'] as String? ?? 'Item';
        final categoryName = map['category_name'] as String? ?? '';
        final unitPrice = (map['unit_price'] as num?)?.toDouble() ?? 0.0;
        final qty = (map['quantity'] as num?)?.toInt() ?? 1;
        final instructions = map['special_instructions'] as String?;

        bool isParcel = false;
        final List<MenuAddon> foundAddons = [];
        final List<String> cleanParts = [];

        if (instructions != null && instructions.isNotEmpty) {
          final parts = instructions.split('•').map((p) => p.trim()).toList();
          for (final part in parts) {
            if (part == '[PARCEL]') {
              isParcel = true;
            } else {
              bool isAddonPart = false;
              for (final addon in availableAddons) {
                if (part.contains(addon.name)) {
                  if (!foundAddons.any((a) => a.id == addon.id)) {
                    foundAddons.add(addon);
                  }
                  isAddonPart = true;
                }
              }
              if (!isAddonPart && part.isNotEmpty) {
                cleanParts.add(part);
              }
            }
          }
        }

        // Authoritative base price from active catalog with robust fallback
        final matchedItem = menuItems.where((m) => m.id == menuItemId).firstOrNull;
        final calculatedBase = unitPrice - foundAddons.fold(0.0, (sum, a) => sum + a.price);
        final basePrice = matchedItem != null && matchedItem.basePrice > 0
            ? matchedItem.basePrice
            : (calculatedBase > 0 ? calculatedBase : unitPrice);

        loaded.add(_EditableLineItem(
          menuItemId: menuItemId,
          itemName: matchedItem?.name ?? itemName,
          categoryName: categoryName,
          baseUnitPrice: basePrice,
          quantity: qty,
          isParcel: isParcel,
          selectedAddons: foundAddons,
          instructions: cleanParts.isNotEmpty ? cleanParts.join(' • ') : null,
        ));
      }

      setState(() {
        _items = loaded;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading order: $e';
      });
    }
  }

  double get _subtotal =>
      _items.fold(0.0, (sum, item) => sum + item.itemTotal);

  Future<void> _handleSave() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Order must contain at least one item. To cancel the order, use the Cancel button on the card.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      final cartItems = _items.map((item) {
        return CartItem(
          menuItem: MenuItem(
            id: item.menuItemId,
            categoryId: '',
            name: item.itemName,
            basePrice: item.baseUnitPrice,
            isAvailable: true,
            isActive: true,
            displayOrder: 0,
          ),
          quantity: item.quantity,
          selectedAddons: item.selectedAddons,
          isParcel: item.isParcel,
          specialInstructions: item.instructions,
        );
      }).toList();

      final success = await ref
          .read(serverOrderProvider.notifier)
          .updateExistingOrder(
            widget.order.id,
            items: cartItems,
            notes: _notesController.text.trim().isNotEmpty
                ? _notesController.text.trim()
                : null,
          );

      if (success && mounted) {
        Navigator.of(context).pop(true);
      } else if (mounted) {
        final err = ref.read(serverOrderProvider).errorMessage ??
            'Failed to save updates';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() => _isSaving = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating order: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final availableAddons = ref.watch(serverOrderProvider).availableAddons;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 16,
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  color: AppColors.primaryGreen,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Manage Order #${widget.order.orderNumber}',
                      style: AppTextStyles.h2.copyWith(
                        color: AppColors.primaryDark,
                      ),
                    ),
                    Text(
                      'Customer: ${widget.customer.displayName}',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(false),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const Divider(height: 24, color: AppColors.borderLight),

          // Body
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.primaryGreen,
                ),
              ),
            )
          else if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  _errorMessage!,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Items in this order',
                      style: AppTextStyles.labelMedium.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Items list
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = _items[index];

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: item.isParcel
                                  ? const Color(0xFFFED7AA)
                                  : AppColors.borderLight,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Line 1: Name, price, delete
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.itemName,
                                          style:
                                              AppTextStyles.bodyMedium.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.primaryDark,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              '${AppConstants.defaultCurrencySymbol}${item.itemTotal.toStringAsFixed(0)}',
                                              style: AppTextStyles.bodyMedium.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.primaryGreen,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '(${AppConstants.defaultCurrencySymbol}${item.effectiveUnitPrice.toStringAsFixed(0)} ea)',
                                              style: AppTextStyles.caption.copyWith(
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 3,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            if (item.selectedAddons.isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 5, vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: AppColors.primaryLight,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: AppColors.primaryGreen
                                                        .withValues(alpha: 0.35),
                                                  ),
                                                ),
                                                child: Text(
                                                  '+${item.selectedAddons.map((a) => a.name).join(", ")} (+₹${item.addonsPricePerUnit.toStringAsFixed(0)})',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppColors.primaryDark,
                                                  ),
                                                ),
                                              ),
                                            InkWell(
                                              onTap: () =>
                                                  _openItemAddonPicker(
                                                      context,
                                                      item,
                                                      availableAddons),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF1F5F9),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                      color: Colors.grey.shade300),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      item.selectedAddons.isNotEmpty
                                                          ? Icons.edit_outlined
                                                          : Icons.add_rounded,
                                                      size: 11,
                                                      color: AppColors.primaryGreen,
                                                    ),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      item.selectedAddons.isNotEmpty
                                                          ? 'Edit Add-ons'
                                                          : '+ Add-on',
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w700,
                                                        color: AppColors.primaryGreen,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Stepper
                                  Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.cardSurface,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: AppColors.borderLight),
                                    ),
                                    child: Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.remove_rounded,
                                              size: 16),
                                          onPressed: item.quantity > 1
                                              ? () {
                                                  HapticFeedback.lightImpact();
                                                  setState(
                                                      () => item.quantity--);
                                                }
                                              : null,
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.all(4),
                                          constraints: const BoxConstraints(),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10),
                                          child: Text(
                                            '${item.quantity}',
                                            style: AppTextStyles.labelMedium
                                                .copyWith(
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.primaryDark,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.add_rounded,
                                              size: 16),
                                          onPressed: () {
                                            HapticFeedback.lightImpact();
                                            setState(() => item.quantity++);
                                          },
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.all(4),
                                          constraints: const BoxConstraints(),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Delete button
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded,
                                        color: AppColors.error, size: 20),
                                    tooltip: 'Remove Item',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () {
                                      HapticFeedback.mediumImpact();
                                      setState(() {
                                        _items.removeAt(index);
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Line 2: Parcel Toggle Chip
                              Row(
                                children: [
                                  FilterChip(
                                    selected: item.isParcel,
                                    onSelected: (val) {
                                      HapticFeedback.selectionClick();
                                      setState(() => item.isParcel = val);
                                    },
                                    avatar: Icon(
                                      Icons.inventory_2_rounded,
                                      size: 14,
                                      color: item.isParcel
                                          ? Colors.white
                                          : const Color(0xFFEA580C),
                                    ),
                                    label: Text(
                                      item.isParcel
                                          ? '📦 PARCEL (To-Go)'
                                          : '🍽️ Dine-In',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: item.isParcel
                                            ? Colors.white
                                            : AppColors.primaryDark,
                                      ),
                                    ),
                                    selectedColor: const Color(0xFFEA580C),
                                    backgroundColor: const Color(0xFFFFF7ED),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 2),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      side: BorderSide(
                                        color: item.isParcel
                                            ? const Color(0xFFEA580C)
                                            : const Color(0xFFFED7AA),
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${AppConstants.defaultCurrencySymbol}${item.itemTotal.toStringAsFixed(0)}',
                                    style: AppTextStyles.labelMedium.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),
                    Text(
                      'Order Notes',
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _notesController,
                      decoration: InputDecoration(
                        hintText: 'e.g. Parcel first, serve juice cold...',
                        hintStyle: AppTextStyles.caption.copyWith(
                          color:
                              AppColors.textSecondary.withValues(alpha: 0.6),
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: AppColors.borderLight),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 12),

          // Total & Save Button
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Updated Total',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '${AppConstants.defaultCurrencySymbol}${_subtotal.toStringAsFixed(0)}',
                    style: AppTextStyles.moneyLarge.copyWith(
                      color: AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _handleSave,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: Text(_isSaving ? 'Updating...' : 'Update Order'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

  void _openItemAddonPicker(
    BuildContext context,
    _EditableLineItem lineItem,
    List<MenuAddon> allAddons,
  ) {
    HapticFeedback.lightImpact();
    final productAddons = allAddons
        .where((a) => a.menuItemId == lineItem.menuItemId)
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Add-ons for ${lineItem.itemName}',
                          style: AppTextStyles.h3.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (productAddons.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.borderLight),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 18,
                                    color: AppColors.textSecondary
                                        .withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'No add-ons available for this product',
                                      style: AppTextStyles.caption.copyWith(
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: productAddons.map((addon) {
                                final isSelected = lineItem.selectedAddons
                                    .any((a) => a.id == addon.id);

                                return FilterChip(
                                  selected: isSelected,
                                  onSelected: (val) {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      if (val) {
                                        lineItem.selectedAddons = [
                                          ...lineItem.selectedAddons,
                                          addon
                                        ];
                                      } else {
                                        lineItem.selectedAddons = lineItem
                                            .selectedAddons
                                            .where((a) => a.id != addon.id)
                                            .toList();
                                      }
                                    });
                                    setModalState(() {});
                                  },
                                  label: Text(
                                    '+${addon.name} (+₹${addon.price.toStringAsFixed(0)})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: isSelected
                                          ? Colors.white
                                          : AppColors.primaryDark,
                                    ),
                                  ),
                                  selectedColor: AppColors.primaryGreen,
                                  backgroundColor: AppColors.primaryLight,
                                  checkmarkColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                      color: isSelected
                                          ? AppColors.primaryGreen
                                          : AppColors.primaryGreen
                                              .withValues(alpha: 0.3),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
