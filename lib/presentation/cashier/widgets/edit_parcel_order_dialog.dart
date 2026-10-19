import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/supabase_service.dart';
import '../../../state/cashier_provider.dart';

/// Representation of an item within the parcel order editor.
class EditParcelOrderItem {
  final String id;
  String? menuItemId;
  String name;
  double unitPrice;
  int quantity;
  bool isReplaced;
  bool isNew;

  EditParcelOrderItem({
    required this.id,
    this.menuItemId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    this.isReplaced = false,
    this.isNew = false,
  });

  double get total => unitPrice * quantity;
}

/// Dialog allowing Cashiers to edit pending parcel orders while in the Waiting queue.
/// Supports increasing/decreasing quantities, replacing items, removing items,
/// and adding new items from the catalog.
class EditParcelOrderDialog extends ConsumerStatefulWidget {
  final String billId;
  final String billNumber;
  final String orderNumber;
  final String customerName;
  final List<EditParcelOrderItem> initialItems;

  const EditParcelOrderDialog({
    super.key,
    required this.billId,
    required this.billNumber,
    required this.orderNumber,
    required this.customerName,
    required this.initialItems,
  });

  static Future<bool?> show({
    required BuildContext context,
    required String billId,
    required String billNumber,
    required String orderNumber,
    required String customerName,
    required List<EditParcelOrderItem> initialItems,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EditParcelOrderDialog(
        billId: billId,
        billNumber: billNumber,
        orderNumber: orderNumber,
        customerName: customerName,
        initialItems: initialItems,
      ),
    );
  }

  @override
  ConsumerState<EditParcelOrderDialog> createState() => _EditParcelOrderDialogState();
}

class _EditParcelOrderDialogState extends ConsumerState<EditParcelOrderDialog> {
  late List<EditParcelOrderItem> _items;
  bool _isSaving = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _catalogItems = [];

  @override
  void initState() {
    super.initState();
    _items = widget.initialItems
        .map((i) => EditParcelOrderItem(
              id: i.id,
              menuItemId: i.menuItemId,
              name: i.name,
              unitPrice: i.unitPrice,
              quantity: i.quantity,
              isReplaced: i.isReplaced,
              isNew: i.isNew,
            ))
        .toList();
    _fetchCatalogItems();
  }

  Future<void> _fetchCatalogItems() async {
    try {
      final res = await SupabaseService.client
          .from('menu_items')
          .select('id, name, base_price, is_available')
          .eq('is_available', true)
          .eq('is_active', true)
          .order('name');
      if (mounted) {
        setState(() {
          _catalogItems = List<Map<String, dynamic>>.from(res as List);
        });
      }
    } catch (e) {
      debugPrint('Error loading catalog in EditParcelOrderDialog: $e');
    }
  }

  double get _calculatedTotal =>
      _items.fold(0.0, (sum, i) => sum + i.total);

  int get _activeItemsCount =>
      _items.where((i) => i.quantity > 0).length;

  void _showReplaceSheet(EditParcelOrderItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CatalogPickerSheet(
        title: 'Replace "${item.name}"',
        catalogItems: _catalogItems,
        onSelected: (selected) {
          setState(() {
            item.menuItemId = selected['id'] as String;
            item.name = selected['name'] as String;
            item.unitPrice = (selected['base_price'] as num).toDouble();
            item.isReplaced = true;
          });
        },
      ),
    );
  }

  void _showAddItemSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CatalogPickerSheet(
        title: 'Add Item to Parcel Order',
        catalogItems: _catalogItems,
        onSelected: (selected) {
          final id = selected['id'] as String;
          // Check if already in active list
          final existing = _items.firstWhere(
            (i) => i.menuItemId == id && i.quantity > 0,
            orElse: () => EditParcelOrderItem(id: '', name: '', unitPrice: 0, quantity: -1),
          );

          if (existing.quantity > 0) {
            setState(() {
              existing.quantity++;
            });
          } else {
            setState(() {
              _items.add(EditParcelOrderItem(
                id: '',
                menuItemId: id,
                name: selected['name'] as String,
                unitPrice: (selected['base_price'] as num).toDouble(),
                quantity: 1,
                isNew: true,
              ));
            });
          }
        },
      ),
    );
  }

  Future<void> _handleSave() async {
    HapticFeedback.lightImpact();
    if (_activeItemsCount == 0) {
      setState(() {
        _errorMessage = 'Order must contain at least 1 item.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final payload = _items
          .map((i) => {
                'order_item_id': (i.id.isNotEmpty && !i.isNew) ? i.id : null,
                'menu_item_id': i.menuItemId,
                'item_name': i.name,
                'quantity': i.quantity,
                'unit_price': i.unitPrice,
              })
          .toList();

      final billingRepo = ref.read(billingRepositoryProvider);
      final res = await billingRepo.editParcelBill(
        billId: widget.billId,
        items: payload,
      );

      if (!mounted) return;

      final success = res['success'] == true;
      if (success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isSaving = false;
          _errorMessage = res['message']?.toString() ?? 'Failed to update parcel order';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Error saving changes: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.82;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFF8F9FA),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Icon(Icons.edit_note_rounded, color: Color(0xFF1D4ED8), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Parcel #${widget.orderNumber}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary),
                        ),
                        Text(
                          '${widget.customerName} • Bill #${widget.billNumber}',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),

            // Item list with steppers, replace and delete
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, idx) {
                  final item = _items[idx];
                  final isRemoved = item.quantity == 0;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isRemoved ? const Color(0xFFF9FAFB) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isRemoved ? Colors.grey.shade300 : const Color(0xFFE5E7EB),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: isRemoved ? Colors.grey.shade500 : AppColors.textPrimary,
                                        decoration: isRemoved ? TextDecoration.lineThrough : null,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  if (!isRemoved)
                                    InkWell(
                                      onTap: _isSaving ? null : () => _showReplaceSheet(item),
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: item.isReplaced ? const Color(0xFFE0F2FE) : const Color(0xFFF3F4F6),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: item.isReplaced ? const Color(0xFF38BDF8) : Colors.grey.shade300,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.swap_horiz_rounded,
                                              size: 12,
                                              color: item.isReplaced ? const Color(0xFF0284C7) : Colors.grey.shade700,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              item.isReplaced ? 'Replaced' : 'Replace',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: item.isReplaced ? const Color(0xFF0284C7) : Colors.grey.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '₹${item.unitPrice.toStringAsFixed(2)} each',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Stepper [-] [qty] [+]
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: _isSaving || item.quantity <= 0
                                    ? null
                                    : () {
                                        setState(() {
                                          item.quantity--;
                                        });
                                      },
                                borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    item.quantity == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
                                    size: 15,
                                    color: item.quantity <= 0
                                        ? Colors.grey.shade300
                                        : (item.quantity == 1 ? Colors.red : const Color(0xFF374151)),
                                  ),
                                ),
                              ),
                              Container(
                                width: 32,
                                alignment: Alignment.center,
                                child: Text(
                                  '${item.quantity}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                    color: isRemoved ? Colors.red : AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: _isSaving || item.quantity >= 99
                                    ? null
                                    : () {
                                        setState(() {
                                          item.quantity++;
                                        });
                                      },
                                borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.add_rounded,
                                    size: 15,
                                    color: item.quantity >= 99 ? Colors.grey.shade300 : const Color(0xFF374151),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Total for item
                        SizedBox(
                          width: 58,
                          child: Text(
                            '₹${item.total.toStringAsFixed(2)}',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                              color: isRemoved ? Colors.grey : AppColors.primaryDark,
                              decoration: isRemoved ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Button to Add another item
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: _isSaving ? null : _showAddItemSheet,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryGreen,
                  side: const BorderSide(color: AppColors.primaryGreen, width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Another Item', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
            const SizedBox(height: 10),

            // Live recalculation strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFF9FAFB),
                border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NEW TOTAL',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
                      ),
                      Text(
                        '$_activeItemsCount active items',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  Text(
                    '₹${_calculatedTotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.primaryDark),
                  ),
                ],
              ),
            ),

            // Action Buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Catalog picker bottom sheet to select replacement or new item.
class _CatalogPickerSheet extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> catalogItems;
  final ValueChanged<Map<String, dynamic>> onSelected;

  const _CatalogPickerSheet({
    required this.title,
    required this.catalogItems,
    required this.onSelected,
  });

  @override
  State<_CatalogPickerSheet> createState() => _CatalogPickerSheetState();
}

class _CatalogPickerSheetState extends State<_CatalogPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.catalogItems.where((i) {
      final name = (i['name'] as String? ?? '').toLowerCase();
      if (_filter.isNotEmpty && !name.contains(_filter)) return false;
      return true;
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.70,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.grey),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) => setState(() => _filter = val.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search menu item...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('No items found', style: TextStyle(color: Colors.grey)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final name = item['name'] as String;
                      final price = (item['base_price'] as num).toDouble();

                      return ListTile(
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        trailing: Text(
                          '₹${price.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreen, fontSize: 14),
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onSelected(item);
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
