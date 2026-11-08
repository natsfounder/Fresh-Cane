import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'receipt_print_service.dart';

/// Service for managing direct Bluetooth thermal printer discovery,
/// connection, and ESC/POS 2-inch (58mm) receipt printing.
class BluetoothPrinterService {
  static const String _prefKeyPrinterMac = 'fresh_cane_thermal_printer_mac';
  static const String _prefKeyPrinterName = 'fresh_cane_thermal_printer_name';

  /// Check if Bluetooth is powered on.
  static Future<bool> isBluetoothEnabled() async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (e) {
      debugPrint('[BluetoothPrinterService] Error checking bluetoothEnabled: $e');
      return false;
    }
  }

  /// Check if Bluetooth permissions are granted on Android.
  static Future<bool> checkPermission() async {
    try {
      return await PrintBluetoothThermal.isPermissionBluetoothGranted;
    } catch (e) {
      debugPrint('[BluetoothPrinterService] Error checking permissions: $e');
      return false;
    }
  }

  /// Get list of bonded/paired Bluetooth devices.
  static Future<List<BluetoothInfo>> getPairedDevices() async {
    try {
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (e) {
      debugPrint('[BluetoothPrinterService] Error getting paired devices: $e');
      return [];
    }
  }

  /// Check if currently connected to a printer.
  static Future<bool> isConnected() async {
    try {
      return await PrintBluetoothThermal.connectionStatus;
    } catch (e) {
      debugPrint('[BluetoothPrinterService] Error checking connectionStatus: $e');
      return false;
    }
  }

  /// Connect to a specific printer by its MAC address.
  static Future<bool> connect(String macAddress) async {
    try {
      final isCurrentlyConnected = await PrintBluetoothThermal.connectionStatus;
      if (isCurrentlyConnected) {
        // If already connected, verify if it's the same device or disconnect first
        await PrintBluetoothThermal.disconnect;
      }
      return await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
    } catch (e) {
      debugPrint('[BluetoothPrinterService] Error connecting to $macAddress: $e');
      return false;
    }
  }

  /// Disconnect current printer.
  static Future<bool> disconnect() async {
    try {
      return await PrintBluetoothThermal.disconnect;
    } catch (e) {
      debugPrint('[BluetoothPrinterService] Error disconnecting: $e');
      return false;
    }
  }

  /// Get saved printer MAC address from SharedPreferences.
  static Future<String?> getSavedPrinterMac() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefKeyPrinterMac);
    } catch (_) {
      return null;
    }
  }

  /// Get saved printer name from SharedPreferences.
  static Future<String?> getSavedPrinterName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefKeyPrinterName);
    } catch (_) {
      return null;
    }
  }

  /// Save printer MAC and name to SharedPreferences.
  static Future<void> savePrinter(String mac, String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyPrinterMac, mac);
      await prefs.setString(_prefKeyPrinterName, name);
    } catch (e) {
      debugPrint('[BluetoothPrinterService] Error saving printer: $e');
    }
  }

  /// Clear saved printer from SharedPreferences.
  static Future<void> clearSavedPrinter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKeyPrinterMac);
      await prefs.remove(_prefKeyPrinterName);
    } catch (_) {}
  }

  /// Generates ESC/POS byte sequence specifically tailored for 2-inch (58mm) roll.
  /// 58mm paper is 384 dots width = 32 standard characters per line.
  static Future<List<int>> generate58mmReceiptBytes(ReceiptPrintData data) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    List<int> bytes = [];

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

    // --- STORE HEADER ---
    bytes += generator.text(
      data.storeName.toUpperCase(),
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );

    final address = data.storeAddress != null && data.storeAddress!.trim().isNotEmpty
        ? data.storeAddress!.trim()
        : ReceiptPrintService.defaultStoreAddress;

    // Split multi-line address cleanly for 58mm
    for (final line in address.split('\n')) {
      if (line.trim().isNotEmpty) {
        bytes += generator.text(
          line.trim(),
          styles: const PosStyles(align: PosAlign.center),
        );
      }
    }

    if (hasGstin) {
      bytes += generator.text(
        'GSTIN: ${data.storeGstin!.trim()}',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
    }

    bytes += generator.hr();
    bytes += generator.text(
      receiptTitle,
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.hr();

    // --- METADATA (Grid total = 12) ---
    bytes += generator.row([
      PosColumn(text: 'Bill No:', width: 4),
      PosColumn(text: data.billNumber, width: 8, styles: const PosStyles(align: PosAlign.right, bold: true)),
    ]);

    bytes += generator.row([
      PosColumn(text: 'Date:', width: 4),
      PosColumn(
        text: DateFormat('dd/MM/yy hh:mm a').format(data.dateTime),
        width: 8,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);

    if (data.orderType != null && data.orderType!.isNotEmpty) {
      bytes += generator.row([
        PosColumn(text: 'Order:', width: 4),
        PosColumn(text: data.orderType!, width: 8, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    if (data.customerName != null && data.customerName!.trim().isNotEmpty) {
      bytes += generator.row([
        PosColumn(text: 'Customer:', width: 4),
        PosColumn(text: data.customerName!.trim(), width: 8, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    if (data.customerPhone != null && data.customerPhone!.trim().isNotEmpty) {
      bytes += generator.row([
        PosColumn(text: 'Phone:', width: 4),
        PosColumn(text: data.customerPhone!.trim(), width: 8, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    if (data.cashierName != null && data.cashierName!.isNotEmpty) {
      bytes += generator.row([
        PosColumn(text: 'Cashier:', width: 4),
        PosColumn(text: data.cashierName!, width: 8, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    bytes += generator.hr();

    // --- ITEMS HEADER (58mm: 6 + 2 + 4 = 12) ---
    bytes += generator.row([
      PosColumn(text: 'ITEM', width: 6, styles: const PosStyles(bold: true)),
      PosColumn(text: 'QTY', width: 2, styles: const PosStyles(align: PosAlign.center, bold: true)),
      PosColumn(text: 'TOTAL', width: 4, styles: const PosStyles(align: PosAlign.right, bold: true)),
    ]);
    bytes += generator.hr();

    // --- ITEMS ROWS ---
    if (data.items.isEmpty) {
      bytes += generator.text('Order Items', styles: const PosStyles(align: PosAlign.left));
    } else {
      for (final item in data.items) {
        bytes += generator.row([
          PosColumn(text: item.name, width: 6),
          PosColumn(text: '${item.quantity}', width: 2, styles: const PosStyles(align: PosAlign.center)),
          PosColumn(
            text: item.totalPrice.toStringAsFixed(2),
            width: 4,
            styles: const PosStyles(align: PosAlign.right, bold: true),
          ),
        ]);
      }
    }

    bytes += generator.hr();

    // --- FINANCIAL TOTALS ---
    String formatAmt(double amt) => 'Rs.${amt.toStringAsFixed(2)}';

    bytes += generator.row([
      PosColumn(text: 'Subtotal:', width: 6),
      PosColumn(text: formatAmt(data.subtotal), width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);

    if (hasDiscount) {
      bytes += generator.row([
        PosColumn(text: 'Discount:', width: 6),
        PosColumn(text: '- ${formatAmt(data.discountAmount)}', width: 6, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    if (hasTax) {
      bytes += generator.row([
        PosColumn(text: 'GST (${data.taxRate.toStringAsFixed(1)}%):', width: 7),
        PosColumn(text: formatAmt(data.taxAmount), width: 5, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    if (hasRoundOff) {
      bytes += generator.row([
        PosColumn(text: 'Round Off:', width: 6),
        PosColumn(
          text: '${data.roundOff >= 0 ? '+' : '-'} ${formatAmt(data.roundOff.abs())}',
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    // --- TOTAL AMOUNT (Prominent Double Line) ---
    bytes += generator.hr(ch: '=');
    bytes += generator.row([
      PosColumn(
        text: 'TOTAL AMOUNT:',
        width: 7,
        styles: const PosStyles(bold: true, height: PosTextSize.size1, width: PosTextSize.size1),
      ),
      PosColumn(
        text: formatAmt(data.finalAmount),
        width: 5,
        styles: const PosStyles(align: PosAlign.right, bold: true, height: PosTextSize.size1, width: PosTextSize.size1),
      ),
    ]);
    bytes += generator.hr(ch: '=');

    // --- FOOTER ---
    bytes += generator.feed(1);
    bytes += generator.text(
      'Thank You! Visit Again',
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.feed(3);
    bytes += generator.cut();

    return bytes;
  }

  /// Sends bytes directly to the connected thermal printer.
  static Future<bool> printBytes(List<int> bytes) async {
    try {
      final isConn = await PrintBluetoothThermal.connectionStatus;
      if (!isConn) {
        debugPrint('[BluetoothPrinterService] Printer is not connected');
        return false;
      }
      return await PrintBluetoothThermal.writeBytes(bytes);
    } catch (e) {
      debugPrint('[BluetoothPrinterService] Error writing bytes to printer: $e');
      return false;
    }
  }

  /// High-level printing flow:
  /// 1. Requests Bluetooth permission (Android 12+).
  /// 2. Verifies Bluetooth is on.
  /// 3. If a saved printer MAC exists, attempts to connect.
  /// 4. If no saved printer or connection fails, presents the [BluetoothDevicePickerSheet].
  /// 5. Sends 2-inch ESC/POS bytes directly to printer.
  static Future<bool> printReceiptDirect({
    required BuildContext context,
    required ReceiptPrintData data,
  }) async {
    // Step 1: Request Bluetooth permission first (Android 12+ requires runtime permission)
    final permissionGranted = await checkPermission();
    if (!permissionGranted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth permission denied. Please allow Bluetooth access in Settings.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return false;
    }

    // Step 2: Check if Bluetooth hardware is turned on
    final btEnabled = await isBluetoothEnabled();
    if (!btEnabled) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please turn ON Bluetooth on your device to print.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return false;
    }

    // Check if already connected
    bool connected = await isConnected();
    final savedMac = await getSavedPrinterMac();

    if (!connected && savedMac != null && savedMac.isNotEmpty) {
      // Try to connect to saved printer automatically
      connected = await connect(savedMac);
    }

    if (!connected) {
      // Need user to select a printer from paired devices
      if (!context.mounted) return false;
      final selectedDevice = await showModalBottomSheet<BluetoothInfo>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => BluetoothDevicePickerSheet(
          onFallbackSystemPrint: () async {
            Navigator.pop(ctx);
            // Fallback to PDF system print dialog
            final pdfBytes = await ReceiptPrintService.generateReceiptPdf(data);
            await ReceiptPrintService.printViaSystemDialog(
              docName: 'Receipt_${data.billNumber}',
              pdfBytes: pdfBytes,
            );
          },
        ),
      );

      if (selectedDevice == null) {
        return false; // User dismissed
      }

      // Connect to selected device and save
      connected = await connect(selectedDevice.macAdress);
      if (connected) {
        await savePrinter(selectedDevice.macAdress, selectedDevice.name);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not connect to ${selectedDevice.name}. Please ensure it is turned on and paired.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }
    }

    // Generate 58mm bytes and print
    try {
      final bytes = await generate58mmReceiptBytes(data);
      final success = await printBytes(bytes);

      if (context.mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Receipt printed successfully! 🖨️'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Print failed. Please check printer paper or connection.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      return success;
    } catch (e) {
      debugPrint('[BluetoothPrinterService] Error during print flow: $e');
      return false;
    }
  }
}

/// Modal sheet allowing cashier to choose paired Bluetooth thermal printer or fallback to system print.
class BluetoothDevicePickerSheet extends StatefulWidget {
  final VoidCallback onFallbackSystemPrint;

  const BluetoothDevicePickerSheet({
    super.key,
    required this.onFallbackSystemPrint,
  });

  @override
  State<BluetoothDevicePickerSheet> createState() => _BluetoothDevicePickerSheetState();
}

class _BluetoothDevicePickerSheetState extends State<BluetoothDevicePickerSheet> {
  bool _loading = true;
  List<BluetoothInfo> _devices = [];
  String? _connectingMac;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _loading = true);
    final devices = await BluetoothPrinterService.getPairedDevices();
    if (mounted) {
      setState(() {
        _devices = devices;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.print_rounded, color: Colors.blue, size: 26),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Bluetooth Printer',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '2-inch (58mm) Thermal POS',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh paired devices',
                onPressed: _loading ? null : _loadDevices,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          if (_loading) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Scanning paired Bluetooth devices...'),
                  ],
                ),
              ),
            ),
          ] else if (_devices.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(Icons.bluetooth_searching, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'No paired Bluetooth printers found',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Pair your printer in Android Bluetooth Settings first, then tap Refresh.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ] else ...[
            const Text(
              'Paired Devices:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _devices.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (ctx, index) {
                  final dev = _devices[index];
                  final isConnecting = _connectingMac == dev.macAdress;
                  final devName = dev.name.isNotEmpty ? dev.name : 'Unknown Printer';

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    leading: const Icon(Icons.bluetooth, color: Colors.blue),
                    title: Text(devName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(dev.macAdress, style: const TextStyle(fontSize: 12)),
                    trailing: isConnecting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right, color: Colors.grey),
                    onTap: isConnecting
                        ? null
                        : () {
                            Navigator.pop(context, dev);
                          },
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Option to fallback to system Wi-Fi / PDF print
          OutlinedButton.icon(
            onPressed: widget.onFallbackSystemPrint,
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
            label: const Text('Print via System / WiFi (PDF)'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

