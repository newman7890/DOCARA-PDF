import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:share_plus/share_plus.dart';
import '../models/scanned_document.dart';
import '../services/pdf_service.dart';
import '../services/ocr_service.dart';
import '../services/tts_service.dart';
import '../services/translation_service.dart';
import 'editor_screen.dart';
import 'package:provider/provider.dart';

class PdfViewerScreen extends StatefulWidget {
  final ScannedDocument document;

  const PdfViewerScreen({super.key, required this.document});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final PdfViewerController _pdfViewerController = PdfViewerController();
  bool _isExtracting = false;
  String? _lastHighlightedSentence;
  bool _isReading = false;
  String _targetLanguage = 'en';
  bool _isTranslating = false;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _copyAllText() async {
    setState(() => _isExtracting = true);
    try {
      final pdfService = context.read<PDFService>();
      final ocrService = context.read<OCRService>();
      final text = await pdfService.extractTextFromPdf(
        widget.document.filePath,
        ocrService: ocrService,
      );
      if (text.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No text found.')));
      } else {
        await Clipboard.setData(ClipboardData(text: text));
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Copied!')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Extraction failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _isExtracting = false);
      }
    }
  }

  Future<void> _toggleReadAloud() async {
    final ttsService = context.read<TTSService>();
    final translationService = context.read<TranslationService>();

    if (ttsService.isPlaying) {
      await ttsService.pause();
      if (mounted) {
        setState(() {});
      }
      return;
    }

    if (ttsService.canResume(widget.document.filePath)) {
      await ttsService.resume();
      if (mounted) {
        setState(() {});
      }
      return;
    }

    // Starting new playback
    setState(() => _isReading = true);

    try {
      final pdfService = context.read<PDFService>();
      final ocrService = context.read<OCRService>();

      final text = await pdfService.extractTextFromPdf(
        widget.document.filePath,
        ocrService: ocrService,
      );

      if (text.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No text to read.')));
      } else {
        String finalOutput = text;
        
        // Translation logic
        if (_targetLanguage != 'source') { // 'source' means original
           setState(() => _isTranslating = true);
           if (!mounted) return;
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Translating... on-device AI is working.'), duration: Duration(seconds: 2)),
           );
           finalOutput = await translationService.translate(
             text: text, 
             targetLanguageCode: _targetLanguage,
           );
           // Set TTS voice to match target language
           ttsService.setLanguage(_mapCodeToTtsLocale(_targetLanguage));
           setState(() => _isTranslating = false);
        } else {
           ttsService.setLanguage("en-US"); // Default for original
        }

        await ttsService.speak(finalOutput, filePath: widget.document.filePath);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      // The provided snippet seems to be for a different context (e.g., navigating from Editor to Viewer).
      // Applying the imageCache.clear() as requested, but not the navigation or undefined variables.
      PaintingBinding.instance.imageCache.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Playback failed: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isReading = false;
          _isTranslating = false;
        });
      }
    }
  }

  Future<void> _onLanguageSelected(String code) async {
    final ttsService = context.read<TTSService>();
    final wasPlaying = ttsService.isPlaying || ttsService.isPaused;

    setState(() => _targetLanguage = code);

    if (wasPlaying) {
      await ttsService.stop(); 
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switching to ${_mapCodeToLanguageName(code)} in 2 seconds...'), 
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.blue.shade700,
        ),
      );
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        await _toggleReadAloud();
      }
    }
  }

  String _mapCodeToLanguageName(String code) {
    switch (code) {
      case 'en': return 'English';
      case 'es': return 'Spanish';
      case 'fr': return 'French';
      case 'de': return 'German';
      case 'it': return 'Italian';
      case 'pt': return 'Portuguese';
      case 'ru': return 'Russian';
      case 'zh': return 'Chinese';
      case 'ja': return 'Japanese';
      case 'ko': return 'Korean';
      default: return 'Original Language';
    }
  }

  String _mapCodeToTtsLocale(String code) {
    switch (code) {
      case 'es': return 'es-ES';
      case 'fr': return 'fr-FR';
      case 'de': return 'de-DE';
      case 'it': return 'it-IT';
      case 'pt': return 'pt-BR';
      case 'ru': return 'ru-RU';
      case 'zh': return 'zh-CN';
      case 'ja': return 'ja-JP';
      case 'ko': return 'ko-KR';
      case 'ar': return 'ar-SA';
      case 'hi': return 'hi-IN';
      default: return 'en-US';
    }
  }

  void _onSentenceChanged(String sentence) {
    if (sentence.isNotEmpty && sentence != _lastHighlightedSentence) {
      _lastHighlightedSentence = sentence;
      _pdfViewerController.clearSelection();
      
      // Starting search for the sentence
      final result = _pdfViewerController.searchText(sentence);
      
      // Ensuring it jumps to the result (Syncfusion usually does this on first instance)
      // but we force a check to be sure it's visible.
      result.addListener(() {
        if (result.hasResult && result.currentInstanceIndex == 0) {
           // This forces the viewer to focus on the first found instance
           result.nextInstance();
        }
      });
    }
  }


  Future<void> _export() async {
    try {
      await Share.shareXFiles([
        XFile(widget.document.filePath),
      ], text: widget.document.title);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  @override
  void dispose() {
    context.read<TTSService>().stop();
    _pdfViewerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ttsService = context.watch<TTSService>();
    final currentSentence = ttsService.currentSentence;
    if (currentSentence != null && ttsService.isPlaying) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onSentenceChanged(currentSentence);
      });
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade200,
      appBar: AppBar(
        title: Text(
          widget.document.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.grey.shade900,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.translate_rounded),
            tooltip: 'Translation Language',
            initialValue: _targetLanguage,
            onSelected: _onLanguageSelected,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'source', child: Text('Original Language')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'en', child: Text('English')),
              const PopupMenuItem(value: 'es', child: Text('Spanish')),
              const PopupMenuItem(value: 'fr', child: Text('French')),
              const PopupMenuItem(value: 'de', child: Text('German')),
              const PopupMenuItem(value: 'it', child: Text('Italian')),
              const PopupMenuItem(value: 'pt', child: Text('Portuguese')),
              const PopupMenuItem(value: 'ru', child: Text('Russian')),
              const PopupMenuItem(value: 'zh', child: Text('Chinese')),
              const PopupMenuItem(value: 'ja', child: Text('Japanese')),
              const PopupMenuItem(value: 'ko', child: Text('Korean')),
            ],
          ),
          PopupMenuButton<double>(
            icon: const Icon(Icons.speed_rounded),
            tooltip: 'Playback Speed',
            onSelected: (speed) => context.read<TTSService>().setSpeed(speed),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 0.5, child: Text('0.5x (Slow)')),
              const PopupMenuItem(value: 0.75, child: Text('0.75x')),
              const PopupMenuItem(value: 1.0, child: Text('1.0x (Normal)')),
              const PopupMenuItem(value: 1.25, child: Text('1.25x')),
              const PopupMenuItem(value: 1.5, child: Text('1.5x (Fast)')),
              const PopupMenuItem(value: 2.0, child: Text('2.0x (Turbo)')),
            ],
          ),
          if (context.watch<TTSService>().state != TTSState.idle) ...[
            IconButton(
              icon: const Icon(Icons.replay_10_rounded),
              onPressed: () => context.read<TTSService>().seekBackward(),
              tooltip: 'Go back',
            ),
          ],
          IconButton(
            icon: (_isReading || _isTranslating)
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _isTranslating ? Colors.blueAccent : Colors.redAccent,
                    ),
                  )
                : Icon(
                    context.watch<TTSService>().isPlaying 
                        ? Icons.pause_circle_rounded 
                        : Icons.play_circle_rounded,
                    color: context.watch<TTSService>().isPaused ? Colors.orangeAccent : Colors.white,
                    size: 28,
                  ),
            onPressed: _toggleReadAloud,
            tooltip: context.read<TTSService>().isPlaying ? 'Pause' : 'Read Aloud',
          ),
          if (context.watch<TTSService>().state != TTSState.idle) ...[
            IconButton(
              icon: const Icon(Icons.forward_10_rounded),
              onPressed: () => context.read<TTSService>().seekForward(),
              tooltip: 'Skip ahead',
            ),
          ],
          IconButton(
            icon: _isExtracting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.copy_all_rounded),
            onPressed: _isExtracting ? null : _copyAllText,
            tooltip: 'Copy all text',
          ),
          IconButton(
            icon: const Icon(Icons.edit_note_rounded),
            tooltip: 'Edit PDF',
            onPressed: () async {
              final navigator = Navigator.of(context);
              
              // Clear cache before transitioning to free up RAM for the Editor
              if (mounted) {
                setState(() => _isClosing = true);
              }
              
              // Give the OS 200ms to fully detach the native SfPdfViewer surfaces
              await Future.delayed(const Duration(milliseconds: 200));

              if (!mounted) return;
              
              PaintingBinding.instance.imageCache.clear();
              navigator.pushReplacement(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => EditorScreen(document: widget.document),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                  settings: const RouteSettings(name: '/editor'),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: _export,
            tooltip: 'Share document',
          ),
        ],
      ),
      body: _isClosing 
        ? const SizedBox.expand()
        : Column(
            children: [
          Expanded(
            child: SfPdfViewer.file(
              File(widget.document.filePath),
              controller: _pdfViewerController,
              enableTextSelection: true,
            ),
          ),
          if (currentSentence != null && ttsService.isPlaying)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.black87,
              child: Text(
                currentSentence,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.yellowAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}
