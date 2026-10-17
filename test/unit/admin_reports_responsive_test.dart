import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_cane/models/settlement_model.dart';
import 'package:fresh_cane/presentation/admin/views/admin_reports_view.dart';
import 'package:fresh_cane/state/settlement_provider.dart';

void main() {
  Widget buildTestWidget({required Size screenSize, SettlementDailySummary? summary}) {
    return ProviderScope(
      overrides: [
        settlementProvider.overrideWith(() => MockSettlementNotifier(summary)),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: screenSize),
          child: const Scaffold(
            body: AdminReportsView(),
          ),
        ),
      ),
    );
  }

  group('AdminReportsView - Responsive Layout & Overflow Elimination Tests', () {
    testWidgets('1. Renders cleanly on standard mobile portrait (360x800) without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestWidget(screenSize: const Size(360, 800)));
      await tester.pumpAndSettle();

      expect(find.byType(AdminReportsView), findsOneWidget);
      expect(find.text('CASH POSITION'), findsOneWidget);
      expect(find.text('UPI POSITION'), findsOneWidget);
      final err = tester.takeException();
      if (err is FlutterError) {
        for (final d in err.diagnostics) {
          debugPrint('DIAG: ${d.value}');
        }
      }
      expect(err, isNull);
    });

    testWidgets('2. Renders cleanly on narrow mobile portrait (320x568) without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestWidget(screenSize: const Size(320, 568)));
      await tester.pumpAndSettle();

      expect(find.byType(AdminReportsView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('3. Renders cleanly on landscape / wide screen (800x480) without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(800, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestWidget(screenSize: const Size(800, 480)));
      await tester.pumpAndSettle();

      expect(find.byType(AdminReportsView), findsOneWidget);
      expect(find.text('CASH POSITION'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('4. Zero opening balance shows [+ Set Float] action button',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final zeroSummary = SettlementDailySummary(
        date: DateTime(2026, 10, 11),
        openingCash: 0.0,
        openingUpi: 0.0,
      );

      await tester.pumpWidget(buildTestWidget(
        screenSize: const Size(390, 844),
        summary: zeroSummary,
      ));
      await tester.pumpAndSettle();

      // Action icon for zero opening float should be present
      expect(find.byIcon(Icons.add_circle_outline_rounded), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('5. Non-zero opening balance preserves automatic value and shows NO add button',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final nonZeroSummary = SettlementDailySummary(
        date: DateTime(2026, 10, 11),
        openingCash: 450.0,
        openingUpi: 250.0,
        salesCash: 100.0,
        expensesCash: 50.0,
      );

      await tester.pumpWidget(buildTestWidget(
        screenSize: const Size(390, 844),
        summary: nonZeroSummary,
      ));
      await tester.pumpAndSettle();

      // Opening balance reflects the calculated values:
      expect(find.text('₹450.00'), findsOneWidget);
      expect(find.text('₹250.00'), findsWidgets);
      // Since openingTotal > 0, manual add button is NOT displayed
      expect(find.byTooltip('Set Manual Opening Float'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

class MockSettlementNotifier extends SettlementNotifier {
  final SettlementDailySummary? _presetSummary;

  MockSettlementNotifier([this._presetSummary]);

  @override
  SettlementState build() {
    final now = DateTime(2026, 10, 11);
    return SettlementState(
      selectedDate: now,
      selectedMonth: DateTime(now.year, now.month, 1),
      dailySummary: _presetSummary ?? SettlementDailySummary(date: now),
    );
  }

  @override
  Future<void> loadSettlementData() async {}
}
