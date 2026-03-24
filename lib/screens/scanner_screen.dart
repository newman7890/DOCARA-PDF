import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../services/pdf_service.dart';
import '../services/storage_service.dart';
import '../services/permission_service.dart';
import '../models/scanned_document.dart';
import 'viewer_screen.dart' show PdfViewerScreen;
import '../widgets/scan_guide_overlay.dart';

enum ScanMode { document, idCard, passport }

/// Screen that handles the camera-based document scanning logic.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  DocumentScanner? _documentScanner;
  bool _isScanning = false;
  ScanMode _selectedMode = ScanMode.document;
  ScanFilter _selectedFilter = ScanFilter.original; // Safe default
  String? _idFrontPath;

  @override
  void initState() {
    super.initState();
  }

  /// Ensures camera permission is granted before starting the scanner.
  Future<bool> _checkPermissions() async {
    final permissions = context.read<PermissionService>();
    bool granted = await permissions.isCameraGranted();
    if (!granted) {
      granted = await permissions.requestCameraPermission();
    }
    return granted;
  }

  /// Logic to trigger the ML Kit Document Scanner.
  void _startScan() async {
    if (!await _checkPermissions()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission is required.')),
        );
      }
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isScanning = true);

    try {
      final options = DocumentScannerOptions(
        documentFormat: DocumentFormat.jpeg,
        mode: ScannerMode.full,
        pageLimit: _selectedMode == ScanMode.document ? 20 : 1,
        isGalleryImport: true,
      );

      _documentScanner = DocumentScanner(options: options);
      final result = await _documentScanner!.scanDocument();

      if (result.images.isNotEmpty) {
        HapticFeedback.lightImpact();
        if (_selectedMode == ScanMode.idCard && _idFrontPath == null) {
          final originalFrontPath = result.images.first;
          final tempDir = await getTemporaryDirectory();
          final stableFrontPath = '${tempDir.path}/id_card_front_${DateTime.now().millisecondsSinceEpoch}.jpeg';
          
          // Use URI parsing to handle file:// prefix issues
          String src = originalFrontPath;
          if (src.startsWith('file://')) src = Uri.parse(src).toFilePath();
          
          await File(src).copy(stableFrontPath);

          setState(() {
            _idFrontPath = stableFrontPath;
            _isScanning = false;
          });
        } else if (_selectedMode == ScanMode.idCard && _idFrontPath != null) {
          // Finished Back, combine both
          await _convertImagesToPdf([_idFrontPath!, result.images.first]);
        } else {
          // Standard or Passport
          await _convertImagesToPdf(result.images);
        }
      } else {
        if (mounted) setState(() => _isScanning = false);
      }
    } catch (e) {
      debugPrint("Scan error: $e");
      if (mounted) setState(() => _isScanning = false);
    }
  }

  /// Takes separate images from the scanner and merges them into one PDF.
  Future<void> _convertImagesToPdf(List<String> images) async {
    final pdfService = context.read<PDFService>();
    final storage = context.read<StorageService>();

    setState(() => _isScanning = true);

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      String prefix = "Scan";
      String? docType = "Document";

      if (_selectedMode == ScanMode.idCard) {
        prefix = "ID_Card";
        docType = "ID Card";
      } else if (_selectedMode == ScanMode.passport) {
        prefix = "Passport";
        docType = "Passport";
      }

      final outputPath = await storage.getNewFilePath("${prefix}_$timestamp");
      final tempDir = await getTemporaryDirectory();

      debugPrint("SCAN: Processing ${images.length} images with filter: $_selectedFilter");
      List<String> stableImages = [];
      for (int i = 0; i < images.length; i++) {
        String src = images[i];
        if (src.startsWith('file://')) src = Uri.parse(src).toFilePath();
        
        final stablePath = '${tempDir.path}/scan_page_${timestamp}_$i.jpeg';
        try {
          await File(src).copy(stablePath);
          stableImages.add(stablePath);
        } catch (copyError) {
          stableImages.add(src);
        }
      }

      await pdfService.imagesToPdf(stableImages, outputPath, filter: _selectedFilter);
      
      final doc = ScannedDocument(
        id: DateTime.now().toIso8601String(),
        title: "$docType ${DateTime.now().hour}:${DateTime.now().minute}",
        filePath: outputPath,
        dateCreated: DateTime.now(),
        isPdf: true,
        documentType: docType,
      );

      await storage.saveDocument(doc);

      if (mounted) {
        HapticFeedback.vibrate();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => PdfViewerScreen(document: doc)),
        );
      }
    } catch (e, stackTrace) {
      debugPrint("SCAN CRASH: $e\n$stackTrace");
      if (mounted) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _documentScanner?.close();
    super.dispose();
  }

  Widget _buildModeItem(String label, IconData icon, ScanMode mode) {
    final isSelected = _selectedMode == mode;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedMode = mode;
          _idFrontPath = null;
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? Colors.indigo : Colors.transparent,
              shape: BoxShape.circle,
              boxShadow: isSelected ? [BoxShadow(color: Colors.indigo.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))] : [],
            ),
            child: Icon(icon, color: isSelected ? Colors.white : Colors.grey[600], size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.indigo : Colors.grey[600],
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterItem(String label, ScanFilter filter) {
    final isSelected = _selectedFilter == filter;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedFilter = filter);
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.indigo : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.indigo : Colors.grey.shade700,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 1. Background Content (Minimal Alignment Guides)
          if (!_isScanning)
            ScanGuideOverlay(
              width: _selectedMode == ScanMode.idCard ? 300 : 320,
              height: _selectedMode == ScanMode.idCard ? 190 : 240,
              label: _selectedMode == ScanMode.idCard 
                  ? (_idFrontPath == null ? "ALIGN ID FRONT" : "ALIGN ID BACK")
                  : _selectedMode == ScanMode.passport 
                      ? "ALIGN PASSPORT INFO"
                      : "ALIGN DOCUMENT",
            ),

          // 2. Top Floating Mode Selector
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 5))],
                border: Border.all(color: Colors.white),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildModeItem('Document', Icons.description_outlined, ScanMode.document),
                  _buildModeItem('ID Card', Icons.badge_outlined, ScanMode.idCard),
                  _buildModeItem('Passport', Icons.public_outlined, ScanMode.passport),
                ],
              ),
            ),
          ),

          // 3. Bottom HUD Panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 25, offset: const Offset(0, -5))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isScanning)
                    Column(
                      children: [
                        const CircularProgressIndicator(strokeWidth: 3),
                        const SizedBox(height: 20),
                        Text(
                          'ENHANCING SCAN QUALITY...',
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text('Using AI to sharpen text and remove shadows.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    )
                  else
                    Column(
                      children: [
                        // Filter Selection
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('SCAN FILTER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.grey)),
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildFilterItem('Original', ScanFilter.original),
                              _buildFilterItem('Enhanced ✨', ScanFilter.enhanced),
                              _buildFilterItem('Grayscale', ScanFilter.grayscale),
                              _buildFilterItem('Black & White', ScanFilter.blackAndWhite),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        Text(
                          _selectedMode == ScanMode.idCard && _idFrontPath != null
                              ? 'FRONT SIDE CAPTURED'
                              : 'READY TO SCAN',
                          style: TextStyle(fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.bold, color: Colors.indigo.shade400),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedMode == ScanMode.document
                              ? 'Automatic boundary detection enabled.'
                              : _selectedMode == ScanMode.idCard
                                  ? (_idFrontPath == null ? 'Center the front of your ID card.' : 'Great! Now capture the back side.')
                                  : 'Align the passport info page.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[700], fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 32),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _startScan,
                            icon: Icon(_selectedMode == ScanMode.idCard && _idFrontPath != null ? Icons.flip_rounded : Icons.camera_alt_rounded),
                            label: Text(
                              _selectedMode == ScanMode.idCard && _idFrontPath != null ? 'CAPTURE BACK SIDE' : 'START SCANNING',
                              style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 4,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
