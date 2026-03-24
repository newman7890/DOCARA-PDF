import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pdf_scanner_editor/main.dart';
import 'package:pdf_scanner_editor/services/storage_service.dart';
import 'package:pdf_scanner_editor/services/pdf_service.dart';
import 'package:pdf_scanner_editor/services/permission_service.dart';

void main() {
  testWidgets('App launches and shows home screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<StorageService>(create: (_) => StorageService()),
          Provider<PDFService>(create: (_) => PDFService()),
          Provider<PermissionService>(create: (_) => PermissionService()),
        ],
        child: const PDFScannerApp(showOnboarding: false),
      ),
    );

    // Verify that the home screen title is displayed
    expect(find.text('PDF Scanner'), findsOneWidget);
  });
}
