import 'package:flutter/material.dart';
import '../models/pdf_edit_overlay.dart';
import 'package:uuid/uuid.dart';

class PdfEditorService extends ChangeNotifier {
  final Map<int, List<PdfEditItem>> _edits = {};
  int _currentPageIndex = 1; // 1-based to match pdfx page numbering
  EditType? _activeTool; // null means selection mode

  // Tool settings
  Color _currentColor = Colors.red;
  double _currentStrokeWidth = 2.0;
  double _currentFontSize = 14.0;
  bool _isBold = false;
  bool _isItalic = false;
  bool _isUnderline = false;
  bool _isStrikethrough = false;
  bool _isH1 = false;
  bool _isH2 = false;
  TextAlign _textAlign = TextAlign.left;

  String? _selectedItemId;

  final _uuid = const Uuid();

  Map<int, List<PdfEditItem>> get edits => _edits;
  int get currentPageIndex => _currentPageIndex;
  EditType? get activeTool => _activeTool;
  Color get currentColor => _currentColor;
  double get currentStrokeWidth => _currentStrokeWidth;
  double get currentFontSize => _currentFontSize;
  bool get isBold => _isBold;
  bool get isItalic => _isItalic;
  bool get isUnderline => _isUnderline;
  bool get isStrikethrough => _isStrikethrough;
  bool get isH1 => _isH1;
  bool get isH2 => _isH2;
  TextAlign get textAlign => _textAlign;
  String? get selectedItemId => _selectedItemId;

  PdfEditItem? get selectedItem {
    if (_selectedItemId == null) return null;
    final items = _edits[_currentPageIndex];
    if (items == null) return null;
    try {
      return items.firstWhere((item) => item.id == _selectedItemId);
    } catch (_) {
      return null;
    }
  }

  void setCurrentPage(int index) {
    if (_currentPageIndex != index) {
      _currentPageIndex = index;
      _selectedItemId = null; // Clear selection on page change
      notifyListeners();
    }
  }

  void setActiveTool(EditType? tool) {
    _activeTool = tool;
    if (tool != null) {
      _selectedItemId = null; // Clear selection when tool is active
    }
    notifyListeners();
  }

  void selectItem(String? id) {
    _selectedItemId = id;
    if (id != null) {
      // Sync tool settings with selected item
      final items = _edits[_currentPageIndex];
      final item = items?.firstWhere((i) => i.id == id);
      if (item is TextEditItem) {
        _currentColor = item.color;
        _currentFontSize = item.fontSize;
        _isBold = item.isBold;
        _isItalic = item.isItalic;
        _isUnderline = item.isUnderline;
        _isStrikethrough = item.isStrikethrough;
        _isH1 = item.isH1;
        _isH2 = item.isH2;
        _textAlign = item.textAlign;
      } else if (item is DrawingEditItem) {
        _currentColor = item.color;
        _currentStrokeWidth = item.strokeWidth;
      }
    }
    notifyListeners();
  }

  void setColor(Color color) {
    _currentColor = color;
    final item = selectedItem;
    if (item is TextEditItem) {
      item.color = color;
    } else if (item is DrawingEditItem) {
      item.color = color;
    }
    notifyListeners();
  }

  void setFontSize(double size) {
    _currentFontSize = size;
    final item = selectedItem;
    if (item is TextEditItem) {
      item.fontSize = size;
    }
    notifyListeners();
  }

  void setStrokeWidth(double width) {
    _currentStrokeWidth = width;
    final item = selectedItem;
    if (item is DrawingEditItem) {
      item.strokeWidth = width;
    }
    notifyListeners();
  }

  void toggleBold() {
    _isBold = !_isBold;
    final item = selectedItem;
    if (item is TextEditItem) {
      item.isBold = _isBold;
    }
    notifyListeners();
  }

  void toggleItalic() {
    _isItalic = !_isItalic;
    final item = selectedItem;
    if (item is TextEditItem) {
      item.isItalic = _isItalic;
    }
    notifyListeners();
  }

  void toggleUnderline() {
    _isUnderline = !_isUnderline;
    final item = selectedItem;
    if (item is TextEditItem) {
      item.isUnderline = _isUnderline;
    }
    notifyListeners();
  }

  void toggleStrikethrough() {
    _isStrikethrough = !_isStrikethrough;
    final item = selectedItem;
    if (item is TextEditItem) {
      item.isStrikethrough = _isStrikethrough;
    }
    notifyListeners();
  }

  void toggleH1() {
    _isH1 = !_isH1;
    if (_isH1) _isH2 = false; // Mutually exclusive
    final item = selectedItem;
    if (item is TextEditItem) {
      item.isH1 = _isH1;
      if (_isH1) item.isH2 = false;
    }
    notifyListeners();
  }

  void toggleH2() {
    _isH2 = !_isH2;
    if (_isH2) _isH1 = false; // Mutually exclusive
    final item = selectedItem;
    if (item is TextEditItem) {
      item.isH2 = _isH2;
      if (_isH2) item.isH1 = false;
    }
    notifyListeners();
  }

  void setTextAlign(TextAlign alignment) {
    _textAlign = alignment;
    final item = selectedItem;
    if (item is TextEditItem) {
      item.textAlign = alignment;
    }
    notifyListeners();
  }

  List<PdfEditItem> getEditsForPage(int pageIndex) {
    return _edits[pageIndex] ?? [];
  }

  void addTextEdit(
    Offset localPosition, {
    String initialText = "Double tap to edit",
    bool? isH1,
    bool? isH2,
  }) {
    final newItem = TextEditItem(
      id: _uuid.v4(),
      pageIndex: _currentPageIndex,
      position: localPosition,
      text: initialText,
      color: _currentColor,
      fontSize: _currentFontSize,
      isBold: _isBold,
      isItalic: _isItalic,
      isUnderline: _isUnderline,
      isStrikethrough: _isStrikethrough,
      isH1: isH1 ?? _isH1,
      isH2: isH2 ?? _isH2,
      textAlign: _textAlign,
    );
    _addItem(newItem);
    selectItem(newItem.id);
  }

  void addDrawing(List<Offset> points) {
    if (points.isEmpty) return;
    final newItem = DrawingEditItem(
      id: _uuid.v4(),
      pageIndex: _currentPageIndex,
      points: points,
      color: _currentColor,
      strokeWidth: _currentStrokeWidth,
    );
    _addItem(newItem);
  }

  void updateTextItem(String id, {String? newText, Offset? newPosition}) {
    final items = _edits[_currentPageIndex];
    if (items != null) {
      final index = items.indexWhere((item) => item.id == id);
      if (index != -1 && items[index] is TextEditItem) {
        final item = items[index] as TextEditItem;
        if (newText != null) item.text = newText;
        if (newPosition != null) item.position = newPosition;
        notifyListeners();
      }
    }
  }

  void updateItemPosition(String id, Offset newPosition) {
    final items = _edits[_currentPageIndex];
    if (items != null) {
      final index = items.indexWhere((item) => item.id == id);
      if (index != -1) {
        items[index].position = newPosition;
        notifyListeners();
      }
    }
  }

  void deleteItem(String id) {
    final items = _edits[_currentPageIndex];
    if (items != null) {
      items.removeWhere((item) => item.id == id);
      if (_selectedItemId == id) _selectedItemId = null;
      notifyListeners();
    }
  }

  void undo() {
    final items = _edits[_currentPageIndex];
    if (items != null && items.isNotEmpty) {
      final removed = items.removeLast();
      if (_selectedItemId == removed.id) _selectedItemId = null;
      notifyListeners();
    }
  }

  void _addItem(PdfEditItem item) {
    _edits.putIfAbsent(item.pageIndex, () => []);
    _edits[item.pageIndex]!.add(item);
    notifyListeners();
  }

  void clearAll() {
    _edits.clear();
    _selectedItemId = null;
    notifyListeners();
  }

  void loadEdits(Map<int, List<PdfEditItem>> existingEdits) {
    _edits.clear();
    _edits.addAll(existingEdits);
    _selectedItemId = null;
    notifyListeners();
  }
}
