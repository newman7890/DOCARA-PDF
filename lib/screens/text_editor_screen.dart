import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdfx/pdfx.dart' as dynamic_pdfx;
import '../models/scanned_document.dart';
import '../services/pdf_service.dart';
import '../services/storage_service.dart';
import '../services/ocr_service.dart';
import '../services/rich_text_service.dart';
import 'signature_pad_screen.dart';

class TextEditorScreen extends StatefulWidget {
  final ScannedDocument document;

  const TextEditorScreen({super.key, required this.document});

  @override
  State<TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends State<TextEditorScreen>
    with SingleTickerProviderStateMixin {
  final StyledTextController _controller = StyledTextController();
  dynamic_pdfx.PdfController? _pdfController;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _showReference = false;
  String _statusMessage = 'Analyzing Document...';
  List<Offset>? _signaturePoints;

  late AnimationController _overlayController;
  late Animation<double> _overlayAnimation;

  @override
  void initState() {
    super.initState();
    _pdfController = dynamic_pdfx.PdfController(
      document: dynamic_pdfx.PdfDocument.openFile(widget.document.filePath),
    );

    _overlayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _overlayAnimation = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeInOutCubic,
    );

    _extractText();
  }

  Future<void> _extractText() async {
    final pdfService = context.read<PDFService>();
    final ocrService = context.read<OCRService>();

    try {
      setState(() {
        _isLoading = true;
        _statusMessage = 'Enhancing & Extracting...';
      });

      String text;
      if (widget.document.extractedText != null &&
          widget.document.extractedText!.isNotEmpty) {
        text = widget.document.extractedText!;
        setState(() => _statusMessage = 'Loading saved text...');
      } else {
        text = await pdfService.extractTextFromPdf(
          widget.document.sourcePath ?? widget.document.filePath,
          ocrService: ocrService,
        );
      }

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _controller.text = text.trim().isEmpty
            ? '(No text detected. Enter your content here.)'
            : text;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _controller.text = '(Error during extraction: $e)';
      });
    }
  }

  Future<void> _saveAsPdf({bool silent = false}) async {
    if (_isSaving) return;

    final pdfService = context.read<PDFService>();
    final storageService = context.read<StorageService>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (!silent) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 10),
              Text('Review Changes'),
            ],
          ),
          content: const Text(
            'Please read through your changes carefully and make sure all edits are correct before saving.',
            style: TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Wait, let me check'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Yes, save now'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    setState(() {
      _isSaving = true;
      _statusMessage = 'Finalizing Document...';
    });

    try {
      final String currentTitle = widget.document.title;
      final bool alreadyCleaned = currentTitle.startsWith('Cleaned_');

      final String newTitle = alreadyCleaned
          ? currentTitle
          : 'Cleaned_$currentTitle';
      final String sourcePath =
          widget.document.sourcePath ?? widget.document.filePath;

      final newPath = alreadyCleaned
          ? widget.document.filePath
          : await storageService.getNewFilePath(
              newTitle.replaceAll('.pdf', ''),
            );

      await pdfService.saveTextAsPdf(
        _controller.text,
        newPath,
        title: newTitle.replaceAll('.pdf', ''),
        signaturePoints: _signaturePoints,
      );

      await storageService.saveDocument(
        widget.document.copyWith(
          title: newTitle,
          filePath: newPath,
          sourcePath: sourcePath,
          extractedText: _controller.text,
        ),
      );

      if (!mounted) return;
      if (!silent) {
        navigator.pop();

        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: const Text('✨ Document Refined & Saved Successfully!'),
            backgroundColor: Colors.indigo[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _toggleReference() {
    setState(() {
      _showReference = !_showReference;
      if (_showReference) {
        _overlayController.forward();
      } else {
        _overlayController.reverse();
      }
    });
  }

  void _fixOrdinals() {
    final text = _controller.text;
    final newText = text.replaceAllMapped(RegExp(r'\b(\d+)%'), (match) {
      final numStr = match.group(1)!;
      final num = int.parse(numStr);
      String suffix = 'th';
      if (num % 100 >= 11 && num % 100 <= 13) {
        suffix = 'th';
      } else {
        switch (num % 10) {
          case 1:
            suffix = 'st';
            break;
          case 2:
            suffix = 'nd';
            break;
          case 3:
            suffix = 'rd';
            break;
        }
      }
      return '$numStr$suffix';
    });

    if (newText != text) {
      _controller.text = newText;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fixed ordinals (e.g., 1st, 2nd)!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No misplaced percentages found.')),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _pdfController?.dispose();
    _overlayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFE),
      appBar: _buildAppBar(),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          // Auto-save on exit if text was changed or signature added
          bool hasChanges = _controller.text != widget.document.extractedText;
          if (_signaturePoints != null && _signaturePoints!.isNotEmpty) {
            hasChanges = true;
          }

          final navigator = Navigator.of(context);
          if (hasChanges) {
            await _saveAsPdf(silent: true);
          }
          if (mounted) {
            navigator.pop();
          }
        },
        child: Stack(
          children: [
            _isLoading ? _buildLoadingUI() : _buildEditorUI(),
            if (!_isLoading) _buildReferenceOverlay(),
          ],
        ),
      ),
      floatingActionButton: _isLoading ? null : _buildReferenceFAB(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.document.title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
          ),
          Text(
            'Text Extraction & Refinement',
            style: TextStyle(
              fontSize: 10,
              color: Colors.black.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      elevation: 0,
      centerTitle: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.share_outlined, size: 20),
          onPressed: () => Share.shareXFiles([XFile(widget.document.filePath)]),
        ),
        if (!_isLoading)
          TextButton.icon(
            onPressed: _isSaving ? null : _saveAsPdf,
            icon: _isSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high, size: 18),
            label: const Text(
              'REFINE',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: TextButton.styleFrom(foregroundColor: Colors.indigo[700]),
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildLoadingUI() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.indigo.withValues(alpha: 0.1),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: const CircularProgressIndicator(
              strokeWidth: 3,
              color: Colors.indigo,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            _statusMessage,
            style: TextStyle(
              color: Colors.indigo[900],
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Processing vectors and AI refinement...',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorUI() {
    return Column(
      children: [
        _buildModernToolbar(),
        const Divider(height: 1, color: Color(0xFFEEEEEE)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(
                fontSize: 17,
                height: 1.7,
                fontFamily: 'Inter',
                color: Color(0xFF2D3436),
                letterSpacing: 0.2,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Start writing your document...',
                hintStyle: TextStyle(color: Color(0xFFBDC3C7)),
              ),
            ),
          ),
        ),
        _buildWordCountBar(),
      ],
    );
  }

  Widget _buildModernToolbar() {
    return Container(
      height: 50,
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _toolIcon(Icons.undo_rounded, _controller.undo, 'Undo'),
            _toolIcon(Icons.redo_rounded, _controller.redo, 'Redo'),
            _vDiv(),
            _toolIcon(
              Icons.format_bold_rounded,
              _controller.toggleBold,
              'Bold',
            ),
            _toolIcon(
              Icons.format_italic_rounded,
              _controller.toggleItalic,
              'Italic',
            ),
            _toolIcon(
              Icons.format_underlined_rounded,
              _controller.toggleUnderline,
              'Underline',
            ),
            _vDiv(),
            _toolIcon(
              Icons.format_list_bulleted_rounded,
              _controller.toggleBulletList,
              'List',
            ),
            _vDiv(),
            _toolIcon(
              Icons.format_align_left_rounded,
              _controller.toggleLeftAlignment,
              'Left',
            ),
            _toolIcon(
              Icons.format_align_center_rounded,
              _controller.toggleCenterAlignment,
              'Center',
            ),
            _toolIcon(
              Icons.format_align_right_rounded,
              _controller.toggleRightAlignment,
              'Right',
            ),
            _vDiv(),
            _toolText('H1', _controller.toggleH1),
            _toolText('H2', _controller.toggleH2),
            _vDiv(),
            _toolText('Fix %', _fixOrdinals),
            _vDiv(),
            _toolIcon(Icons.draw_rounded, _openSignature, 'Sign'),
            _vDiv(),
            _toolIcon(
              Icons.text_fields_rounded,
              _controller.toggleFillableField,
              'Fillable Field',
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolIcon(IconData icon, VoidCallback onPressed, String tooltip) {
    return IconButton(
      icon: Icon(icon, size: 20, color: const Color(0xFF636E72)),
      onPressed: onPressed,
      tooltip: tooltip,
      splashRadius: 20,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _toolText(String label, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(40, 40),
        padding: EdgeInsets.zero,
        foregroundColor: const Color(0xFF636E72),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }

  Widget _vDiv() => const VerticalDivider(
    width: 24,
    indent: 15,
    endIndent: 15,
    color: Color(0xFFE0E0E0),
  );

  Widget _buildWordCountBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF1F1F1))),
      ),
      child: Row(
        children: [
          Text(
            '${_controller.text.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).length} words  •  ${_controller.text.length} chars',
            style: TextStyle(
              fontSize: 11,
              color: Colors.indigo[300],
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          const Icon(Icons.cloud_done_rounded, size: 14, color: Colors.green),
          const SizedBox(width: 4),
          Text(
            'Local Save Active',
            style: TextStyle(fontSize: 10, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildReferenceFAB() {
    return FloatingActionButton.extended(
      onPressed: _toggleReference,
      backgroundColor: _showReference ? Colors.red[400] : Colors.indigo[900],
      elevation: 4,
      icon: Icon(_showReference ? Icons.close : Icons.description_outlined),
      label: Text(_showReference ? 'Close View' : 'Original PDF'),
    );
  }

  Widget _buildReferenceOverlay() {
    return AnimatedBuilder(
      animation: _overlayAnimation,
      builder: (context, child) {
        if (_overlayAnimation.value == 0) return const SizedBox.shrink();

        return FadeTransition(
          opacity: _overlayAnimation,
          child: Stack(
            children: [
              // Blur background
              GestureDetector(
                onTap: _toggleReference,
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 5 * _overlayAnimation.value,
                    sigmaY: 5 * _overlayAnimation.value,
                  ),
                  child: Container(
                    color: Colors.black.withValues(
                      alpha: 0.1 * _overlayAnimation.value,
                    ),
                  ),
                ),
              ),

              // Floating Reference Card
              Center(
                child: ScaleTransition(
                  scale: _overlayAnimation,
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.85,
                    height: MediaQuery.of(context).size.height * 0.65,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.indigo.withValues(alpha: 0.1),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          color: const Color(0xFFF8F9FA),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.picture_as_pdf,
                                color: Colors.red,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Original Reference',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Use for visual verification',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: dynamic_pdfx.PdfView(
                            controller: _pdfController!,
                            scrollDirection: Axis.vertical,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openSignature() async {
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final points = await navigator.push<List<Offset>>(
      MaterialPageRoute(builder: (c) => const SignaturePadScreen()),
    );
    if (points != null && points.isNotEmpty && mounted) {
      setState(() => _signaturePoints = points);
      _controller.insertSignatureMarker();
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('✅ Signature captured and placed in document.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
