import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/storage_service.dart';
import 'services/pdf_service.dart';
import 'services/ocr_service.dart';
import 'services/permission_service.dart';
import 'services/image_processing_service.dart';
import 'services/pdf_editor_service.dart';
import 'services/identity_service.dart';
import 'services/api_service.dart';
import 'services/security_service.dart';
import 'services/payment_service.dart';
import 'services/tts_service.dart';
import 'services/translation_service.dart';
import 'services/spreadsheet_service.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/spreadsheet_editor_screen.dart';
import 'screens/spreadsheet_list_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final bool showOnboarding = !(prefs.getBool('onboarding_shown') ?? false);

  // Initialize Services for registration
  // Basic security check
  final securityService = SecurityService();
  final bool isSuspicious = await securityService.isSuspicious();
  debugPrint("Device Security Status: ${isSuspicious ? 'Suspicious' : 'Secure'}");

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PdfEditorService>(
          create: (_) => PdfEditorService(),
        ),
        Provider<StorageService>(create: (_) => StorageService()),
        Provider<PDFService>(create: (_) => PDFService()),
        Provider<OCRService>(
          create: (_) => OCRService(),
          dispose: (_, service) => service.dispose(),
        ),
        Provider<PermissionService>(create: (_) => PermissionService()),
        Provider<ImageProcessingService>(
          create: (_) => ImageProcessingService(),
        ),
        Provider<IdentityService>(create: (_) => IdentityService()),
        Provider<ApiService>(create: (_) => ApiService()),
        Provider<SecurityService>(create: (_) => SecurityService()),
        Provider<PaymentService>(create: (_) => PaymentService()),
        Provider<SpreadsheetService>(create: (_) => SpreadsheetService()),
        ChangeNotifierProvider<TTSService>(
          create: (_) => TTSService(),
        ),
        Provider<TranslationService>(
          create: (_) => TranslationService(),
          dispose: (_, s) => s.dispose(),
        ),
      ],
      child: PDFScannerApp(showOnboarding: showOnboarding),
    ),
  );
}

class PDFScannerApp extends StatelessWidget {
  final bool showOnboarding;
  const PDFScannerApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Docara',
      debugShowCheckedModeBanner: false,
      initialRoute: showOnboarding ? '/onboarding' : '/home',
      routes: {
        '/onboarding': (context) => const OnboardingScreen(),
        '/home': (context) => const HomeScreen(),
        '/spreadsheet': (context) => const SpreadsheetEditorScreen(),
        '/spreadsheets': (context) => const SpreadsheetListScreen(),
      },
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          primary: Colors.indigo,
          secondary: Colors.indigoAccent,
          brightness: Brightness.light,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: ZoomPageTransitionsBuilder(
              allowEnterRouteSnapshotting: false,
            ),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            splashFactory: InkRipple.splashFactory,
            animationDuration: const Duration(milliseconds: 150),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            splashFactory: InkRipple.splashFactory,
            animationDuration: const Duration(milliseconds: 150),
          ),
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'US')],
      home: showOnboarding ? const OnboardingScreen() : const HomeScreen(),
    );
  }
}
