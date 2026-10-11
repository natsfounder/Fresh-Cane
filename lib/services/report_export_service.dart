import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Result returned from exporting a report
class ExportResult {
  final String filePath;
  final String fileName;
  final String folderName;
  final bool success;
  final String? error;

  const ExportResult({
    required this.filePath,
    required this.fileName,
    required this.folderName,
    this.success = true,
    this.error,
  });
}

/// Service responsible for generating and downloading Excel (.xlsx) and PDF reports
/// directly to the device's Downloads directory.
class ReportExportService {
  const ReportExportService._();

  /// Formats currency
  static String formatCurrency(dynamic value) {
    if (value == null) return '0.00';
    final numVal = num.tryParse(value.toString()) ?? 0;
    return '₹${numVal.toStringAsFixed(2)}';
  }

  /// Finds the primary Downloads directory on the device
  static Future<Directory> _getDownloadDirectory() async {
    if (!kIsWeb && Platform.isAndroid) {
      // 1. Try primary public Download folder on Android (/storage/emulated/0/Download)
      final publicDownload = Directory('/storage/emulated/0/Download');
      try {
        if (await publicDownload.exists()) {
          return publicDownload;
        }
      } catch (_) {}

      // 2. Try external storage Downloads folder
      try {
        final externalDirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
        if (externalDirs != null && externalDirs.isNotEmpty) {
          return externalDirs.first;
        }
      } catch (_) {}
    }

    // 3. Desktop / iOS / Fallback
    try {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) return downloadsDir;
    } catch (_) {}

    return await getApplicationDocumentsDirectory();
  }

  /// Exports report dataset to Excel (.xlsx) and saves directly to Downloads directory.
  /// Automatically opens the file via default spreadsheet viewer.
  static Future<ExportResult> exportToExcel({
    required String reportTitle,
    required String dateRangeStr,
    required List<String> headers,
    required List<List<dynamic>> rows,
  }) async {
    try {
      final excel = Excel.createExcel();
      final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
      final sheet = excel[defaultSheet];

      // Title row
      sheet.appendRow([
        TextCellValue('Fresh Cane - $reportTitle'),
      ]);
      sheet.appendRow([
        TextCellValue('Period: $dateRangeStr | Generated: ${DateTime.now().toString().substring(0, 19)}'),
      ]);
      sheet.appendRow([]); // empty row

      // Header row
      sheet.appendRow(
        headers.map((h) => TextCellValue(h)).toList(),
      );

      // Data rows
      for (final row in rows) {
        sheet.appendRow(
          row.map((cell) {
            if (cell == null) return TextCellValue('-');
            if (cell is num) return DoubleCellValue(cell.toDouble());
            return TextCellValue(cell.toString());
          }).toList(),
        );
      }

      final fileBytes = excel.encode();
      if (fileBytes == null) throw Exception('Failed to encode Excel file');

      final downloadDir = await _getDownloadDirectory();
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final sanitizedTitle = reportTitle.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'fresh_cane_${sanitizedTitle}_$timestamp.xlsx';
      final file = File('${downloadDir.path}/$fileName');
      await file.writeAsBytes(fileBytes, flush: true);

      // Automatically open the downloaded file
      try {
        await OpenFilex.open(file.path);
      } catch (e) {
        debugPrint('[ReportExportService] Could not auto-open Excel: $e');
      }

      return ExportResult(
        filePath: file.path,
        fileName: fileName,
        folderName: downloadDir.path.contains('Download') ? 'Downloads' : 'Documents',
      );
    } catch (e) {
      debugPrint('[ReportExportService] Excel export failed: $e');
      rethrow;
    }
  }

  /// Generates a branded PDF report and saves directly to Downloads directory.
  /// Automatically opens the file via default PDF viewer.
  static Future<ExportResult> exportToPdf({
    required String reportTitle,
    required String dateRangeStr,
    required List<String> headers,
    required List<List<dynamic>> rows,
    Map<String, dynamic>? summaryData,
  }) async {
    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          header: (pw.Context context) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              padding: const pw.EdgeInsets.only(bottom: 8),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey300, width: 1),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'FRESH CANE POS',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor.fromInt(0xFF2E7D32),
                        ),
                      ),
                      pw.Text(
                        reportTitle.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey800,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Range: $dateRangeStr',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                      pw.Text(
                        'Generated: ${DateTime.now().toString().substring(0, 16)}',
                        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
          footer: (pw.Context context) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(top: 8),
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
              ),
            );
          },
          build: (pw.Context context) {
            return [
              if (summaryData != null && summaryData.isNotEmpty) ...[
                pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 12),
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                    children: summaryData.entries.map((e) {
                      return pw.Column(
                        children: [
                          pw.Text(e.key, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            e.value.toString(),
                            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
              pw.TableHelper.fromTextArray(
                headers: headers,
                data: rows.map((r) => r.map((c) => c?.toString() ?? '-').toList()).toList(),
                headerStyle: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF2E7D32),
                ),
                rowDecoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                  ),
                ),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellAlignment: pw.Alignment.centerLeft,
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              ),
            ];
          },
        ),
      );

      final pdfBytes = await pdf.save();

      final downloadDir = await _getDownloadDirectory();
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final sanitizedTitle = reportTitle.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'fresh_cane_${sanitizedTitle}_$timestamp.pdf';
      final file = File('${downloadDir.path}/$fileName');
      await file.writeAsBytes(pdfBytes, flush: true);

      // Automatically open the downloaded file
      try {
        await OpenFilex.open(file.path);
      } catch (e) {
        debugPrint('[ReportExportService] Could not auto-open PDF: $e');
      }

      return ExportResult(
        filePath: file.path,
        fileName: fileName,
        folderName: downloadDir.path.contains('Download') ? 'Downloads' : 'Documents',
      );
    } catch (e) {
      debugPrint('[ReportExportService] PDF export failed: $e');
      rethrow;
    }
  }
}
