import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../../repositories/billing_repository.dart';
import '../../../services/supabase_service.dart';

/// Representation of an individual item within a billed order.
class _BilledItem {
  final String id;
  final String? menuItemId;
  final String name;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  const _BilledItem({
    required this.id,
    this.menuItemId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });
}

/// Representation of a bill row with its order and itemized items.
class _BillRow {
  final String id;
  final String billNumber;
  final double finalAmount;
  final String status;
  final DateTime createdAt;
  final String? customerName;
  final String? customerPhone;
  final String orderType;
  final String? orderNumber;
  final String? orderId;
  final bool isEdited;
  final List<_BilledItem> items;
  final List<Map<String, dynamic>> payments;

  const _BillRow({
    required this.id,
    required this.billNumber,
    required this.finalAmount,
    required this.status,
    required this.createdAt,
    this.customerName,
    this.customerPhone,
    required this.orderType,
    this.orderNumber,
    this.orderId,
    this.isEdited = false,
    this.items = const [],
    this.payments = const [],
  });

  String get paymentSummary {
    if (payments.isEmpty) return 'PAID';
    if (payments.length == 1) {
      final m = payments.first['payment_method']?.toString().toUpperCase() ?? 'PAID';
      return m;
    }
    final cashPmt = payments.firstWhere(
      (p) => (p['payment_method']?.toString().toLowerCase()) == 'cash',
      orElse: () => {},
    );
    final upiPmt = payments.firstWhere(
      (p) => (p['payment_method']?.toString().toLowerCase()) == 'upi',
      orElse: () => {},
    );
    final cashAmt = (cashPmt['amount'] as num?)?.toDouble() ?? 0.0;
    final upiAmt = (upiPmt['amount'] as num?)?.toDouble() ?? 0.0;
    if (cashAmt > 0 && upiAmt > 0) {
      return 'SPLIT (₹${cashAmt.toStringAsFixed(0)} / ₹${upiAmt.toStringAsFixed(0)})';
    }
    return 'SPLIT';
  }

  String get primaryPaymentMethod {
    if (payments.isEmpty) return 'cash';
    if (payments.length > 1) return 'split';
    return payments.first['payment_method']?.toString().toLowerCase() ?? 'cash';
  }
}

/// Modal bottom sheet showing Today's Billed Items directly from the database.
/// Includes toggle for Dine-In vs Parcel with total amount summaries, itemized breakdowns,
/// Revert option for Dine-In bills, and Edit Order option for Parcel bills.
class CashierTodayBillsSheet extends StatefulWidget {
  const CashierTodayBillsSheet._();

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => const CashierTodayBillsSheet._(),
    );
  }

  @override
  State<CashierTodayBillsSheet> createState() => _CashierTodayBillsSheetState();
}

class _CashierTodayBillsSheetState extends State<CashierTodayBillsSheet> {
  bool _isLoading = true;
  String? _error;
  List<_BillRow> _dineInBills = [];
  List<_BillRow> _parcelBills = [];

  /// 0 = Dine-In, 1 = Parcel
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadTodayBills();
  }

  Future<void> _loadTodayBills() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final client = SupabaseService.client;
      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();

      // Query bills joined with orders, order_items, and payments
      // Note: item_total is the generated column in order_items
      final data = await client
          .from('bills')
          .select(
            'id, bill_number, final_amount, status, created_at, business_date, '
            'customer_name_snapshot, customer_phone_snapshot, '
            'orders(id, order_type, order_number, notes, order_items(id, menu_item_id, item_name_snapshot, quantity, unit_price_snapshot, item_total, status)), '
            'payments(id, payment_method, amount, cash_tendered, change_returned, transaction_reference, status)',
          )
          .or('business_date.eq.$todayStr,created_at.gte.$startOfDay')
          .order('created_at', ascending: false);

      final List<_BillRow> dineIn = [];
      final List<_BillRow> parcel = [];

      for (final row in (data as List<dynamic>)) {
        final map = Map<String, dynamic>.from(row as Map);
        final order = map['orders'] as Map<String, dynamic>?;
        final rawOrderType = (order?['order_type'] as String?)?.toLowerCase() ?? 'dine_in';
        final isTakeaway = rawOrderType == 'takeaway' || rawOrderType == 'parcel';

        final notes = order?['notes'] as String?;
        final isEdited = notes != null && notes.contains('[EDITED]');

        // Extract active order items (excluding cancelled items)
        final rawItems = (order?['order_items'] as List<dynamic>?) ?? [];
        final List<_BilledItem> items = [];
        for (final it in rawItems) {
          final itMap = Map<String, dynamic>.from(it as Map);
          final itemStatus = (itMap['status'] as String?)?.toLowerCase();
          if (itemStatus == 'cancelled') continue;

          final qty = (itMap['quantity'] as num?)?.toInt() ?? 1;
          final unitP = (itMap['unit_price_snapshot'] as num?)?.toDouble() ?? 0.0;
          final totalP = (itMap['item_total'] as num?)?.toDouble() ?? (unitP * qty);
          items.add(_BilledItem(
            id: itMap['id'] as String? ?? '',
            menuItemId: itMap['menu_item_id'] as String?,
            name: itMap['item_name_snapshot'] as String? ?? 'Item',
            quantity: qty,
            unitPrice: unitP,
            totalPrice: totalP,
          ));
        }

        // Extract payments
        final rawPayments = (map['payments'] as List<dynamic>?) ?? [];
        final List<Map<String, dynamic>> payments = rawPayments
            .map((p) => Map<String, dynamic>.from(p as Map))
            .where((p) => (p['status'] as String?)?.toLowerCase() != 'failed')
            .toList();

        final bill = _BillRow(
          id: map['id'] as String? ?? '',
          billNumber: map['bill_number'] as String? ?? '-',
          finalAmount: (map['final_amount'] as num?)?.toDouble() ?? 0.0,
          status: (map['status'] as String? ?? 'paid').toLowerCase(),
          createdAt: map['created_at'] != null
              ? DateTime.parse(map['created_at'].toString()).toLocal()
              : DateTime.now(),
          customerName: map['customer_name_snapshot'] as String?,
          customerPhone: map['customer_phone_snapshot'] as String?,
          orderType: isTakeaway ? 'takeaway' : 'dine_in',
          orderNumber: order?['order_number'] as String?,
          orderId: order?['id'] as String?,
          isEdited: isEdited,
          items: items,
          payments: payments,
        );

        if (isTakeaway) {
          parcel.add(bill);
        } else {
          dineIn.add(bill);
        }
      }

      if (mounted) {
        setState(() {
          _dineInBills = dineIn;
          _parcelBills = parcel;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load bills: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openSwapPaymentDialog(_BillRow bill) async {
    final swapped = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SwapPaymentMethodDialog(bill: bill),
    );

    if (swapped == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Payment method swapped successfully for ${bill.billNumber}'),
              ),
            ],
          ),
          backgroundColor: AppColors.primaryGreen,
          duration: const Duration(seconds: 3),
        ),
      );
      _loadTodayBills();
    }
  }

  Future<void> _openEditParcelDialog(_BillRow bill) async {
    final updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditParcelBillDialog(bill: bill),
    );

    if (updated == true) {
      _loadTodayBills();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;
    final isTablet = screenW >= 600;

    // Only count active paid bills for KPI summaries (skip voided)
    final activeDineIn = _dineInBills.where((b) => b.status != 'voided').toList();
    final activeParcel = _parcelBills.where((b) => b.status != 'voided').toList();

    final totalDineInAmount = activeDineIn.fold(0.0, (s, b) => s + b.finalAmount);
    final totalParcelAmount = activeParcel.fold(0.0, (s, b) => s + b.finalAmount);
    final grandTotalAmount = totalDineInAmount + totalParcelAmount;
    final totalBillsCount = activeDineIn.length + activeParcel.length;

    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

    return Container(
      height: screenH * 0.90,
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FA),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.receipt_long_rounded, color: AppColors.primaryGreen, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Today's Billed Items",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1B4332)),
                      ),
                      Text(
                        DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.primaryGreen),
                  onPressed: _loadTodayBills,
                  tooltip: 'Refresh from Database',
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Grand Total KPI strip directly from database
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B4332), Color(0xFF2D6A4F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 3)),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "TOTAL BILLED TODAY",
                          style: TextStyle(color: Color(0xFFD8F3DC), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fmt.format(grandTotalAmount),
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '$totalBillsCount bills settled today',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    height: 40,
                    width: 1,
                    color: Colors.white24,
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.table_restaurant_rounded, size: 12, color: Color(0xFFD8F3DC)),
                          const SizedBox(width: 4),
                          Text('Dine: ${fmt.format(totalDineInAmount)}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.takeout_dining_rounded, size: 12, color: Color(0xFFFFE8D6)),
                          const SizedBox(width: 4),
                          Text('Parcel: ${fmt.format(totalParcelAmount)}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Toggle Tab (Dine-In / Parcel)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  _toggleTab(
                    label: '🍽  Dine-In',
                    badgeCount: _dineInBills.length,
                    amount: totalDineInAmount,
                    index: 0,
                  ),
                  _toggleTab(
                    label: '🥡  Parcel / Takeaway',
                    badgeCount: _parcelBills.length,
                    amount: totalParcelAmount,
                    index: 1,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          const Divider(height: 1),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
                : _error != null
                    ? _buildErrorState()
                    : _buildBillsList(_tabIndex == 0 ? _dineInBills : _parcelBills, isTablet, fmt),
          ),
        ],
      ),
    );
  }

  Widget _toggleTab({
    required String label,
    required int badgeCount,
    required double amount,
    required int index,
  }) {
    final isSelected = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 1))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? AppColors.primaryGreen : Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primaryGreen : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(_error ?? 'Unknown error loading bills', style: const TextStyle(color: AppColors.error, fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadTodayBills,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Try Again'),
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

  Widget _buildBillsList(List<_BillRow> bills, bool isTablet, NumberFormat fmt) {
    if (bills.isEmpty) {
      final typeLabel = _tabIndex == 0 ? 'Dine-In' : 'Parcel / Takeaway';
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 52, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'No $typeLabel bills for today',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Text(
              'Settled bills will appear here in real-time.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: bills.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _buildBillCard(bills[i], fmt),
    );
  }

  Widget _buildBillCard(_BillRow bill, NumberFormat fmt) {
    final isVoided = bill.status == 'voided';
    final isPaid = bill.status == 'paid';

    final Color statusColor;
    final Color statusBg;
    if (isVoided) {
      statusColor = const Color(0xFFDC2626);
      statusBg = const Color(0xFFFEE2E2);
    } else if (isPaid) {
      statusColor = const Color(0xFF2D6A4F);
      statusBg = const Color(0xFFD8F3DC);
    } else {
      statusColor = const Color(0xFFD97706);
      statusBg = const Color(0xFFFEF3C7);
    }

    return Container(
      decoration: BoxDecoration(
        color: isVoided ? const Color(0xFFFAFAFA) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isVoided ? Colors.red.shade100 : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: bill info, type, status badge, EDITED badge, and total
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    bill.orderType == 'takeaway'
                        ? Icons.takeout_dining_rounded
                        : Icons.table_restaurant_rounded,
                    color: statusColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Text(
                            bill.billNumber,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: isVoided ? Colors.grey.shade600 : const Color(0xFF1B4332),
                              decoration: isVoided ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              bill.status.toUpperCase(),
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          // Payment Method Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: bill.primaryPaymentMethod == 'cash'
                                  ? const Color(0xFFE8F5E9)
                                  : bill.primaryPaymentMethod == 'upi'
                                      ? const Color(0xFFEDE9FE)
                                      : const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: bill.primaryPaymentMethod == 'cash'
                                    ? const Color(0xFF81C784)
                                    : bill.primaryPaymentMethod == 'upi'
                                        ? const Color(0xFFA78BFA)
                                        : const Color(0xFFFDBA74),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  bill.primaryPaymentMethod == 'cash'
                                      ? Icons.money_rounded
                                      : bill.primaryPaymentMethod == 'upi'
                                          ? Icons.qr_code_rounded
                                          : Icons.call_split_rounded,
                                  size: 11,
                                  color: bill.primaryPaymentMethod == 'cash'
                                      ? const Color(0xFF2E7D32)
                                      : bill.primaryPaymentMethod == 'upi'
                                          ? const Color(0xFF6D28D9)
                                          : const Color(0xFFC2410C),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  bill.paymentSummary,
                                  style: TextStyle(
                                    color: bill.primaryPaymentMethod == 'cash'
                                        ? const Color(0xFF2E7D32)
                                        : bill.primaryPaymentMethod == 'upi'
                                            ? const Color(0xFF6D28D9)
                                            : const Color(0xFFC2410C),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // EDITED badge for orders that were modified or payment swapped
                          if (bill.isEdited)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFF59E0B)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit_note_rounded, size: 12, color: Color(0xFFB45309)),
                                  SizedBox(width: 3),
                                  Text(
                                    'EDITED',
                                    style: TextStyle(
                                      color: Color(0xFFB45309),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              bill.customerName ?? (bill.orderType == 'takeaway' ? 'Parcel Customer' : 'Walk-in Customer'),
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (bill.customerPhone != null && bill.customerPhone!.isNotEmpty) ...[
                            Text(' • ${bill.customerPhone}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          ],
                        ],
                      ),
                      Text(
                        bill.orderNumber != null && bill.orderNumber!.isNotEmpty
                            ? 'Order #${bill.orderNumber} • ${AppDateTime.formatTime(bill.createdAt)}'
                            : AppDateTime.formatTime(bill.createdAt),
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      fmt.format(bill.finalAmount),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isVoided ? Colors.grey.shade500 : const Color(0xFF1B4332),
                        decoration: isVoided ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    Text(
                      '${bill.items.length} items',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ],
            ),

            // Itemized list of billed items
            if (bill.items.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: bill.items.map((item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isVoided ? Colors.grey : AppColors.primaryGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isVoided ? Colors.grey : AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            'x${item.quantity}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            fmt.format(item.totalPrice),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isVoided ? Colors.grey : const Color(0xFF1B4332),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],

            // Action Row: Swap Payment (All active paid bills) & Edit Order (Parcel only)
            if (!isVoided && isPaid) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _openSwapPaymentDialog(bill),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 15, color: Color(0xFF1D4ED8)),
                    label: const Text(
                      'Swap Payment',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF93C5FD)),
                      backgroundColor: const Color(0xFFEFF6FF),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  if (bill.orderType == 'takeaway') ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _openEditParcelDialog(bill),
                      icon: const Icon(Icons.edit_rounded, size: 14, color: AppColors.primaryGreen),
                      label: const Text(
                        'Edit Order',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF86EFAC)),
                        backgroundColor: const Color(0xFFF0FDF4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dialog for editing quantities of items in an existing parcel bill.
class _EditParcelBillDialog extends StatefulWidget {
  final _BillRow bill;

  const _EditParcelBillDialog({required this.bill});

  @override
  State<_EditParcelBillDialog> createState() => _EditParcelBillDialogState();
}

class _EditableItemState {
  final String id;
  String? menuItemId;
  String name;
  double unitPrice;
  int quantity;
  bool isReplaced = false;

  _EditableItemState({
    required this.id,
    this.menuItemId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
  });

  double get total => unitPrice * quantity;
}

class _EditParcelBillDialogState extends State<_EditParcelBillDialog> {
  late List<_EditableItemState> _items;
  bool _isSaving = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _catalogItems = [];

  @override
  void initState() {
    super.initState();
    _items = widget.bill.items
        .map((i) => _EditableItemState(
              id: i.id,
              menuItemId: i.menuItemId,
              name: i.name,
              unitPrice: i.unitPrice,
              quantity: i.quantity,
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
          .order('name');
      if (mounted) {
        setState(() {
          _catalogItems = List<Map<String, dynamic>>.from(res as List);
        });
      }
    } catch (e) {
      debugPrint('Error loading catalog: $e');
    }
  }

  double get _calculatedSubtotal =>
      _items.fold(0.0, (sum, i) => sum + i.total);

  int get _activeItemsCount =>
      _items.where((i) => i.quantity > 0).length;

  void _showReplaceItemSheet(_EditableItemState item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ReplaceItemModal(
        catalogItems: _catalogItems,
        currentItemName: item.name,
        onItemSelected: (selected) {
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

  Future<void> _saveChanges() async {
    if (_activeItemsCount == 0) {
      setState(() {
        _errorMessage = 'Order must have at least 1 active item.';
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
                'order_item_id': i.id.isNotEmpty ? i.id : null,
                'menu_item_id': (i.menuItemId != null && i.menuItemId!.isNotEmpty) ? i.menuItemId : null,
                'item_name': i.name,
                'quantity': i.quantity,
                'unit_price': i.unitPrice,
              })
          .toList();

      final res = await SupabaseService.client.rpc(
        'edit_parcel_bill',
        params: {
          'p_bill_id': widget.bill.id,
          'p_items': payload,
        },
      );

      if (!mounted) return;

      final success = res != null && (res as Map)['success'] == true;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Parcel bill #${widget.bill.billNumber} updated successfully!'),
            backgroundColor: AppColors.primaryGreen,
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isSaving = false;
          _errorMessage = res?['message'] ?? 'Failed to update bill';
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
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

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
            // Dialog Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.edit_rounded, color: AppColors.primaryGreen, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Parcel Bill #${widget.bill.billNumber}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1B4332)),
                        ),
                        Text(
                          widget.bill.customerName ?? 'Parcel Customer',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.grey),
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),

            // Item list with quantity steppers and Replace option
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _items.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, idx) {
                  final item = _items[idx];
                  final isRemoved = item.quantity == 0;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isRemoved ? const Color(0xFFF3F4F6) : Colors.white,
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
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: isRemoved ? Colors.grey.shade500 : const Color(0xFF1F2937),
                                        decoration: isRemoved ? TextDecoration.lineThrough : null,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  if (!isRemoved)
                                    InkWell(
                                      onTap: _isSaving ? null : () => _showReplaceItemSheet(item),
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
                                '${fmt.format(item.unitPrice)} each',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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
                                  width: 32,
                                  height: 32,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    item.quantity == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
                                    size: 16,
                                    color: item.quantity <= 0
                                        ? Colors.grey.shade300
                                        : (item.quantity == 1 ? Colors.red : const Color(0xFF374151)),
                                  ),
                                ),
                              ),
                              Container(
                                width: 36,
                                alignment: Alignment.center,
                                child: Text(
                                  '${item.quantity}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isRemoved ? Colors.red : const Color(0xFF1F2937),
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
                                  width: 32,
                                  height: 32,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.add_rounded,
                                    size: 16,
                                    color: item.quantity >= 99 ? Colors.grey.shade300 : const Color(0xFF374151),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Total for item
                        SizedBox(
                          width: 65,
                          child: Text(
                            fmt.format(item.total),
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isRemoved ? Colors.grey : const Color(0xFF1B4332),
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
                        'NEW SUBTOTAL',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
                      ),
                      Text(
                        '$_activeItemsCount active items',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  Text(
                    fmt.format(_calculatedSubtotal),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1B4332)),
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
                      onPressed: _isSaving ? null : _saveChanges,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
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

/// Bottom sheet modal to search and select a replacement item from the menu catalog.
class _ReplaceItemModal extends StatefulWidget {
  final List<Map<String, dynamic>> catalogItems;
  final String currentItemName;
  final ValueChanged<Map<String, dynamic>> onItemSelected;

  const _ReplaceItemModal({
    required this.catalogItems,
    required this.currentItemName,
    required this.onItemSelected,
  });

  @override
  State<_ReplaceItemModal> createState() => _ReplaceItemModalState();
}

class _ReplaceItemModalState extends State<_ReplaceItemModal> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() {
        _filter = _searchCtrl.text.trim().toLowerCase();
      });
    });
  }

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

    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

    return Container(
      height: MediaQuery.of(context).size.height * 0.70,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Replace Food Item',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF1B4332)),
                      ),
                      Text(
                        'Replacing: ${widget.currentItemName}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search replacement item...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No items found'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final item = filtered[i];
                      final name = item['name'] as String? ?? 'Item';
                      final price = (item['base_price'] as num?)?.toDouble() ?? 0.0;

                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        tileColor: Colors.grey.shade50,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.restaurant_rounded, color: AppColors.primaryGreen, size: 18),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              fmt.format(price),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1B4332)),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.check_circle_outline_rounded, color: AppColors.primaryGreen, size: 20),
                          ],
                        ),
                        onTap: () {
                          widget.onItemSelected(item);
                          Navigator.of(context).pop();
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

/// Dialog for swapping payment method on same-day settled bills (Cash <-> UPI <-> Split).
class _SwapPaymentMethodDialog extends StatefulWidget {
  final _BillRow bill;

  const _SwapPaymentMethodDialog({required this.bill});

  @override
  State<_SwapPaymentMethodDialog> createState() => _SwapPaymentMethodDialogState();
}

class _SwapPaymentMethodDialogState extends State<_SwapPaymentMethodDialog> {
  late String _selectedMode;
  late TextEditingController _cashAmountController;
  late TextEditingController _upiAmountController;
  late TextEditingController _reasonController;
  late TextEditingController _upiRefController;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final currentMethod = widget.bill.primaryPaymentMethod;
    // Suggest the other method as default for convenient 1-tap swap
    if (currentMethod == 'cash') {
      _selectedMode = 'upi';
    } else if (currentMethod == 'upi') {
      _selectedMode = 'cash';
    } else {
      _selectedMode = 'split';
    }

    final halfAmount = (widget.bill.finalAmount / 2).roundToDouble();
    final remAmount = widget.bill.finalAmount - halfAmount;
    _cashAmountController = TextEditingController(text: halfAmount.toStringAsFixed(0));
    _upiAmountController = TextEditingController(text: remAmount.toStringAsFixed(0));
    _reasonController = TextEditingController(text: 'Payment method swapped by cashier');
    _upiRefController = TextEditingController();
  }

  @override
  void dispose() {
    _cashAmountController.dispose();
    _upiAmountController.dispose();
    _reasonController.dispose();
    _upiRefController.dispose();
    super.dispose();
  }

  double get _splitCashAmount => double.tryParse(_cashAmountController.text.trim()) ?? 0.0;
  double get _splitUpiAmount => double.tryParse(_upiAmountController.text.trim()) ?? 0.0;

  void _onCashAmountChanged(String val) {
    final cash = double.tryParse(val.trim()) ?? 0.0;
    final diff = widget.bill.finalAmount - cash;
    if (diff >= 0) {
      _upiAmountController.text = diff.toStringAsFixed(0);
    }
    setState(() {});
  }

  void _onUpiAmountChanged(String val) {
    final upi = double.tryParse(val.trim()) ?? 0.0;
    final diff = widget.bill.finalAmount - upi;
    if (diff >= 0) {
      _cashAmountController.text = diff.toStringAsFixed(0);
    }
    setState(() {});
  }

  Future<void> _handleSwap() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final List<Map<String, dynamic>> newPayments = [];

      if (_selectedMode == 'cash') {
        newPayments.add({
          'method': 'cash',
          'amount': widget.bill.finalAmount,
          'cash_tendered': widget.bill.finalAmount,
          'status': 'completed',
        });
      } else if (_selectedMode == 'upi') {
        newPayments.add({
          'method': 'upi',
          'amount': widget.bill.finalAmount,
          'transaction_reference': _upiRefController.text.trim().isNotEmpty
              ? _upiRefController.text.trim()
              : null,
          'status': 'completed',
        });
      } else {
        // Split mode
        final cash = _splitCashAmount;
        final upi = _splitUpiAmount;
        final total = cash + upi;

        if ((total - widget.bill.finalAmount).abs() > 0.01) {
          throw Exception(
            'Split total (₹${total.toStringAsFixed(0)}) must equal bill amount (₹${widget.bill.finalAmount.toStringAsFixed(0)})',
          );
        }

        if (cash > 0) {
          newPayments.add({
            'method': 'cash',
            'amount': cash,
            'cash_tendered': cash,
            'status': 'completed',
          });
        }
        if (upi > 0) {
          newPayments.add({
            'method': 'upi',
            'amount': upi,
            'transaction_reference': _upiRefController.text.trim().isNotEmpty
                ? _upiRefController.text.trim()
                : null,
            'status': 'completed',
          });
        }
      }

      final repo = BillingRepository();
      await repo.swapBillPaymentMethod(
        billId: widget.bill.id,
        payments: newPayments,
        reason: _reasonController.text.trim().isNotEmpty
            ? _reasonController.text.trim()
            : 'Payment method swapped by cashier',
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '').replaceAll('RepositoryFailureException: ', '');
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF1D4ED8), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Swap Payment Method',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                Text(
                  'Bill: ${widget.bill.billNumber}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bill summary banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('CURRENT METHOD', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text(
                        widget.bill.paymentSummary,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('BILL AMOUNT (LOCKED)', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text(
                        fmt.format(widget.bill.finalAmount),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B4332)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'Select New Payment Method',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),

            // Mode Selection Pills
            Row(
              children: [
                _buildModeTile('cash', '💵 Cash', const Color(0xFF16A34A)),
                const SizedBox(width: 8),
                _buildModeTile('upi', '📱 UPI', const Color(0xFF7C3AED)),
                const SizedBox(width: 8),
                _buildModeTile('split', '⚡ Split', const Color(0xFFEA580C)),
              ],
            ),
            const SizedBox(height: 16),

            // Split Mode Specific Inputs
            if (_selectedMode == 'split') ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.call_split_rounded, size: 14, color: Color(0xFFC2410C)),
                        const SizedBox(width: 6),
                        const Text(
                          'Split Tender Breakdown',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFC2410C)),
                        ),
                        const Spacer(),
                        Text(
                          'Total: ₹${(_splitCashAmount + _splitUpiAmount).toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: ((_splitCashAmount + _splitUpiAmount) == widget.bill.finalAmount)
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Cash (₹)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              TextField(
                                controller: _cashAmountController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  fillColor: Colors.white,
                                  filled: true,
                                ),
                                onChanged: _onCashAmountChanged,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('UPI (₹)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              TextField(
                                controller: _upiAmountController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  fillColor: Colors.white,
                                  filled: true,
                                ),
                                onChanged: _onUpiAmountChanged,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // UPI Reference field (optional)
            if (_selectedMode == 'upi' || _selectedMode == 'split') ...[
              TextField(
                controller: _upiRefController,
                decoration: InputDecoration(
                  labelText: 'UPI Ref / Txn ID (Optional)',
                  labelStyle: const TextStyle(fontSize: 12),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.receipt_outlined, size: 16),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Reason / Audit Note
            TextField(
              controller: _reasonController,
              decoration: InputDecoration(
                labelText: 'Audit Reason',
                labelStyle: const TextStyle(fontSize: 12),
                hintText: 'e.g. Cashier selected UPI mistakenly instead of Cash',
                hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.note_alt_outlined, size: 16),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF87171)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _handleSwap,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1D4ED8),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Confirm Swap', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildModeTile(String mode, String label, Color accentColor) {
    final isSelected = _selectedMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedMode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? accentColor.withOpacity(0.1) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? accentColor : Colors.grey.shade300,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? accentColor : Colors.grey.shade700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

