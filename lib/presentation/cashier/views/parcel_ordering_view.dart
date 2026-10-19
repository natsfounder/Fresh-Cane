import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/responsive.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../../models/bill_model.dart';
import '../../../models/cart_item_model.dart';
import '../../../models/category_model.dart';
import '../../../models/menu_item_model.dart';
import '../../../models/payment_model.dart';
import '../../../services/supabase_service.dart';
import '../../../state/cashier_provider.dart';
import '../../server/widgets/item_customization_modal.dart';
import '../widgets/edit_parcel_order_dialog.dart';
import '../widgets/payment_dialog.dart';
import '../widgets/receipt_dialog.dart';
import '../../common/product_image_widget.dart';

/// Checkout action chosen in the Parcel Order review sheet.
enum ParcelCheckoutAction {
  payLater,
  payNow,
}

/// Representation of an unpaid parcel order awaiting settlement at pickup.
class _PendingParcelBill {
  final String billId;
  final String billNumber;
  final String orderId;
  final String orderNumber;
  final String customerName;
  final String customerPhone;
  final double finalAmount;
  final DateTime createdAt;
  final List<_PendingBillItem> items;
  final Bill billModel;

  const _PendingParcelBill({
    required this.billId,
    required this.billNumber,
    required this.orderId,
    required this.orderNumber,
    required this.customerName,
    required this.customerPhone,
    required this.finalAmount,
    required this.createdAt,
    required this.items,
    required this.billModel,
  });
}

class _PendingBillItem {
  final String id;
  final String? menuItemId;
  final String name;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final String? notes;

  const _PendingBillItem({
    required this.id,
    this.menuItemId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.notes,
  });
}

/// Cashier Parcel / Takeaway Ordering View.
///
/// Features:
/// - Top Tab Bar: [ 📝 Take Order ] vs [ ⏳ Waiting for Settlement (count) ]
/// - Fast Parcel Ordering: Category selector, menu item grid, customization, live cart.
/// - Flexible Payment Flow: Pay Now (immediate settlement) or Pay Later (customer waits for juice, settles upon delivery).
/// - Waiting Queue: Settle pending takeaway orders upon pickup or cancel unpaid orders.
class ParcelOrderingView extends ConsumerStatefulWidget {
  const ParcelOrderingView({super.key});

  @override
  ConsumerState<ParcelOrderingView> createState() => _ParcelOrderingViewState();
}

class _ParcelOrderingViewState extends ConsumerState<ParcelOrderingView> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customerNameController = TextEditingController(text: 'Parcel Customer');
  final TextEditingController _customerPhoneController = TextEditingController();
  final GlobalKey<FormState> _customerFormKey = GlobalKey<FormState>();

  String? _selectedCategoryId;
  String _searchQuery = '';

  /// Active cart items for this parcel order (keyed by menuItem.id)
  final Map<String, CartItem> _cart = {};

  /// 0 = Take Order, 1 = Waiting for Settlement
  int _selectedTab = 0;

  /// Pending unpaid takeaway bills
  bool _isLoadingPending = false;
  String? _pendingError;
  List<_PendingParcelBill> _pendingBills = [];

  @override
  void initState() {
    super.initState();
    _loadPendingBills();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    super.dispose();
  }

  int get _totalItemsCount => _cart.values.fold(0, (sum, i) => sum + i.quantity);

  double get _grandTotalAmount =>
      _cart.values.fold(0.0, (sum, i) => sum + i.itemTotal);

  void _addItem(MenuItem item) {
    HapticFeedback.lightImpact();
    setState(() {
      final existing = _cart[item.id];
      if (existing != null) {
        _cart[item.id] = existing.copyWith(quantity: existing.quantity + 1);
      } else {
        _cart[item.id] = CartItem(
          menuItem: item,
          quantity: 1,
          isParcel: true,
        );
      }
    });
  }

  void _decrementItem(String menuItemId) {
    HapticFeedback.lightImpact();
    setState(() {
      final existing = _cart[menuItemId];
      if (existing == null) return;
      if (existing.quantity <= 1) {
        _cart.remove(menuItemId);
      } else {
        _cart[menuItemId] = existing.copyWith(quantity: existing.quantity - 1);
      }
    });
  }

  void _setConfiguredItem(CartItem configuredItem) {
    setState(() {
      if (configuredItem.quantity <= 0) {
        _cart.remove(configuredItem.menuItem.id);
      } else {
        _cart[configuredItem.menuItem.id] = configuredItem.copyWith(isParcel: true);
      }
    });
  }

  void _openCustomizationModal(MenuItem item) {
    HapticFeedback.lightImpact();
    final cartItem = _cart[item.id];
    final cashierState = ref.read(cashierProvider);
    ItemCustomizationModal.show(
      context: context,
      item: item,
      initialCartItem: cartItem,
      availableAddons: cashierState.availableAddons,
      onSave: (configuredItem) => _setConfiguredItem(configuredItem),
    );
  }

  Future<void> _loadPendingBills() async {
    if (!mounted) return;
    setState(() {
      _isLoadingPending = true;
      _pendingError = null;
    });

    try {
      final client = SupabaseService.client;
      // Fetch unpaid bills joined with takeaway orders
      final data = await client
          .from('bills')
          .select(
            '*, '
            'orders(id, order_type, order_number, customer_name, customer_phone, notes, '
            'order_items(id, menu_item_id, item_name_snapshot, quantity, unit_price_snapshot, item_total, special_instructions, status))'
          )
          .eq('status', 'unpaid')
          .order('created_at', ascending: false);

      final List<_PendingParcelBill> loaded = [];

      for (final row in (data as List<dynamic>)) {
        final map = Map<String, dynamic>.from(row as Map);
        final order = map['orders'] as Map<String, dynamic>?;
        final rawOrderType = (order?['order_type'] as String?)?.toLowerCase() ?? '';
        if (rawOrderType != 'takeaway' && rawOrderType != 'parcel') {
          continue;
        }

        final billModel = Bill.fromJson(map);
        final rawItems = (order?['order_items'] as List<dynamic>?) ?? [];
        final List<_PendingBillItem> items = [];

        for (final it in rawItems) {
          final itMap = Map<String, dynamic>.from(it as Map);
          final itemStatus = (itMap['status'] as String?)?.toLowerCase();
          if (itemStatus == 'cancelled') continue;

          final qty = (itMap['quantity'] as num?)?.toInt() ?? 1;
          final unitP = (itMap['unit_price_snapshot'] as num?)?.toDouble() ?? 0.0;
          final totalP = (itMap['item_total'] as num?)?.toDouble() ?? (unitP * qty);
          final instructions = itMap['special_instructions'] as String?;

          items.add(_PendingBillItem(
            id: itMap['id'] as String? ?? '',
            menuItemId: itMap['menu_item_id'] as String?,
            name: itMap['item_name_snapshot'] as String? ?? 'Item',
            quantity: qty,
            unitPrice: unitP,
            totalPrice: totalP,
            notes: instructions,
          ));
        }

        loaded.add(_PendingParcelBill(
          billId: billModel.id,
          billNumber: billModel.billNumber,
          orderId: order?['id'] as String? ?? billModel.orderId,
          orderNumber: order?['order_number'] as String? ?? 'ORD-0000',
          customerName: billModel.customerNameSnapshot ?? order?['customer_name'] as String? ?? 'Parcel Customer',
          customerPhone: billModel.customerPhoneSnapshot ?? order?['customer_phone'] as String? ?? '',
          finalAmount: billModel.finalAmount,
          createdAt: billModel.createdAt,
          items: items,
          billModel: billModel,
        ));
      }

      if (mounted) {
        setState(() {
          _pendingBills = loaded;
          _isLoadingPending = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading pending parcel bills: $e');
      if (mounted) {
        setState(() {
          _pendingError = e.toString();
          _isLoadingPending = false;
        });
      }
    }
  }

  Future<void> _handleReviewAndSettle() async {
    HapticFeedback.lightImpact();
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one item to the parcel cart.')),
      );
      return;
    }

    final action = await showModalBottomSheet<ParcelCheckoutAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (bCtx) => _buildReviewBottomSheet(bCtx),
    );

    if (action != null && mounted) {
      await _processParcelOrder(action);
    }
  }

  Future<void> _processParcelOrder(ParcelCheckoutAction action) async {
    final billingRepo = ref.read(billingRepositoryProvider);
    final cashierNotifier = ref.read(cashierProvider.notifier);

    final customerName = _customerNameController.text.trim();
    final customerPhone = _customerPhoneController.text.trim();

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryGreen),
        ),
      );

      final items = _cart.values.toList();
      final orderResult = await billingRepo.submitParcelOrder(
        customerName: customerName.isNotEmpty ? customerName : 'Parcel Customer',
        customerPhone: customerPhone,
        items: items,
      );

      final orderId = orderResult['order_id'] as String;
      final bill = await billingRepo.generateBillForOrder(orderId);

      if (mounted) Navigator.pop(context); // Dismiss loading dialog

      if (action == ParcelCheckoutAction.payLater) {
        // Customer 1 opts to pay later when parcel arrives:
        // Clear cart immediately so cashier is ready for Customer 2 on spot!
        setState(() {
          _cart.clear();
          _customerPhoneController.clear();
          _customerNameController.text = 'Parcel Customer';
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF15803D),
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Parcel order placed (${orderResult['order_number'] ?? 'Token'}). Waiting for settlement.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }

        // Refresh pending list
        await _loadPendingBills();
        return;
      }

      // If action is payNow:
      if (mounted) {
        final payments = await PaymentDialog.show(
          context: context,
          bill: bill,
        );

        if (payments != null && payments.isNotEmpty && mounted) {
          final success = await cashierNotifier.settleBill(bill.id, payments);
          if (success && mounted) {
            final firstPmt = payments.first;
            final paymentObj = Payment(
              id: 'pmt_${DateTime.now().millisecondsSinceEpoch}',
              billId: bill.id,
              paymentMethod: firstPmt['method'] as String? ?? 'cash',
              amount: bill.finalAmount,
              cashTendered: (firstPmt['cash_tendered'] as num?)?.toDouble(),
              changeReturned: (firstPmt['cash_tendered'] as num?) != null
                  ? ((firstPmt['cash_tendered'] as num).toDouble() - bill.finalAmount)
                  : null,
              transactionReference: firstPmt['transaction_reference'] as String?,
              receivedBy: 'cashier',
              status: 'completed',
              createdAt: DateTime.now(),
            );

            ReceiptDialog.show(
              context,
              bill: bill,
              payment: paymentObj,
              onFinish: () {
                setState(() {
                  _cart.clear();
                  _customerPhoneController.clear();
                  _customerNameController.text = 'Parcel Customer';
                });
                _loadPendingBills();
              },
            );
          }
        } else {
          // If cashier/customer closed or cancelled payment dialog:
          // The order is NOT lost! It stays unpaid in the "Waiting for Settlement" queue.
          // Clear cart so cashier can serve Customer 2!
          if (mounted) {
            setState(() {
              _cart.clear();
              _customerPhoneController.clear();
              _customerNameController.text = 'Parcel Customer';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFFEA580C),
                content: Text(
                  'Payment postponed. Order #${orderResult['order_number'] ?? ''} saved in Waiting for Settlement.',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                duration: const Duration(seconds: 4),
              ),
            );
            await _loadPendingBills();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // dismiss loading if open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleSettlePendingBill(_PendingParcelBill pendingBill) async {
    HapticFeedback.lightImpact();
    final cashierNotifier = ref.read(cashierProvider.notifier);

    try {
      final payments = await PaymentDialog.show(
        context: context,
        bill: pendingBill.billModel,
      );

      if (payments != null && payments.isNotEmpty && mounted) {
        final success = await cashierNotifier.settleBill(pendingBill.billId, payments);
        if (success && mounted) {
          final firstPmt = payments.first;
          final paymentObj = Payment(
            id: 'pmt_${DateTime.now().millisecondsSinceEpoch}',
            billId: pendingBill.billId,
            paymentMethod: firstPmt['method'] as String? ?? 'cash',
            amount: pendingBill.finalAmount,
            cashTendered: (firstPmt['cash_tendered'] as num?)?.toDouble(),
            changeReturned: (firstPmt['cash_tendered'] as num?) != null
                ? ((firstPmt['cash_tendered'] as num).toDouble() - pendingBill.finalAmount)
                : null,
            transactionReference: firstPmt['transaction_reference'] as String?,
            receivedBy: 'cashier',
            status: 'completed',
            createdAt: DateTime.now(),
          );

          ReceiptDialog.show(
            context,
            bill: pendingBill.billModel,
            payment: paymentObj,
            onFinish: () {
              _loadPendingBills();
            },
          );

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF15803D),
              content: Text(
                'Parcel Bill #${pendingBill.billNumber} settled successfully!',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          );

          await _loadPendingBills();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Settlement failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleCancelPendingOrder(_PendingParcelBill pendingBill) async {
    HapticFeedback.lightImpact();
    final reasonController = TextEditingController(text: 'Customer cancelled parcel before payment');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: AppColors.error, size: 22),
            SizedBox(width: 8),
            Text('Cancel Parcel Order', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to cancel Order #${pendingBill.orderNumber} (Bill #${pendingBill.billNumber})?',
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Total: ₹${pendingBill.finalAmount.toStringAsFixed(2)} • Customer: ${pendingBill.customerName}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'Cancellation Reason',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Keep Order', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Yes, Cancel Order', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(
            child: CircularProgressIndicator(color: AppColors.primaryGreen),
          ),
        );

        final billingRepo = ref.read(billingRepositoryProvider);
        await billingRepo.cancelUnpaidParcelOrder(
          billId: pendingBill.billId,
          reason: reasonController.text.trim().isNotEmpty
              ? reasonController.text.trim()
              : 'Customer cancelled parcel before payment',
        );

        if (mounted) Navigator.pop(context); // dismiss loading dialog

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Order #${pendingBill.orderNumber} cancelled successfully.'),
              backgroundColor: AppColors.error,
            ),
          );
        }

        await _loadPendingBills();
      } catch (e) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop(); // dismiss loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cancellation failed: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleEditPendingOrder(_PendingParcelBill pendingBill) async {
    HapticFeedback.lightImpact();
    final editItems = pendingBill.items
        .map((i) => EditParcelOrderItem(
              id: i.id,
              menuItemId: i.menuItemId,
              name: i.name,
              unitPrice: i.unitPrice,
              quantity: i.quantity,
            ))
        .toList();

    final updated = await EditParcelOrderDialog.show(
      context: context,
      billId: pendingBill.billId,
      billNumber: pendingBill.billNumber,
      orderNumber: pendingBill.orderNumber,
      customerName: pendingBill.customerName,
      initialItems: editItems,
    );

    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF15803D),
          content: Text(
            'Parcel #${pendingBill.orderNumber} updated successfully!',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
      await _loadPendingBills();
    }
  }

  String _formatElapsed(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    final hrs = diff.inHours;
    final mins = diff.inMinutes % 60;
    return '${hrs}h ${mins}m ago';
  }

  Widget _buildReviewBottomSheet(BuildContext bCtx) {
    final screenH = MediaQuery.of(bCtx).size.height;
    final keyboardH = MediaQuery.of(bCtx).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(maxHeight: screenH * 0.90),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            top: 16,
            left: 20,
            right: 20,
            bottom: keyboardH + 24,
          ),
          child: Form(
            key: _customerFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.takeout_dining_rounded, color: AppColors.primaryGreen, size: 24),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Review Parcel Order',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primaryDark),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.grey),
                      onPressed: () => Navigator.pop(bCtx, false),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 14),

                // Customer Info inputs
                const Text('CUSTOMER DETAILS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _customerNameController,
                  decoration: InputDecoration(
                    labelText: 'Customer Name',
                    prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.primaryGreen),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _customerPhoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Mobile Number (10 Digits) *',
                    prefixIcon: const Icon(Icons.phone_outlined, color: AppColors.primaryGreen),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Please enter 10-digit mobile number';
                    if (v.trim().length != 10) return 'Must be exactly 10 digits';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Items list
                const Text('ORDER ITEMS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: _cart.values.map((item) {
                      final hasAddons = item.selectedAddons.isNotEmpty;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${item.quantity}x',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primaryDark),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.menuItem.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                                  ),
                                  if (hasAddons)
                                    Text(
                                      item.selectedAddons.map((a) => '+${a.name}').join(', '),
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              '₹${item.itemTotal.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primaryDark),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 14),

                // Total
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Amount:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    Text(
                      '₹${_grandTotalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Action Buttons: Pay Later (Settle on pickup) vs Pay Now (Immediate)
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFC2410C),
                            backgroundColor: const Color(0xFFFFF7ED),
                            side: const BorderSide(color: Color(0xFFEA580C), width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          ),
                          onPressed: () {
                            if (!_customerFormKey.currentState!.validate()) return;
                            Navigator.pop(bCtx, ParcelCheckoutAction.payLater);
                          },
                          icon: const Icon(Icons.hourglass_top_rounded, size: 18),
                          label: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pay Later',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFC2410C)),
                              ),
                              Text(
                                'Settle on pickup',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFEA580C)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGreen,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          ),
                          onPressed: () {
                            if (!_customerFormKey.currentState!.validate()) return;
                            Navigator.pop(bCtx, ParcelCheckoutAction.payNow);
                          },
                          icon: const Icon(Icons.flash_on_rounded, size: 18),
                          label: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pay Now',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                              ),
                              Text(
                                'Immediate payment',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.white70),
                              ),
                            ],
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cashierState = ref.watch(cashierProvider);
    final categories = cashierState.categories;
    final allMenuItems = cashierState.menuItems;

    if (_selectedCategoryId == null && categories.isNotEmpty) {
      _selectedCategoryId = categories.first.id;
    }

    final isSearching = _searchQuery.trim().isNotEmpty;
    final cleanQuery = _searchQuery.trim().toLowerCase();
    final filteredItems = allMenuItems.where((item) {
      if (!item.isActive || !item.isAvailable) return false;
      if (isSearching) {
        final matchesName = item.name.toLowerCase().contains(cleanQuery);
        final matchesDesc =
            item.description?.toLowerCase().contains(cleanQuery) ?? false;
        return matchesName || matchesDesc;
      }
      return _selectedCategoryId == null || item.categoryId == _selectedCategoryId;
    }).toList();

    return Column(
      children: [
        // ─── 0. Top Segmented Tab Switcher (Take Order vs Waiting for Settlement) ───
        _buildTopTabBar(context),

        // ─── 1. Content View ──────────────────────────────────────────
        Expanded(
          child: _selectedTab == 0
              ? _buildTakeOrderView(context, categories, filteredItems)
              : _buildWaitingForSettlementView(),
        ),
      ],
    );
  }

  // ─── Top Segmented Tab Switcher ────────────────────────────────────────────

  Widget _buildTopTabBar(BuildContext context) {
    final isCompact = Responsive.isCompact(context);
    final waitingTitle = isCompact ? 'Waiting' : 'Waiting for Settlement';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderLight, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSegmentButton(
              title: 'Take Order',
              icon: Icons.edit_note_rounded,
              isSelected: _selectedTab == 0,
              onTap: () {
                if (_selectedTab != 0) {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedTab = 0);
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildSegmentButton(
              title: waitingTitle,
              icon: Icons.hourglass_top_rounded,
              badgeCount: _pendingBills.length,
              isSelected: _selectedTab == 1,
              onTap: () {
                if (_selectedTab != 1) {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedTab = 1);
                  _loadPendingBills();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return Material(
      color: isSelected ? AppColors.primaryGreen : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              if (badgeCount > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white : const Color(0xFFEA580C),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: TextStyle(
                      color: isSelected ? AppColors.primaryGreen : Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── Take Order View (Search + Categories + Menu Grid + Cart) ───────────────

  Widget _buildTakeOrderView(
    BuildContext context,
    List<Category> categories,
    List<MenuItem> filteredItems,
  ) {
    return Column(
      children: [
        // ─── Header with Search Bar + Cart Pill ─────────────────────────
        Container(
          height: Responsive.headerHeight(context),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: const BoxDecoration(
            color: AppColors.cardSurface,
            border: Border(bottom: BorderSide(color: AppColors.borderLight, width: 1)),
            boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Row(
            children: [
              // Search bar
              Expanded(
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    decoration: InputDecoration(
                      hintText: 'Search items...',
                      hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.grey),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Live Cart Item Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _totalItemsCount > 0 ? AppColors.primaryLight : AppColors.warmSurface,
                  borderRadius: BorderRadius.circular(AppColors.radiusRound),
                  border: Border.all(
                    color: _totalItemsCount > 0
                        ? AppColors.primaryGreen.withValues(alpha: 0.3)
                        : AppColors.borderLight,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shopping_bag_outlined,
                      size: 14,
                      color: _totalItemsCount > 0 ? AppColors.primaryDark : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$_totalItemsCount items',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _totalItemsCount > 0 ? AppColors.primaryDark : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ─── Main Layout (Categories Left + Menu Center + Live Cart Right on Tablet) ───
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isThreePane = constraints.maxWidth >= 840;
              final categoryWidth = Responsive.categoryPanelWidth(context);
              final isCompact = Responsive.isCompact(context);

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left Panel: Categories (ALWAYS on the left)
                  SizedBox(
                    width: categoryWidth,
                    child: _buildCategoryLeftPanel(categories, isCompact),
                  ),

                  const VerticalDivider(width: 1, thickness: 1, color: AppColors.borderLight),

                  // Center Panel: Menu Grid
                  Expanded(
                    child: _buildMenuItemsRightPanel(filteredItems, isCompact),
                  ),

                  // Right Panel: Live Cart & Direct Settle on Tablet Landscape
                  if (isThreePane) ...[
                    const VerticalDivider(width: 1, thickness: 1, color: AppColors.borderLight),
                    SizedBox(
                      width: 330,
                      child: _buildTabletParcelCartPanel(),
                    ),
                  ],
                ],
              );
            },
          ),
        ),

        // ─── Docked Running Bottom Bar (Mobile / Portrait only) ─────────
        LayoutBuilder(
          builder: (context, constraints) {
            final isThreePane = MediaQuery.sizeOf(context).width >= 840;
            if (isThreePane) return const SizedBox.shrink();
            return _buildBottomBar();
          },
        ),
      ],
    );
  }

  // ─── Waiting for Settlement View ───────────────────────────────────────────

  Widget _buildWaitingForSettlementView() {
    if (_isLoadingPending) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primaryGreen),
            SizedBox(height: 12),
            Text(
              'Loading pending parcel orders...',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_pendingError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
              const SizedBox(height: 12),
              Text(
                'Failed to load pending bills:\n$_pendingError',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadPendingBills,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_pendingBills.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFBBF7D0), width: 2),
                ),
                child: const Icon(
                  Icons.task_alt_rounded,
                  size: 56,
                  color: Color(0xFF16A34A),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No Pending Parcel Orders',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'All takeaway orders are paid and settled.\nNew orders placed with "Pay Later" will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() => _selectedTab = 0);
                },
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                label: const Text('Take New Parcel Order'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Sub-header bar with count and refresh
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            border: Border(bottom: BorderSide(color: Colors.amber.shade200)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFB45309)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_pendingBills.length} ${_pendingBills.length == 1 ? "parcel order" : "parcel orders"} waiting for customer pickup & payment',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20, color: Color(0xFF92400E)),
                tooltip: 'Refresh Queue',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _loadPendingBills();
                },
              ),
            ],
          ),
        ),

        // List of pending cards
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _pendingBills.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final bill = _pendingBills[index];
                  return _buildPendingBillCard(bill);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPendingBillCard(_PendingParcelBill bill) {
    final elapsedStr = _formatElapsed(bill.createdAt);
    final timeStr = AppDateTime.formatTime(bill.createdAt);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top header: Order # + Bill # + Time
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
              border: Border(bottom: BorderSide(color: Colors.orange.shade100)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEA580C),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.takeout_dining_rounded, size: 12, color: Colors.white),
                      const SizedBox(width: 3),
                      Text(
                        '#${bill.orderNumber}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Bill #${bill.billNumber}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule_rounded, size: 12, color: Colors.grey),
                    const SizedBox(width: 3),
                    Text(
                      '$timeStr ($elapsedStr)',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Customer details
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                const Icon(Icons.person_rounded, size: 15, color: AppColors.primaryGreen),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    bill.customerPhone.isNotEmpty
                        ? '${bill.customerName.isNotEmpty ? bill.customerName : "Customer"} • ${bill.customerPhone}'
                        : (bill.customerName.isNotEmpty ? bill.customerName : 'Parcel Customer'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, indent: 14, endIndent: 14),

          // Items list
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              children: bill.items.map((item) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${item.quantity}x',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (item.notes != null && item.notes!.isNotEmpty)
                              Text(
                                item.notes!,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '₹${item.totalPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          const Divider(height: 1),

          // Bottom summary & action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'To Collect',
                      style: TextStyle(fontSize: 9.5, color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '₹${bill.finalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
                const Spacer(),

                // Edit button
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0284C7),
                    backgroundColor: const Color(0xFFF0F9FF),
                    side: const BorderSide(color: Color(0xFFBAE6FD)),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _handleEditPendingOrder(bill),
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('Edit', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 6),

                // Cancel button
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(color: Colors.red.shade300),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _handleCancelPendingOrder(bill),
                  child: const Text('Cancel', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 6),

                // Collect & Settle button
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _handleSettlePendingBill(bill),
                  icon: const Icon(Icons.payments_rounded, size: 14),
                  label: const Text('Collect & Settle', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Left Category Panel ──────────────────────────────────────────────────

  Widget _buildCategoryLeftPanel(List<Category> categories, bool isCompact) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFF0F2E1E)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 10 : 14,
              vertical: 13,
            ),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF265036), width: 1)),
            ),
            child: Text(
              'Categories',
              style: TextStyle(
                color: Colors.white,
                fontSize: isCompact ? 11 : 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.symmetric(
                vertical: 8,
                horizontal: isCompact ? 4 : 8,
              ),
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final category = categories[index];
                final isSelected = _selectedCategoryId == category.id;

                final imageAsset = category.imageUrl != null && category.imageUrl!.isNotEmpty
                    ? category.imageUrl!
                    : 'assets/images/categories/${category.slug}.png';

                return Material(
                  color: isSelected ? const Color(0xFF266540) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _searchController.clear();
                      setState(() {
                        _selectedCategoryId = category.id;
                        _searchQuery = '';
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? 6 : 10,
                        vertical: isCompact ? 8 : 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: isCompact
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Image.asset(
                                    imageAsset,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Icon(Icons.restaurant_rounded, size: 18, color: Color(0xFF0F2E1E)),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  category.name,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected ? Colors.white : const Color(0xFFB4C8BA),
                                    height: 1.15,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: Colors.white,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Image.asset(
                                    imageAsset,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Icon(Icons.restaurant_rounded, size: 18, color: Color(0xFF0F2E1E)),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    category.name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                      color: isSelected ? Colors.white : const Color(0xFFB4C8BA),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Right Menu Items Panel ───────────────────────────────────────────────

  Widget _buildMenuItemsRightPanel(List<MenuItem> items, bool isCompact) {
    final isSearching = _searchQuery.trim().isNotEmpty;

    return Column(
      children: [
        if (isSearching)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            color: const Color(0xFFFFF7ED),
            child: Row(
              children: [
                const Icon(
                  Icons.manage_search_rounded,
                  size: 16,
                  color: Color(0xFFEA580C),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Found ${items.length} ${items.length == 1 ? "item" : "items"} for "$_searchQuery"',
                    style: const TextStyle(
                      color: Color(0xFFC2410C),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      'Clear',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 10),
                        Text(
                          isSearching
                              ? 'No menu items found matching "$_searchQuery".'
                              : 'No menu items found.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (isSearching) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFEA580C),
                              side: const BorderSide(color: Color(0xFFFED7AA)),
                            ),
                            icon: const Icon(Icons.clear, size: 16),
                            label: const Text('Clear search'),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = constraints.maxWidth >= 520
                        ? 3
                        : (constraints.maxWidth >= 310 ? 2 : 1);

                    final aspectRatio = crossAxisCount == 1
                        ? 2.3
                        : (crossAxisCount == 2 ? 0.65 : 0.72);

                    final spacing = Responsive.gridSpacing(context);

                    return GridView.builder(
                      padding: Responsive.screenPadding(context),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                        childAspectRatio: aspectRatio,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final cartItem = _cart[item.id];
                        final quantity = cartItem?.quantity ?? 0;

                        return _buildMenuItemCard(item, cartItem, quantity, isSingleColumn: crossAxisCount == 1);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMenuItemCard(MenuItem item, CartItem? cartItem, int quantity, {bool isSingleColumn = false}) {
    final hasAddons = cartItem != null && cartItem.selectedAddons.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openCustomizationModal(item),
        borderRadius: BorderRadius.circular(AppColors.radiusMedium),
        child: Container(
          padding: EdgeInsets.all(Responsive.isCompact(context) ? 8 : 10),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(AppColors.radiusMedium),
            border: Border.all(
              color: quantity > 0 ? AppColors.secondaryGreen.withValues(alpha: 0.3) : AppColors.borderLight,
              width: 1,
            ),
            boxShadow: [
              ...AppColors.shadowSmall,
              if (quantity > 0)
                BoxShadow(
                  color: AppColors.secondaryGreen.withValues(alpha: 0.08),
                  blurRadius: 8,
                  spreadRadius: -2,
                ),
            ],
          ),
          child: isSingleColumn
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Product Photo Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                      child: ProductImageWidget(
                        imageUrl: item.imageUrl,
                        width: 66,
                        height: 66,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Details Column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.name,
                            style: AppTextStyles.h4.copyWith(
                              letterSpacing: -0.1,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (item.description != null && item.description!.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              item.description!,
                              style: AppTextStyles.caption.copyWith(fontSize: 10),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (cartItem != null && (cartItem.isParcel || hasAddons)) ...[
                            const SizedBox(height: 2),
                            _buildParcelBadges(cartItem, hasAddons),
                          ],
                          const SizedBox(height: 4),
                          _buildParcelPriceAndStepper(item, cartItem, quantity, hasAddons),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top: Product Photo
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                      child: ProductImageWidget(
                        imageUrl: item.imageUrl,
                        height: Responsive.isCompact(context) ? 72 : 88,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 5),

                    // Item Name + Description
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            item.name,
                            style: AppTextStyles.h4.copyWith(
                              letterSpacing: -0.1,
                              fontSize: Responsive.isCompact(context) ? 12 : 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (item.description != null && item.description!.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              item.description!,
                              style: AppTextStyles.caption.copyWith(
                                fontSize: Responsive.isCompact(context) ? 9 : 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (cartItem != null && (cartItem.isParcel || hasAddons)) ...[
                      const SizedBox(height: 2),
                      _buildParcelBadges(cartItem, hasAddons),
                    ],
                    const SizedBox(height: 4),
                    _buildParcelPriceAndStepper(item, cartItem, quantity, hasAddons),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildParcelBadges(CartItem cartItem, bool hasAddons) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: const Text(
              '📦 PARCEL',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Color(0xFFEA580C),
              ),
            ),
          ),
          if (hasAddons) ...[
            const SizedBox(width: 4),
            ...cartItem.selectedAddons.map(
              (addon) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '+${addon.name} (+₹${addon.price.toStringAsFixed(0)})',
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildParcelPriceAndStepper(MenuItem item, CartItem? cartItem, int quantity, bool hasAddons) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Price Breakdown
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (quantity == 0) ...[
                Text(
                  '₹${item.basePrice.toStringAsFixed(0)}',
                  style: AppTextStyles.moneySmall.copyWith(
                    color: AppColors.primaryDark,
                    fontSize: Responsive.isCompact(context) ? 12 : 14,
                  ),
                ),
                const Text(
                  'Tap to customise',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                ),
              ] else if (quantity == 1) ...[
                Text(
                  '₹${cartItem!.itemTotal.toStringAsFixed(0)}',
                  style: AppTextStyles.moneySmall.copyWith(
                    color: AppColors.primaryDark,
                    fontSize: Responsive.isCompact(context) ? 12 : 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (hasAddons)
                  Text(
                    '₹${item.basePrice.toStringAsFixed(0)} + ₹${cartItem.addonsPricePerUnit.toStringAsFixed(0)} add-on',
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.primaryGreen),
                  )
                else
                  const Text(
                    'Customise ›',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.primaryGreen),
                  ),
              ] else ...[
                Text(
                  '₹${cartItem!.itemTotal.toStringAsFixed(0)}',
                  style: AppTextStyles.moneySmall.copyWith(
                    color: AppColors.primaryDark,
                    fontSize: Responsive.isCompact(context) ? 12 : 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '₹${cartItem.effectiveUnitPrice.toStringAsFixed(0)} ea${hasAddons ? " (incl. add-on)" : ""}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: hasAddons ? AppColors.primaryGreen : AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 4),

        // Stepper
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: ScaleTransition(scale: animation, child: child));
          },
          child: quantity == 0
              ? _buildAddButton(
                  item: item,
                  key: const ValueKey('add_btn'),
                )
              : _buildQuantityStepper(
                  item: item,
                  qty: quantity,
                  key: const ValueKey('stepper_ctrl'),
                ),
        ),
      ],
    );
  }

  Widget _buildAddButton({required MenuItem item, required Key key}) {
    return Material(
      key: key,
      color: AppColors.primaryGreen,
      borderRadius: BorderRadius.circular(AppColors.radiusSmall),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppColors.radiusSmall),
        onTap: () => _addItem(item),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 16, color: Colors.white),
              SizedBox(width: 4),
              Text(
                'Add',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuantityStepper({required MenuItem item, required int qty, required Key key}) {
    return Container(
      key: key,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.secondaryLight,
        borderRadius: BorderRadius.circular(AppColors.radiusSmall),
        border: Border.all(color: AppColors.secondaryGreen, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(AppColors.radiusSmall - 1)),
              onTap: () => _decrementItem(item.id),
              child: Container(
                width: 32,
                height: 34,
                alignment: Alignment.center,
                child: const Icon(Icons.remove_rounded, size: 16, color: AppColors.secondaryGreen),
              ),
            ),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 24),
            alignment: Alignment.center,
            child: Text(
              '$qty',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.primaryDark),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(AppColors.radiusSmall - 1)),
              onTap: () => _addItem(item),
              child: Container(
                width: 32,
                height: 34,
                alignment: Alignment.center,
                child: const Icon(Icons.add_rounded, size: 16, color: AppColors.secondaryGreen),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Docked Running Bottom Bar ────────────────────────────────────────────

  Widget _buildBottomBar() {
    final canSubmit = _cart.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderLight, width: 1)),
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, -3))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      '$_totalItemsCount items',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                    ),
                    const SizedBox(width: 4),
                    const Text('• Parcel', style: TextStyle(fontSize: 12, color: Color(0xFFEA580C), fontWeight: FontWeight.bold)),
                  ],
                ),
                Text(
                  '₹${_grandTotalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primaryGreen),
                ),
              ],
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: canSubmit ? _handleReviewAndSettle : null,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text('Review & Settle'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                disabledForegroundColor: Colors.grey.shade500,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Tablet Landscape Live Parcel Cart Panel ─────────────────────────────

  Widget _buildTabletParcelCartPanel() {
    final cartItems = _cart.values.toList();
    final canSubmit = _cart.isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.creamSoft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Parcel info + Customer Details
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: AppColors.borderLight, width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFED7AA)),
                  ),
                  child: const Icon(
                    Icons.takeout_dining_rounded,
                    size: 16,
                    color: Color(0xFFEA580C),
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Parcel Cart',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Direct Takeaway Order',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_totalItemsCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEA580C),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$_totalItemsCount',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Items List / Empty Placeholder
          Expanded(
            child: cartItems.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFFFF7ED),
                              border: Border.all(color: const Color(0xFFFED7AA)),
                            ),
                            child: const Icon(
                              Icons.takeout_dining_outlined,
                              size: 28,
                              color: Color(0xFFEA580C),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Parcel cart is empty',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tap [+ Add] on items to add them to this takeaway order',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    itemCount: cartItems.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final cartItem = cartItems[index];
                      final item = cartItem.menuItem;
                      final hasAddons = cartItem.selectedAddons.isNotEmpty;

                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                          border: Border.all(color: AppColors.borderLight),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x06000000),
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: AppColors.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '₹${cartItem.itemTotal.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.primaryDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    setState(() {
                                      _cart.remove(item.id);
                                    });
                                  },
                                ),
                              ],
                            ),

                            if (hasAddons) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 4,
                                runSpacing: 2,
                                children: cartItem.selectedAddons.map((addon) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryLight,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '+${addon.name}',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primaryDark,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],

                            const SizedBox(height: 6),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                InkWell(
                                  onTap: () => _openCustomizationModal(item),
                                  child: const Text(
                                    'Edit addons ›',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primaryGreen,
                                    ),
                                  ),
                                ),

                                // Stepper [-] qty [+]
                                Container(
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: AppColors.secondaryLight,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: AppColors.secondaryGreen,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(
                                        onTap: () => _decrementItem(item.id),
                                        child: const SizedBox(
                                          width: 26,
                                          height: 28,
                                          child: Icon(
                                            Icons.remove_rounded,
                                            size: 14,
                                            color: AppColors.primaryDark,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        constraints:
                                            const BoxConstraints(minWidth: 22),
                                        alignment: Alignment.center,
                                        child: Text(
                                          '${cartItem.quantity}',
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.primaryDark,
                                          ),
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () => _addItem(item),
                                        child: const SizedBox(
                                          width: 26,
                                          height: 28,
                                          child: Icon(
                                            Icons.add_rounded,
                                            size: 14,
                                            color: AppColors.primaryDark,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Financial Summary & Action
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: AppColors.borderLight, width: 1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x0C000000),
                  blurRadius: 8,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total ($_totalItemsCount ${_totalItemsCount == 1 ? "item" : "items"})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '₹${_grandTotalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: canSubmit ? _handleReviewAndSettle : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      disabledBackgroundColor: AppColors.borderMedium,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Review & Settle',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
  }
}
