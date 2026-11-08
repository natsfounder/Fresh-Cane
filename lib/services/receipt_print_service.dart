import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/bill_model.dart';
import '../models/payment_model.dart';
import 'supabase_service.dart';

/// Single item line on a receipt.
class ReceiptItem {
  final String name;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  const ReceiptItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });
}

/// Structured data passed to print layout.
class ReceiptPrintData {
  final String billNumber;
  final DateTime dateTime;
  final String storeName;
  final String? storeAddress;
  final String? storeGstin;
  final String? orderType;
  final String? customerName;
  final String? customerPhone;
  final String? cashierName;
  final List<ReceiptItem> items;
  final double subtotal;
  final String? discountType;
  final double discountAmount;
  final double taxRate;
  final double taxAmount;
  final double roundOff;
  final double finalAmount;
  final String paymentMethod;
  final double? cashTendered;
  final double? changeReturned;
  final String? transactionReference;
  final bool isReprint;
  final bool isPreBill;

  const ReceiptPrintData({
    required this.billNumber,
    required this.dateTime,
    required this.storeName,
    this.storeAddress,
    this.storeGstin,
    this.orderType,
    this.customerName,
    this.customerPhone,
    this.cashierName,
    required this.items,
    required this.subtotal,
    this.discountType,
    this.discountAmount = 0.0,
    this.taxRate = 0.0,
    this.taxAmount = 0.0,
    this.roundOff = 0.0,
    required this.finalAmount,
    required this.paymentMethod,
    this.cashTendered,
    this.changeReturned,
    this.transactionReference,
    this.isReprint = false,
    this.isPreBill = false,
  });
}

/// Service responsible for rendering and printing thermal POS receipts and pre-bills.
class ReceiptPrintService {
  /// Fetch order items for a given order ID from Supabase.
  static Future<List<ReceiptItem>> fetchItemsForOrder(String orderId) async {
    if (orderId.isEmpty) return [];
    try {
      final response = await SupabaseService.client
          .from('order_items')
          .select('item_name_snapshot, quantity, unit_price_snapshot, item_total, status')
          .eq('order_id', orderId);

      final list = <ReceiptItem>[];
      for (final row in (response as List<dynamic>)) {
        final map = Map<String, dynamic>.from(row as Map);
        final status = (map['status'] as String?)?.toLowerCase();
        if (status == 'cancelled') continue;

        final qty = (map['quantity'] as num?)?.toInt() ?? 1;
        final unitPrice = (map['unit_price_snapshot'] as num?)?.toDouble() ?? 0.0;
        final total = (map['item_total'] as num?)?.toDouble() ?? (unitPrice * qty);

        list.add(ReceiptItem(
          name: map['item_name_snapshot'] as String? ?? 'Item',
          quantity: qty,
          unitPrice: unitPrice,
          totalPrice: total,
        ));
      }
      return list;
    } catch (e) {
      debugPrint('[ReceiptPrintService] Error fetching items for order $orderId: $e');
      return [];
    }
  }

  /// Builds a thermal receipt PDF document (80mm standard roll format).
  static Future<Uint8List> generateReceiptPdf(ReceiptPrintData data) async {
    final pdf = pw.Document();

    pw.Font? regularFont;
    pw.Font? boldFont;
    String currencySymbol = '₹';

    try {
      regularFont = await PdfGoogleFonts.robotoRegular();
      boldFont = await PdfGoogleFonts.robotoBold();
    } catch (e) {
      debugPrint('[ReceiptPrintService] Roboto font not available, using standard font: $e');
      currencySymbol = 'Rs. ';
    }

    final theme = regularFont != null && boldFont != null
        ? pw.ThemeData.withFont(base: regularFont, bold: boldFont)
        : pw.ThemeData.base();

    String formatAmt(double amt) => '$currencySymbol${amt.toStringAsFixed(2)}';

    // Receipt page format: 80mm roll, dynamic height, tight margins
    const pageFormat = PdfPageFormat(
      80 * PdfPageFormat.mm,
      double.infinity,
      marginTop: 3 * PdfPageFormat.mm,
      marginBottom: 6 * PdfPageFormat.mm,
      marginLeft: 3.5 * PdfPageFormat.mm,
      marginRight: 3.5 * PdfPageFormat.mm,
    );

    final bool hasGstin = data.storeGstin != null && data.storeGstin!.trim().isNotEmpty;
    final bool hasTax = data.taxAmount > 0;
    final bool hasDiscount = data.discountAmount > 0;
    final bool hasRoundOff = data.roundOff.abs() >= 0.01;

    String receiptTitle;
    if (data.isPreBill) {
      receiptTitle = hasTax ? 'BILL / TAX INVOICE' : 'BILL';
    } else if (data.isReprint) {
      receiptTitle = 'DUPLICATE RECEIPT';
    } else if (hasTax) {
      receiptTitle = 'TAX INVOICE';
    } else {
      receiptTitle = 'RECEIPT';
    }

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        theme: theme,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // --- Store Header ---
              pw.Center(
                child: pw.Text(
                  data.storeName.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              if (data.storeAddress != null && data.storeAddress!.trim().isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Center(
                  child: pw.Text(
                    data.storeAddress!.trim(),
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ],
              if (hasGstin) ...[
                pw.SizedBox(height: 2),
                pw.Center(
                  child: pw.Text(
                    'GSTIN: ${data.storeGstin!.trim()}',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ],
              pw.SizedBox(height: 4),

              // Title box
              _buildDashedLine(),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Center(
                  child: pw.Text(
                    receiptTitle,
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ),
              _buildDashedLine(),
              pw.SizedBox(height: 4),

              // --- Bill Metadata ---
              _buildMetaRow('Bill No:', data.billNumber),
              _buildMetaRow(
                'Date/Time:',
                DateFormat('dd/MM/yyyy hh:mm a').format(data.dateTime),
              ),
              if (data.orderType != null && data.orderType!.isNotEmpty)
                _buildMetaRow('Order Type:', data.orderType!),
              if (data.customerName != null && data.customerName!.trim().isNotEmpty)
                _buildMetaRow('Customer:', data.customerName!.trim()),
              if (data.customerPhone != null && data.customerPhone!.trim().isNotEmpty)
                _buildMetaRow('Phone:', data.customerPhone!.trim()),
              if (data.cashierName != null && data.cashierName!.isNotEmpty)
                _buildMetaRow('Cashier:', data.cashierName!),
              pw.SizedBox(height: 4),

              // --- Items Table Header ---
              _buildDashedLine(),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 5,
                      child: pw.Text('ITEM', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text('QTY', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text('RATE', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right),
                    ),
                    pw.Expanded(
                      flex: 3,
                      child: pw.Text('TOTAL', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right),
                    ),
                  ],
                ),
              ),
              _buildDashedLine(),

              // --- Items Rows ---
              if (data.items.isEmpty) ...[
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 4),
                  child: pw.Text('Order Items', style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
                ),
              ] else ...[
                for (final item in data.items)
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          flex: 5,
                          child: pw.Text(
                            item.name,
                            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                            '${item.quantity}',
                            style: const pw.TextStyle(fontSize: 8),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                            item.unitPrice.toStringAsFixed(2),
                            style: const pw.TextStyle(fontSize: 8),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                        pw.Expanded(
                          flex: 3,
                          child: pw.Text(
                            item.totalPrice.toStringAsFixed(2),
                            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              pw.SizedBox(height: 2),
              _buildDashedLine(),

              // --- Financial Totals ---
              pw.SizedBox(height: 2),
              _buildSummaryRow('Subtotal:', formatAmt(data.subtotal)),
              if (hasDiscount)
                _buildSummaryRow(
                  'Discount (${data.discountType ?? 'Flat'}):',
                  '- ${formatAmt(data.discountAmount)}',
                ),
              if (hasTax)
                _buildSummaryRow(
                  'GST (${data.taxRate.toStringAsFixed(1)}%):',
                  formatAmt(data.taxAmount),
                ),
              if (hasRoundOff)
                _buildSummaryRow(
                  'Round Off:',
                  '${data.roundOff >= 0 ? '+' : '-'} ${formatAmt(data.roundOff.abs())}',
                ),

              pw.SizedBox(height: 3),
              _buildSolidLine(thickness: 1.2),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 4),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'TOTAL PAID:',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      formatAmt(data.finalAmount),
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),
              _buildSolidLine(thickness: 1.2),
              pw.SizedBox(height: 6),

              _buildDashedLine(),
              pw.SizedBox(height: 6),

              // --- Footer ---
              pw.Center(
                child: pw.Text(
                  'Thank You! Visit Again',
                  style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 4),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<String?> _resolveStoreAddress(String? snapshotAddress) async {
    if (snapshotAddress != null && snapshotAddress.trim().isNotEmpty) {
      return snapshotAddress.trim();
    }
    try {
      final res = await SupabaseService.client
          .from('store_settings')
          .select('address')
          .limit(1)
          .maybeSingle();
      if (res != null && res['address'] != null) {
        final addr = res['address'].toString().trim();
        if (addr.isNotEmpty) return addr;
      }
    } catch (_) {}
    return null;
  }

  /// Triggers standard printing dialog / layout for a completed Bill.
  static Future<bool> printReceipt({
    required Bill bill,
    required Payment payment,
    String? tableName,
    String? cashierName,
    List<ReceiptItem>? items,
    bool isReprint = false,
  }) async {
    try {
      List<ReceiptItem> receiptItems = items ?? [];
      if (receiptItems.isEmpty && bill.orderId.isNotEmpty) {
        receiptItems = await fetchItemsForOrder(bill.orderId);
      }

      String orderTypeLabel = tableName ?? 'Dine-In';
      if (tableName == null || tableName.isEmpty) {
        orderTypeLabel = 'Dine-In';
      }

      final storeAddress = await _resolveStoreAddress(bill.storeAddressSnapshot);

      final data = ReceiptPrintData(
        billNumber: bill.billNumber,
        dateTime: bill.createdAt,
        storeName: bill.storeNameSnapshot.isNotEmpty ? bill.storeNameSnapshot : 'Fresh Cane',
        storeAddress: storeAddress,
        storeGstin: bill.storeGstinSnapshot,
        orderType: orderTypeLabel,
        customerName: bill.customerNameSnapshot,
        customerPhone: bill.customerPhoneSnapshot,
        cashierName: cashierName ?? 'Cashier',
        items: receiptItems,
        subtotal: bill.subtotalAmount,
        discountType: bill.discountType,
        discountAmount: bill.discountAmount,
        taxRate: bill.taxRateSnapshot,
        taxAmount: bill.taxAmount,
        roundOff: bill.roundOffAmount,
        finalAmount: bill.finalAmount,
        paymentMethod: payment.paymentMethod,
        cashTendered: payment.cashTendered,
        changeReturned: payment.changeReturned,
        transactionReference: payment.transactionReference,
        isReprint: isReprint,
        isPreBill: false,
      );

      final pdfBytes = await generateReceiptPdf(data);

      return await Printing.layoutPdf(
        name: 'Receipt_${bill.billNumber}',
        onLayout: (PdfPageFormat format) async => pdfBytes,
      );
    } catch (e, stack) {
      debugPrint('[ReceiptPrintService] Error executing print: $e\n$stack');
      return false;
    }
  }

  /// Triggers standard printing dialog / layout for an unpaid Bill (Pre-Bill).
  static Future<bool> printPreBill({
    required Bill bill,
    String? tableName,
    String? cashierName,
    List<ReceiptItem>? items,
  }) async {
    try {
      List<ReceiptItem> receiptItems = items ?? [];
      if (receiptItems.isEmpty && bill.orderId.isNotEmpty) {
        receiptItems = await fetchItemsForOrder(bill.orderId);
      }

      String orderTypeLabel = tableName ?? 'Dine-In';
      if (tableName == null || tableName.isEmpty) {
        orderTypeLabel = 'Dine-In';
      }

      final storeAddress = await _resolveStoreAddress(bill.storeAddressSnapshot);

      final data = ReceiptPrintData(
        billNumber: bill.billNumber,
        dateTime: bill.createdAt,
        storeName: bill.storeNameSnapshot.isNotEmpty ? bill.storeNameSnapshot : 'Fresh Cane',
        storeAddress: storeAddress,
        storeGstin: bill.storeGstinSnapshot,
        orderType: orderTypeLabel,
        customerName: bill.customerNameSnapshot,
        customerPhone: bill.customerPhoneSnapshot,
        cashierName: cashierName ?? 'Cashier',
        items: receiptItems,
        subtotal: bill.subtotalAmount,
        discountType: bill.discountType,
        discountAmount: bill.discountAmount,
        taxRate: bill.taxRateSnapshot,
        taxAmount: bill.taxAmount,
        roundOff: bill.roundOffAmount,
        finalAmount: bill.finalAmount,
        paymentMethod: 'Pending',
        isReprint: false,
        isPreBill: true,
      );

      final pdfBytes = await generateReceiptPdf(data);

      return await Printing.layoutPdf(
        name: 'Bill_${bill.billNumber}',
        onLayout: (PdfPageFormat format) async => pdfBytes,
      );
    } catch (e, stack) {
      debugPrint('[ReceiptPrintService] Error executing pre-bill print: $e\n$stack');
      return false;
    }
  }

  // Helper widgets for PDF layout
  static pw.Widget _buildDashedLine() {
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Text(
        '- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -',
        style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey800),
        maxLines: 1,
        overflow: pw.TextOverflow.clip,
      ),
    );
  }

  static pw.Widget _buildSolidLine({double thickness = 0.5}) {
    return pw.Container(
      height: thickness,
      color: PdfColors.black,
      margin: const pw.EdgeInsets.symmetric(vertical: 2),
    );
  }

  static pw.Widget _buildMetaRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 58,
            child: pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSummaryRow(String label, String value, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 8, color: isBold ? PdfColors.black : PdfColors.grey800, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 8, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal),
          ),
        ],
      ),
    );
  }
}
