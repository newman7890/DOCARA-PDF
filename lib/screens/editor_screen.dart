import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdfx/pdfx.dart' as dynamic_pdfx;
import '../models/scanned_document.dart';
import '../models/pdf_edit_overlay.dart';
import '../services/pdf_editor_service.dart';
import '../services/storage_service.dart';
import '../services/pdf_service.dart';
import '../services/rich_text_service.dart';
import '../services/ocr_service.dart';

class EditorScreen extends StatefulWidget {
  final ScannedDocument document;

  const EditorScreen({super.key, required this.document});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  dynamic_pdfx.PdfDocument? _pdfDocument;
  dynamic_pdfx.PdfPageImage? _currentPageImage;
  int _currentPage = 1;
  int _totalPages = 0;
  bool _isLoading = true;

  List<Offset> _currentDrawingPath = [];
  List<PdfTextBlock>? _pageTextBlocks; // New field for text blocks

  @override
  void initState() {
    super.initState();
    // Reset tool selection and clear previous session edits
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final editor = context.read<PdfEditorService>();
      editor.setActiveTool(null);
      if (widget.document.overlayEdits != null) {
        editor.loadEdits(widget.document.overlayEdits!);
      } else {
        editor.clearAll();
      }
    });
    _loadPdf();
    _loadPageText(); // Load text blocks
  }

  Future<void> _loadPdf() async {
    try {
      _pdfDocument = await dynamic_pdfx.PdfDocument.openFile(
        widget.document.sourcePath ?? widget.document.filePath,
      );
      _totalPages = _pdfDocument!.pagesCount;
      await _renderPage(_currentPage);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load PDF: $e')));
      }
    }
  }

  Future<void> _loadPageText() async {
    try {
      final pdfService = context.read<PDFService>();
      final ocrService = context.read<OCRService>();
      final blocks = await pdfService.extractTextBlocksFromPdf(
        widget.document.sourcePath ?? widget.document.filePath,
        ocrService: ocrService,
      );
      if (mounted) {
        setState(() => _pageTextBlocks = blocks);
      }
    } catch (e) {
      debugPrint("Failed to load text blocks: $e");
    }
  }

  Future<void> _renderPage(int pageNumber) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final page = await _pdfDocument!.getPage(pageNumber);
    final image = await page.render(
      width: page.width * 2,
      height: page.height * 2,
      format: dynamic_pdfx.PdfPageImageFormat.jpeg,
    );
    await page.close();

    if (mounted) {
      context.read<PdfEditorService>().setCurrentPage(pageNumber);
      setState(() {
        _currentPageImage = image;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _pdfDocument?.close();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _totalPages) {
      _currentPage++;
      _currentDrawingPath = [];
      _renderPage(_currentPage);
    }
  }

  void _previousPage() {
    if (_currentPage > 1) {
      _currentPage--;
      _currentDrawingPath = [];
      _renderPage(_currentPage);
    }
  }

  void _editTextItem(
    BuildContext context,
    PdfEditorService editor,
    TextEditItem item,
  ) {
    final controller = StyledTextController()..text = item.text;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Text'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          style: TextStyle(
            fontSize: item.isH1
                ? 32
                : item.isH2
                ? 26
                : item.fontSize,
            fontWeight: (item.isBold || item.isH1 || item.isH2)
                ? FontWeight.bold
                : FontWeight.normal,
            fontStyle: item.isItalic ? FontStyle.italic : FontStyle.normal,
            decoration: TextDecoration.combine([
              if (item.isUnderline) TextDecoration.underline,
              if (item.isStrikethrough) TextDecoration.lineThrough,
            ]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              editor.deleteItem(item.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              editor.updateTextItem(item.id, newText: controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showImmediateTextDialog(
    BuildContext context,
    PdfEditorService editor,
    Offset position, {
    String initialText = "Enter text here",
    bool isH1 = false,
    bool isH2 = false,
  }) {
    final textController = TextEditingController(text: initialText);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.text_fields_rounded, color: Colors.indigo),
            SizedBox(width: 10),
            Text('Add Text to PDF', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Type something...',
            border: UnderlineInputBorder(),
          ),
          style: TextStyle(
            fontSize: isH1 ? 32 : (isH2 ? 26 : editor.currentFontSize),
            fontWeight: (isH1 || isH2 || editor.isBold)
                ? FontWeight.bold
                : FontWeight.normal,
            fontStyle: editor.isItalic ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (textController.text.isNotEmpty) {
                editor.addTextEdit(
                  position,
                  initialText: textController.text,
                  isH1: isH1,
                  isH2: isH2,
                );
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Add Text'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<PdfEditorService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit PDF'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo last edit',
            onPressed: () => context.read<PdfEditorService>().undo(),
          ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save edited PDF',
            onPressed: () => _savePdf(),
          ),
        ],
      ),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          final editor = context.read<PdfEditorService>();
          final navigator = Navigator.of(context);
          if (editor.edits.isNotEmpty) {
            // Auto-save silently on exit if there are edits
            await _savePdf(silent: true);
          }
          if (mounted) {
            navigator.pop();
          }
        },
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: SafeArea(
                      child: InteractiveViewer(
                        panEnabled:
                            editor.activeTool == null &&
                            editor.selectedItemId == null,
                        scaleEnabled:
                            editor.activeTool == null &&
                            editor.selectedItemId == null,
                        minScale: 0.5,
                        maxScale: 4.0,
                        child: Center(
                          child: _currentPageImage == null
                              ? const CircularProgressIndicator()
                              : AspectRatio(
                                  aspectRatio:
                                      (_currentPageImage!.width?.toDouble() ??
                                          1.0) /
                                      (_currentPageImage!.height?.toDouble() ??
                                          1.0),
                                  child: LayoutBuilder(
                                    builder: (_, constraints) {
                                      final W = constraints.maxWidth;
                                      final H = constraints.maxHeight;
                                      return Stack(
                                        children: [
                                          // Layer 1: PDF page image (cached, never repaints during drawing)
                                          Positioned.fill(
                                            child: RepaintBoundary(
                                              child: Image.memory(
                                                _currentPageImage!.bytes,
                                                fit: BoxFit.fill,
                                                gaplessPlayback: true,
                                              ),
                                            ),
                                          ),

                                          // Layer 2: Drawing strokes overlay (isolated repaint)
                                          Positioned.fill(
                                            child: RepaintBoundary(
                                              child: CustomPaint(
                                                isComplex: true,
                                                willChange: _currentDrawingPath
                                                    .isNotEmpty,
                                                painter: _OverlayPainter(
                                                  edits: editor.getEditsForPage(
                                                    _currentPage,
                                                  ),
                                                  currentDrawing:
                                                      _currentDrawingPath,
                                                  drawingColor:
                                                      editor.currentColor,
                                                  activeToolType:
                                                      editor.activeTool,
                                                ),
                                              ),
                                            ),
                                          ),

                                          // Layer 3: Text item widgets
                                          ...editor
                                              .getEditsForPage(_currentPage)
                                              .whereType<TextEditItem>()
                                              .map(
                                                (item) => Positioned(
                                                  left: item.position.dx * W,
                                                  top: item.position.dy * H,
                                                  child: GestureDetector(
                                                    behavior:
                                                        HitTestBehavior.opaque,
                                                    onTap: () => editor
                                                        .selectItem(item.id),
                                                    onPanUpdate:
                                                        editor.activeTool ==
                                                            null
                                                        ? (d) {
                                                            editor.updateItemPosition(
                                                              item.id,
                                                              Offset(
                                                                item
                                                                        .position
                                                                        .dx +
                                                                    d.delta.dx /
                                                                        W,
                                                                item
                                                                        .position
                                                                        .dy +
                                                                    d.delta.dy /
                                                                        H,
                                                              ),
                                                            );
                                                          }
                                                        : null,
                                                    onDoubleTap: () =>
                                                        _editTextItem(
                                                          context,
                                                          editor,
                                                          item,
                                                        ),
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical:
                                                                12, // Larger vertical target for mobile
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white
                                                            .withValues(
                                                              alpha: 0.01,
                                                            ), // Ensure hit detection
                                                        border: Border.all(
                                                          color:
                                                              editor.selectedItemId ==
                                                                  item.id
                                                              ? Colors.blue
                                                              : Colors
                                                                    .blueAccent
                                                                    .withValues(
                                                                      alpha:
                                                                          0.2,
                                                                    ),
                                                          width:
                                                              editor.selectedItemId ==
                                                                  item.id
                                                              ? 2
                                                              : 1,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                      ),
                                                      child: Text.rich(
                                                        StyledTextController.buildRichTextSpan(
                                                          item.text,
                                                          TextStyle(
                                                            color: item.color,
                                                            fontSize: item.isH1
                                                                ? 32
                                                                : item.isH2
                                                                ? 26
                                                                : item.fontSize,
                                                            fontWeight:
                                                                (item.isBold ||
                                                                    item.isH1 ||
                                                                    item.isH2)
                                                                ? FontWeight
                                                                      .bold
                                                                : FontWeight
                                                                      .normal,
                                                            fontStyle:
                                                                item.isItalic
                                                                ? FontStyle
                                                                      .italic
                                                                : FontStyle
                                                                      .normal,
                                                            decoration: TextDecoration.combine([
                                                              if (item
                                                                  .isUnderline)
                                                                TextDecoration
                                                                    .underline,
                                                              if (item
                                                                  .isStrikethrough)
                                                                TextDecoration
                                                                    .lineThrough,
                                                            ]),
                                                          ),
                                                        ),
                                                        textAlign:
                                                            item.textAlign,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),

                                          // Layer 4: Gesture capture — only when an edit tool is active
                                          if (editor.activeTool != null)
                                            Positioned.fill(
                                              child: GestureDetector(
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onPanStart: (d) {
                                                  if (editor.activeTool ==
                                                      EditType.drawing) {
                                                    setState(() {
                                                      _currentDrawingPath = [
                                                        Offset(
                                                          d.localPosition.dx /
                                                              W,
                                                          d.localPosition.dy /
                                                              H,
                                                        ),
                                                      ];
                                                    });
                                                  }
                                                },
                                                onPanUpdate: (d) {
                                                  if (editor.activeTool ==
                                                      EditType.drawing) {
                                                    setState(() {
                                                      _currentDrawingPath.add(
                                                        Offset(
                                                          d.localPosition.dx /
                                                              W,
                                                          d.localPosition.dy /
                                                              H,
                                                        ),
                                                      );
                                                    });
                                                  }
                                                },
                                                onPanEnd: (_) {
                                                  if (_currentDrawingPath
                                                      .isNotEmpty) {
                                                    editor.addDrawing(
                                                      List.from(
                                                        _currentDrawingPath,
                                                      ),
                                                    );
                                                    setState(
                                                      () =>
                                                          _currentDrawingPath =
                                                              [],
                                                    );
                                                  }
                                                },
                                                onTapUp: (d) {
                                                  if (editor.activeTool ==
                                                      EditType.text) {
                                                    // Immediate text entry
                                                    final pos = Offset(
                                                      d.localPosition.dx / W,
                                                      d.localPosition.dy / H,
                                                    );

                                                    // Identify paragraph at tap location
                                                    String initialText =
                                                        "Enter text here";
                                                    bool isH1 = false;
                                                    bool isH2 = false;

                                                    if (_pageTextBlocks !=
                                                        null) {
                                                      final pageBlocks =
                                                          _pageTextBlocks!
                                                              .where(
                                                                (b) =>
                                                                    b.pageIndex ==
                                                                    (_currentPage -
                                                                        1),
                                                              )
                                                              .toList();

                                                      // Find nearest block within a reasonable threshold
                                                      PdfTextBlock? nearest;
                                                      double minDist =
                                                          0.5; // threshold

                                                      for (var b
                                                          in pageBlocks) {
                                                        // Simple distance check in normalized space
                                                        // We assume Letter size (612x792) as a baseline for hit-testing
                                                        final dist =
                                                            (b.bounds.center.dx /
                                                                        612 -
                                                                    pos.dx)
                                                                .abs() +
                                                            (b.bounds.center.dy /
                                                                        792 -
                                                                    pos.dy)
                                                                .abs();
                                                        if (dist < minDist) {
                                                          minDist = dist;
                                                          nearest = b;
                                                        }
                                                      }
                                                      if (nearest != null) {
                                                        initialText = nearest
                                                            .text
                                                            .trim()
                                                            .replaceAll(
                                                              '\n',
                                                              ' ',
                                                            );
                                                        isH1 = nearest.isH1;
                                                        isH2 = nearest.isH2;
                                                      }
                                                    }

                                                    _showImmediateTextDialog(
                                                      context,
                                                      editor,
                                                      pos,
                                                      initialText: initialText,
                                                      isH1: isH1,
                                                      isH2: isH2,
                                                    );
                                                    editor.setActiveTool(null);
                                                  }
                                                },
                                              ),
                                            )
                                          else
                                            // Background tap to clear selection
                                            Positioned.fill(
                                              child: GestureDetector(
                                                behavior:
                                                    HitTestBehavior.translucent,
                                                onTap: () =>
                                                    editor.selectItem(null),
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  _buildToolbar(editor),
                ],
              ),
      ),
    );
  }

  Future<void> _savePdf({bool silent = false}) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final editorSession = context.read<PdfEditorService>();
    final pdfService = context.read<PDFService>();
    final storageService = context.read<StorageService>();

    if (!silent) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 10),
              Text('Review Changes'),
            ],
          ),
          content: const Text(
            'Please read through your changes carefully and make sure everything is correct and saved well before finalizing.',
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

    if (mounted) setState(() => _isLoading = true);
    try {
      final String currentTitle = widget.document.title;
      final bool alreadyEdited = currentTitle.startsWith('Edited_');

      final newTitle = alreadyEdited ? currentTitle : 'Edited_$currentTitle';

      final String sourcePath =
          widget.document.sourcePath ?? widget.document.filePath;

      final newPath = alreadyEdited
          ? widget.document.filePath
          : await storageService.getNewFilePath(
              newTitle.replaceAll('.pdf', ''),
            );

      await pdfService.flattenEditsToPdf(
        sourcePath,
        editorSession.edits,
        newPath,
      );

      final updatedDoc = widget.document.copyWith(
        title: newTitle,
        filePath: newPath,
        sourcePath: sourcePath,
        overlayEdits: editorSession.edits,
      );

      await storageService.saveDocument(updatedDoc);

      if (!mounted) return;
      if (!silent) {
        navigator.pop();
      }
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildToolbar(PdfEditorService editor) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Selection/Formatting sub-toolbar
            if (editor.selectedItemId != null || editor.activeTool != null)
              _buildFormattingOptions(editor),

            const Divider(height: 1),

            // Main tool buttons
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: _ToolButton(
                      icon: Icons.pan_tool_outlined,
                      label: 'Move',
                      isActive:
                          editor.activeTool == null &&
                          editor.selectedItemId == null,
                      onTap: () {
                        editor.setActiveTool(null);
                        editor.selectItem(null);
                      },
                    ),
                  ),
                  Expanded(
                    child: _ToolButton(
                      icon: Icons.text_fields_rounded,
                      label: 'Text',
                      isActive: editor.activeTool == EditType.text,
                      onTap: () => editor.setActiveTool(EditType.text),
                    ),
                  ),
                  Expanded(
                    child: _ToolButton(
                      icon: Icons.brush_rounded,
                      label: 'Draw',
                      isActive: editor.activeTool == EditType.drawing,
                      onTap: () => editor.setActiveTool(EditType.drawing),
                    ),
                  ),
                  Expanded(
                    child: _ToolButton(
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete',
                      isActive: false,
                      onTap: () {
                        if (editor.selectedItemId != null) {
                          editor.deleteItem(editor.selectedItemId!);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Page navigation
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: _previousPage,
                  ),
                  Text(
                    'Page $_currentPage of $_totalPages',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: _nextPage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormattingOptions(PdfEditorService editor) {
    final bool isText =
        editor.activeTool == EditType.text ||
        editor.selectedItem is TextEditItem;
    final bool isDraw =
        editor.activeTool == EditType.drawing ||
        editor.selectedItem is DrawingEditItem;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Column(
        children: [
          Row(
            children: [
              // Colors
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children:
                        [
                              Colors.black,
                              Colors.white, // Added for erasing/white-out
                              Colors.red,
                              Colors.blue,
                              Colors.green,
                              Colors.orange,
                              Colors.purple,
                            ]
                            .map(
                              (c) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: GestureDetector(
                                  onTap: () => editor.setColor(c),
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: c,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: editor.currentColor == c
                                            ? Colors.indigo
                                            : Colors.grey[300]!,
                                        width: editor.currentColor == c ? 2 : 1,
                                      ),
                                    ),
                                    child: editor.currentColor == c
                                        ? Icon(
                                            Icons.check,
                                            size: 14,
                                            color: c.computeLuminance() > 0.5
                                                ? Colors.black
                                                : Colors.white,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ),
              ),

              if (isText) ...[
                IconButton(
                  icon: Icon(
                    Icons.format_bold_rounded,
                    color: editor.isBold ? Colors.indigo : Colors.grey,
                  ),
                  onPressed: editor.toggleBold,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(
                    Icons.format_italic_rounded,
                    color: editor.isItalic ? Colors.indigo : Colors.grey,
                  ),
                  onPressed: editor.toggleItalic,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(
                    Icons.format_underlined_rounded,
                    color: editor.isUnderline ? Colors.indigo : Colors.grey,
                  ),
                  onPressed: editor.toggleUnderline,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(
                    Icons.format_strikethrough_rounded,
                    color: editor.isStrikethrough ? Colors.indigo : Colors.grey,
                  ),
                  onPressed: editor.toggleStrikethrough,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (isText) ...[
                const SizedBox(width: 8),
                const Text('Size:'),
                Expanded(
                  child: Slider(
                    value: editor.currentFontSize,
                    min: 8,
                    max: 48,
                    activeColor: Colors.indigo,
                    inactiveColor: Colors.indigo.withValues(alpha: 0.1),
                    onChanged: editor.setFontSize,
                  ),
                ),
              ],
              if (isDraw) ...[
                const Icon(Icons.line_weight_rounded, size: 20),
                const SizedBox(width: 8),
                const Text('Width:'),
                Expanded(
                  child: Slider(
                    value: editor.currentStrokeWidth,
                    min: 1,
                    max: 20,
                    activeColor: Colors.indigo,
                    inactiveColor: Colors.indigo.withValues(alpha: 0.1),
                    onChanged: editor.setStrokeWidth,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.indigo.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? Colors.indigo : Colors.grey[700],
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? Colors.indigo : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final List<PdfEditItem> edits;
  final List<Offset> currentDrawing;
  final Color drawingColor;
  final EditType? activeToolType;

  _OverlayPainter({
    required this.edits,
    required this.currentDrawing,
    required this.drawingColor,
    required this.activeToolType,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw committed strokes
    for (final edit in edits) {
      if (edit is DrawingEditItem && edit.points.length > 1) {
        final paint = Paint()
          ..color = edit.color
          ..strokeWidth = edit.strokeWidth
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

        for (int i = 0; i < edit.points.length - 1; i++) {
          canvas.drawLine(
            Offset(
              edit.points[i].dx * size.width,
              edit.points[i].dy * size.height,
            ),
            Offset(
              edit.points[i + 1].dx * size.width,
              edit.points[i + 1].dy * size.height,
            ),
            paint,
          );
        }
      }
    }

    // Draw current active stroke
    if (activeToolType == EditType.drawing && currentDrawing.length > 1) {
      final paint = Paint()
        ..color = drawingColor
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < currentDrawing.length - 1; i++) {
        canvas.drawLine(
          Offset(
            currentDrawing[i].dx * size.width,
            currentDrawing[i].dy * size.height,
          ),
          Offset(
            currentDrawing[i + 1].dx * size.width,
            currentDrawing[i + 1].dy * size.height,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) => true;
}
