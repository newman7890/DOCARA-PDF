import 'package:flutter/material.dart';

/// A simple data model for a selection and text state.
class TextState {
  final String text;
  final TextSelection selection;

  TextState(this.text, this.selection);
}

/// A custom controller that handles basic real-time formatting visualization
/// and a robust Undo/Redo history stack.
class StyledTextController extends TextEditingController {
  final List<TextState> _undoStack = [];
  final List<TextState> _redoStack = [];
  bool _isHandlingUndoRedo = false;

  StyledTextController() {
    // Initial state
    _undoStack.add(TextState('', const TextSelection.collapsed(offset: 0)));
    addListener(_handleTextChange);
  }

  void _handleTextChange() {
    if (_isHandlingUndoRedo) return;

    final newState = TextState(text, selection);
    if (_undoStack.isEmpty || _undoStack.last.text != newState.text) {
      _undoStack.add(newState);
      if (_undoStack.length > 50) _undoStack.removeAt(0);
      _redoStack.clear();
    }
  }

  void undo() {
    if (_undoStack.length < 2) return;
    _isHandlingUndoRedo = true;
    _redoStack.add(_undoStack.removeLast());
    final prevState = _undoStack.last;
    value = TextEditingValue(
      text: prevState.text,
      selection: prevState.selection,
    );
    _isHandlingUndoRedo = false;
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _isHandlingUndoRedo = true;
    final nextState = _redoStack.removeLast();
    _undoStack.add(nextState);
    value = TextEditingValue(
      text: nextState.text,
      selection: nextState.selection,
    );
    _isHandlingUndoRedo = false;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return buildRichTextSpan(text, style);
  }

  /// Reusable rich text parser that handles bold, italic, underline, strikethrough,
  /// headers, lists, and color markers.
  static TextSpan buildRichTextSpan(String text, TextStyle? style) {
    if (text.isEmpty) return TextSpan(style: style);
    return _buildSpanRecursive(text, style);
  }

  static TextSpan _buildSpanRecursive(String text, TextStyle? style) {
    if (text.isEmpty) return TextSpan(style: style);

    final List<InlineSpan> children = [];
    final markerStyle = (style ?? const TextStyle()).copyWith(
      color: Colors.transparent,
      fontSize: 0.1, // Near-zero size to collapse space
      height: 0,
      letterSpacing: -1,
    );

    text.splitMapJoin(
      RegExp(
        r'(\*\*\*[\s\S]*?\*\*\*)|' // Bold+Italic (Triple)
        r'(\[(?:H1|h1)\][\s\S]*?\[/(?:H1|h1)\]|^\s*#\s+.*?$)|' // H1
        r'(\[(?:H2|h2)\][\s\S]*?\[/(?:H2|h2)\]|^\s*##\s+.*?$)|' // H2
        r'(\[(?:H3|h3)\][\s\S]*?\[/(?:H3|h3)\]|^\s*###\s+.*?$)|' // H3
        r'(\*\*[\s\S]*?\*\*)|' // Bold
        r'((?:__|_)[\s\S]*?(?:__|_))|' // Underline (Support __ or _)
        r'(\*[\s\S]*?\*)|' // Italic
        r'(~~[\s\S]*?~~)|' // Strike
        r'(^- .*?$|^- .*?\n)|' // Bullet
        r'(^\d+\. .*?$|^\d+\. .*?\n)|' // Numbered
        r'(^---+$|^---+\n)|' // HR
        r'(\[/?(?:H1|h1|H2|h2|H3|h3)\]|\*\*\*|\*\*|\*|__|~~|---+|#+|\[:[\s\S]*?:\]|(?<!\w)_(?!\w)|\[:/?field:\]|\[:sig:\])', // Markers
        multiLine: true,
      ),
      onMatch: (m) {
        final match = m.group(0)!;

        if (m.group(1) != null) {
          // *** Bold + Italic ***
          if (match.length >= 6) {
            final content = match.substring(3, match.length - 3);
            children.add(TextSpan(text: '***', style: markerStyle));
            children.add(
              _buildSpanRecursive(
                content,
                style?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                  color: Colors.black,
                ),
              ),
            );
            children.add(TextSpan(text: '***', style: markerStyle));
          } else {
            children.add(TextSpan(text: match, style: style));
          }
        } else if (m.group(2) != null) {
          // H1
          String content;
          String startMarker;
          String endMarker = '';
          if (match.toLowerCase().startsWith('[h1]')) {
            content = match.substring(4, match.length - 5);
            startMarker = match.substring(0, 4);
            endMarker = match.substring(match.length - 5);
          } else {
            final hashMatch = RegExp(r'^\s*#\s+').firstMatch(match)!;
            startMarker = hashMatch.group(0)!;
            content = match.substring(startMarker.length);
          }
          children.add(TextSpan(text: startMarker, style: markerStyle));
          children.add(
            _buildSpanRecursive(
              content,
              style?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 22,
                color: Colors.black,
              ),
            ),
          );
          if (endMarker.isNotEmpty) {
            children.add(TextSpan(text: endMarker, style: markerStyle));
          }
        } else if (m.group(3) != null) {
          // H2
          String content;
          String startMarker;
          String endMarker = '';
          if (match.toLowerCase().startsWith('[h2]')) {
            content = match.substring(4, match.length - 5);
            startMarker = match.substring(0, 4);
            endMarker = match.substring(match.length - 5);
          } else {
            final hashMatch = RegExp(r'^\s*##\s+').firstMatch(match)!;
            startMarker = hashMatch.group(0)!;
            content = match.substring(startMarker.length);
          }
          children.add(TextSpan(text: startMarker, style: markerStyle));
          children.add(
            _buildSpanRecursive(
              content,
              style?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.black,
              ),
            ),
          );
          if (endMarker.isNotEmpty) {
            children.add(TextSpan(text: endMarker, style: markerStyle));
          }
        } else if (m.group(4) != null) {
          // H3
          String content;
          String startMarker;
          String endMarker = '';
          if (match.toLowerCase().startsWith('[h3]')) {
            content = match.substring(4, match.length - 5);
            startMarker = match.substring(0, 4);
            endMarker = match.substring(match.length - 5);
          } else {
            final hashMatch = RegExp(r'^\s*###\s+').firstMatch(match)!;
            startMarker = hashMatch.group(0)!;
            content = match.substring(startMarker.length);
          }
          children.add(TextSpan(text: startMarker, style: markerStyle));
          children.add(
            _buildSpanRecursive(
              content,
              style?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black,
              ),
            ),
          );
          if (endMarker.isNotEmpty) {
            children.add(TextSpan(text: endMarker, style: markerStyle));
          }
        } else if (m.group(5) != null) {
          // ** Bold **
          if (match.length >= 4) {
            final content = match.substring(2, match.length - 2);
            children.add(TextSpan(text: '**', style: markerStyle));
            children.add(
              _buildSpanRecursive(
                content,
                (style ?? const TextStyle()).copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            );
            children.add(TextSpan(text: '**', style: markerStyle));
          } else {
            children.add(TextSpan(text: match, style: style));
          }
        } else if (m.group(6) != null) {
          // __ Underline __ or _ Underline _
          final isDouble = match.startsWith('__');
          final mLen = isDouble ? 2 : 1;
          if (match.length >= mLen * 2) {
            final content = match.substring(mLen, match.length - mLen);
            final marker = isDouble ? '__' : '_';

            children.add(TextSpan(text: marker, style: markerStyle));
            children.add(
              _buildSpanRecursive(
                content,
                (style ?? const TextStyle()).copyWith(
                  decoration: TextDecoration.underline,
                  color: Colors.black,
                ),
              ),
            );
            children.add(TextSpan(text: marker, style: markerStyle));
          } else {
            children.add(TextSpan(text: match, style: style));
          }
        } else if (m.group(7) != null) {
          // * Italic *
          if (match.length >= 2) {
            final content = match.substring(1, match.length - 1);
            children.add(TextSpan(text: '*', style: markerStyle));
            children.add(
              _buildSpanRecursive(
                content,
                (style ?? const TextStyle()).copyWith(
                  fontStyle: FontStyle.italic,
                  color: Colors.black,
                ),
              ),
            );
            children.add(TextSpan(text: '*', style: markerStyle));
          } else {
            children.add(TextSpan(text: match, style: style));
          }
        } else if (m.group(8) != null) {
          // ~~ Strike ~~
          if (match.length >= 4) {
            final content = match.substring(2, match.length - 2);
            children.add(TextSpan(text: '~~', style: markerStyle));
            children.add(
              _buildSpanRecursive(
                content,
                style?.copyWith(
                  decoration: TextDecoration.lineThrough,
                  color: Colors.black,
                ),
              ),
            );
            children.add(TextSpan(text: '~~', style: markerStyle));
          } else {
            children.add(TextSpan(text: match, style: style));
          }
        } else if (m.group(9) != null) {
          // Bullet
          children.add(
            TextSpan(
              text: '• ',
              style: (style ?? const TextStyle()).copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          );
          children.add(
            _buildSpanRecursive(
              match.substring(2),
              style?.copyWith(color: Colors.black),
            ),
          );
        } else if (m.group(10) != null) {
          // Numbered
          final dotIndex = match.indexOf('. ');
          children.add(
            TextSpan(
              text: match.substring(0, dotIndex + 2),
              style: (style ?? const TextStyle()).copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          );
          children.add(
            _buildSpanRecursive(
              match.substring(dotIndex + 2),
              style?.copyWith(color: Colors.black),
            ),
          );
        } else if (m.group(11) != null) {
          // HR
          children.add(
            WidgetSpan(
              child: Container(
                height: 1,
                width: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: 8),
                color: Colors.grey[400],
              ),
            ),
          );
          children.add(TextSpan(text: match, style: markerStyle));
        } else if (m.group(12) != null) {
          // Color / Meta
          if (match.startsWith('[:color:') && match.endsWith(':]')) {
            try {
              // Extract dynamically based on length, preventing out of bounds on short strings
              final hexColor = match.substring(8, match.length - 2);
              final color = Color(
                int.parse(hexColor.replaceFirst('#', '0xFF')),
              );
                children.add(
                  TextSpan(
                    text: match,
                    style: markerStyle.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                      decorationColor: color,
                    ),
                  ),
                );
              } catch (_) {
                children.add(TextSpan(text: match, style: style));
              }
          } else if (match.startsWith('[:left:]') ||
              match.startsWith('[:center:]') ||
              match.startsWith('[:right:]')) {
            children.add(TextSpan(text: match, style: markerStyle));          } else if (match == '[:sig:]') {
            children.add(
              TextSpan(
                text: '[:sig:]',
                style: markerStyle.copyWith(
                  color: Colors.indigo,
                  fontWeight: FontWeight.bold,
                  backgroundColor: Colors.indigo.withAlpha(30),
                ),
              ),
            );
          } else {
            children.add(TextSpan(text: match, style: markerStyle));
          }
        }
        return '';
      },
      onNonMatch: (s) {
        children.add(TextSpan(text: s, style: style));
        return '';
      },
    );

    return TextSpan(style: style, children: children);
  }

  void toggleBold() {
    _wrapSelection('**', '**');
  }

  void toggleItalic() {
    _wrapSelection('*', '*');
  }

  void toggleUnderline() {
    _wrapSelection('__', '__');
  }

  void toggleStrikethrough() {
    _wrapSelection('~~', '~~');
  }

  void setAlignment(String alignment) {
    // alignment can be 'left', 'center', 'right'
    final marker = '[:$alignment:]';
    _toggleLineStart(
      marker,
      replaceOthers: ['[:left:]', '[:center:]', '[:right:]'],
    );
  }

  void toggleBulletList() {
    _toggleLineStart('- ');
  }

  void toggleNumberedList() {
    _toggleLineStart('1. ');
  }

  void toggleLeftAlignment() {
    if (!selection.isCollapsed) {
      _wrapSelection('[:left:]', '');
      return;
    }
    _toggleLineStart(
      '[:left:]',
      replaceOthers: [
        '[:center:]',
        '[:right:]',
        '# ',
        '## ',
        '### ',
      ],
    );
  }

  void toggleCenterAlignment() {
    if (!selection.isCollapsed) {
      _wrapSelection('[:center:]', '[:left:]');
      return;
    }
    _toggleLineStart(
      '[:center:]',
      replaceOthers: [
        '[:left:]',
        '[:right:]',
        '# ',
        '## ',
        '### ',
      ],
    );
  }

  void toggleRightAlignment() {
    if (!selection.isCollapsed) {
      _wrapSelection('[:right:]', '[:left:]');
      return;
    }
    _toggleLineStart(
      '[:right:]',
      replaceOthers: [
        '[:left:]',
        '[:center:]',
        '# ',
        '## ',
        '### ',
      ],
    );
  }

  void toggleFillableField() {
    _wrapSelection('[:field:]', '[:/field:]');
  }

  void insertHorizontalRule() {
    final curSelection = selection.isValid
        ? selection
        : TextSelection.collapsed(offset: text.length);
    final curText = text;
    final newText = curText.replaceRange(
      curSelection.start,
      curSelection.end,
      '\n---\n',
    );
    value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: curSelection.start + 5),
    );
  }

  void setTextColor(Color color) {
    final hex =
        '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    _toggleLineStart('[:color:$hex:]');
  }

  void toggleH1() {
    _toggleLineStart(
      '# ',
      replaceOthers: [
        '## ',
        '### ',
        '- ',
        '1. ',
        '[:left:]',
        '[:center:]',
        '[:right:]',
      ],
    );
  }

  void insertSignatureMarker() {
    final curSelection = selection.isValid
        ? selection
        : TextSelection.collapsed(offset: text.length);
    final curText = text;
    final marker = '[:sig:]';

    // Insert at selection, or at end if no selection
    final newText = curText.replaceRange(
      curSelection.start,
      curSelection.end,
      marker,
    );
    value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: curSelection.start + marker.length,
      ),
    );
  }

  void toggleH2() {
    _toggleLineStart(
      '## ',
      replaceOthers: [
        '# ',
        '### ',
        '- ',
        '1. ',
        '[:left:]',
        '[:center:]',
        '[:right:]',
      ],
    );
  }

  void toggleH3() {
    _toggleLineStart(
      '### ',
      replaceOthers: [
        '# ',
        '## ',
        '- ',
        '1. ',
        '[:left:]',
        '[:center:]',
        '[:right:]',
      ],
    );
  }

  void _wrapSelection(String prefix, String suffix) {
    if (!selection.isValid) return;

    final curSelection = selection;
    final curText = text;

    // 1. Check if the selection is already wrapped from OUTSIDE
    if (curSelection.start >= prefix.length &&
        curSelection.end <= curText.length - suffix.length) {
      final textBefore = curText.substring(
        curSelection.start - prefix.length,
        curSelection.start,
      );
      final textAfter = curText.substring(
        curSelection.end,
        curSelection.end + suffix.length,
      );
      if (textBefore == prefix && textAfter == suffix) {
        final newText = curText.replaceRange(
          curSelection.end,
          curSelection.end + suffix.length,
          '',
        );
        final finalText = newText.replaceRange(
          curSelection.start - prefix.length,
          curSelection.start,
          '',
        );
        value = TextEditingValue(
          text: finalText,
          selection: TextSelection(
            baseOffset: curSelection.start - prefix.length,
            extentOffset: curSelection.end - prefix.length,
          ),
        );
        return;
      }
    }

    // 2. NEW Smart Check: Is the selection INSIDE a larger block of the same type?
    // Find the nearest surrounding prefix/suffix
    int searchStart = curSelection.start;
    int searchEnd = curSelection.end;

    // Look backwards for prefix
    int prefixPos = -1;
    for (int i = searchStart - prefix.length; i >= 0; i--) {
      if (curText.substring(i, i + prefix.length) == prefix) {
        prefixPos = i;
        break;
      }
      if (curText[i] == '\n') {
        break; // Don't search across lines for simple styles
      }
    }

    // Look forwards for suffix
    int suffixPos = -1;
    if (prefixPos != -1) {
      for (int i = searchEnd; i <= curText.length - suffix.length; i++) {
        if (curText.substring(i, i + suffix.length) == suffix) {
          suffixPos = i;
          break;
        }
        if (curText[i] == '\n') break;
      }
    }

    if (prefixPos != -1 && suffixPos != -1) {
      // Toggle OFF by splitting or simply removing if it's the whole line
      // For simplicity in this UI, we just remove the outer ones if they exist
      final newText = curText.replaceRange(
        suffixPos,
        suffixPos + suffix.length,
        '',
      );
      final finalText = newText.replaceRange(
        prefixPos,
        prefixPos + prefix.length,
        '',
      );

      value = TextEditingValue(
        text: finalText,
        selection: TextSelection(
          baseOffset: curSelection.start - prefix.length,
          extentOffset: curSelection.end - prefix.length,
        ),
      );
      return;
    }

    // 3. Check if the selection is already wrapped from INSIDE
    final selectedText = curSelection.textInside(curText);
    if (selectedText.startsWith(prefix) &&
        selectedText.endsWith(suffix) &&
        selectedText.length >= (prefix.length + suffix.length)) {
      final unwrapped = selectedText.substring(
        prefix.length,
        selectedText.length - suffix.length,
      );
      final newText = curText.replaceRange(
        curSelection.start,
        curSelection.end,
        unwrapped,
      );
      value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: curSelection.start,
          extentOffset: curSelection.start + unwrapped.length,
        ),
      );
      return;
    }

    // 4. Apply Multi-paragraph wrapping logic
    final isInlineStyle = prefix == '**' ||
        prefix == '*' ||
        prefix == '__' ||
        prefix == '~~' ||
        prefix == '***' ||
        prefix.startsWith('[:color:');

    if (!curSelection.isCollapsed && selectedText.contains('\n')) {
      if (isInlineStyle) {
        // For inline styles, wrap the ENTIRE block as one, not line by line
        final wrapped = '$prefix$selectedText$suffix';
        final newText = curText.replaceRange(
          curSelection.start,
          curSelection.end,
          wrapped,
        );
        value = TextEditingValue(
          text: newText,
          selection: TextSelection(
            baseOffset: curSelection.start,
            extentOffset: curSelection.start + wrapped.length,
          ),
        );
        return;
      }

      final lines = selectedText.split('\n');
      final wrappedLines = lines
          .map((line) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) return line;
            if (trimmed.startsWith(prefix) && trimmed.endsWith(suffix)) {
              return line;
            }
            return '$prefix$line$suffix';
          })
          .join('\n');

      final newText = curText.replaceRange(
        curSelection.start,
        curSelection.end,
        wrappedLines,
      );
      value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: curSelection.start,
          extentOffset: curSelection.start + wrappedLines.length,
        ),
      );
      return;
    }

    // 5. Default single-wrapping (includes empty selection)
    if (curSelection.isCollapsed) {
      final newText = curText.replaceRange(
        curSelection.start,
        curSelection.end,
        '$prefix$suffix',
      );
      value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: curSelection.start + prefix.length,
        ),
      );
    } else {
      final wrapped = '$prefix$selectedText$suffix';
      final newText = curText.replaceRange(
        curSelection.start,
        curSelection.end,
        wrapped,
      );
      value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: curSelection.start,
          extentOffset: curSelection.start + wrapped.length,
        ),
      );
    }
  }

  void _toggleLineStart(String marker, {List<String>? replaceOthers}) {
    final curSelection = selection.isValid
        ? selection
        : TextSelection.collapsed(offset: text.length);
    final curText = text;

    // Find start of line
    int lineStart = 0;
    for (int i = curSelection.start - 1; i >= 0; i--) {
      if (curText[i] == '\n') {
        lineStart = i + 1;
        break;
      }
    }

    String lineContent = curText.substring(lineStart);

    // Check if the current marker already exists
    if (lineContent.startsWith(marker)) {
      // Remove existing marker
      final newText = curText.replaceRange(
        lineStart,
        lineStart + marker.length,
        '',
      );
      value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: (curSelection.start - marker.length).clamp(0, newText.length),
        ),
      );
      return;
    }

    // Check if any of the replaceOthers markers exist
    String? foundOther;
    if (replaceOthers != null) {
      for (final other in replaceOthers) {
        if (lineContent.startsWith(other)) {
          foundOther = other;
          break;
        }
      }
    }

    if (foundOther != null) {
      // Replace existing marker with new one
      final removedText = curText.replaceRange(
        lineStart,
        lineStart + foundOther.length,
        '',
      );
      final finalText = removedText.replaceRange(lineStart, lineStart, marker);
      value = TextEditingValue(
        text: finalText,
        selection: TextSelection.collapsed(
          offset: (curSelection.start - foundOther.length + marker.length)
              .clamp(0, finalText.length),
        ),
      );
    } else {
      // Add new marker
      final finalText = curText.replaceRange(lineStart, lineStart, marker);
      value = TextEditingValue(
        text: finalText,
        selection: TextSelection.collapsed(
          offset: (curSelection.start + marker.length).clamp(
            0,
            finalText.length,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    removeListener(_handleTextChange);
    super.dispose();
  }
}
