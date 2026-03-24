import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OCRService {
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  /// Extracts text from an image file using ML Kit with recursive XY-cut and proximity joining.
  Future<String> extractTextFromImage(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final RecognizedText recognizedText = await _textRecognizer.processImage(
      inputImage,
    );

    final List<TextBlock> blocks = recognizedText.blocks.where((block) {
      final text = block.text.trim();
      // Filter out common OCR noise and phantom words
      if (text.length <= 4) {
        final lower = text.toLowerCase();
        if (RegExp(
          r'^[^a-z0-9]*(aah|ae|avoe|aa|ii|oo|uu|at)[^a-z0-9]*$',
        ).hasMatch(lower)) {
          return false;
        }
        if (RegExp(r'^[^a-zA-Z0-9]+$').hasMatch(text)) {
          return false; // Only symbols
        }
      }

      // Filter out blocks that are likely border noise (very close to edges)
      // This assumes a standard coordinate system from ML Kit
      return true;
    }).toList();

    if (blocks.isEmpty) return "";

    // Apply recursive XY-cut for intelligent layout sorting
    final List<TextBlock> sortedBlocks = _recursiveXYCut(blocks);

    // Calculate median line height for header detection heuristics
    final List<double> lineHeights = [];
    for (var b in sortedBlocks) {
      if (b.lines.isNotEmpty) {
        for (var l in b.lines) {
          lineHeights.add(l.boundingBox.height);
        }
      }
    }
    lineHeights.sort();
    final double medianHeight = lineHeights.isNotEmpty
        ? lineHeights[lineHeights.length ~/ 2]
        : 12.0;

    // Join blocks using proximity and smart sentence-joining logic to "close spaces"
    String result = "";
    for (int i = 0; i < sortedBlocks.length; i++) {
      final current = sortedBlocks[i];
      var text = current.text.trim();

      // Header Detection Heuristic
      final avgLineHeight =
          current.boundingBox.height /
          (current.lines.isNotEmpty ? current.lines.length : 1);

      // All Caps heuristic for headers
      bool isAllCaps =
          text.length >= 4 &&
          text == text.toUpperCase() &&
          RegExp(r'[A-Z]').hasMatch(text);

      if (avgLineHeight > medianHeight * 1.5) {
        text = "[H1] $text";
      } else if (avgLineHeight > medianHeight * 1.2 || isAllCaps) {
        text = "[H2] $text";
      }

      result += text;

      if (i < sortedBlocks.length - 1) {
        final next = sortedBlocks[i + 1];

        // Vertical proximity
        double verticalGap = next.boundingBox.top - current.boundingBox.bottom;
        // Same visual line check
        bool sameLine =
            (next.boundingBox.top - current.boundingBox.top).abs() <
            (current.boundingBox.height / 2);

        // Join with a space if it's on the same line OR if the line doesn't end in terminal punctuation
        bool endsInStop = RegExp(r'[.!?:]$').hasMatch(text);

        if (sameLine ||
            (!endsInStop && verticalGap < current.boundingBox.height * 1.5)) {
          result += " ";
        } else if (verticalGap < current.boundingBox.height * 1.5) {
          result += "\n";
        } else {
          result += "\n\n";
        }
      }
    }

    return result.trim();
  }

  /// Extracts blocks from an image for interactive use in the editor.
  Future<List<TextBlock>> extractBlocksFromImage(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final RecognizedText recognizedText = await _textRecognizer.processImage(
      inputImage,
    );
    return recognizedText.blocks;
  }

  /// True Recursive XY-Cut: Only splits if NO block spans across the cut line.
  List<TextBlock> _recursiveXYCut(List<TextBlock> blocks) {
    if (blocks.length <= 1) return blocks;

    // --- Try Horizontal Splits First ---
    blocks.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    for (int i = 0; i < blocks.length - 1; i++) {
      // Potential split between block i and i+1
      double splitY =
          (blocks[i].boundingBox.bottom + blocks[i + 1].boundingBox.top) / 2;

      // A split is "True" only if ZERO blocks intersect it
      bool isClearCut = true;
      for (var b in blocks) {
        if (b.boundingBox.top < splitY && b.boundingBox.bottom > splitY) {
          isClearCut = false;
          break;
        }
      }

      double gap = blocks[i + 1].boundingBox.top - blocks[i].boundingBox.bottom;
      if (isClearCut && gap > 1) {
        // Any clear gap is a valid horizontal split
        final top = blocks
            .where((b) => b.boundingBox.bottom <= splitY)
            .toList();
        final bottom = blocks
            .where((b) => b.boundingBox.top >= splitY)
            .toList();
        if (top.isNotEmpty && bottom.isNotEmpty) {
          return [..._recursiveXYCut(top), ..._recursiveXYCut(bottom)];
        }
      }
    }

    // --- Try Vertical Splits Next ---
    blocks.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));

    for (int i = 0; i < blocks.length - 1; i++) {
      double splitX =
          (blocks[i].boundingBox.right + blocks[i + 1].boundingBox.left) / 2;

      bool isClearCut = true;
      for (var b in blocks) {
        if (b.boundingBox.left < splitX && b.boundingBox.right > splitX) {
          isClearCut = false;
          break;
        }
      }

      double gap = blocks[i + 1].boundingBox.left - blocks[i].boundingBox.right;
      if (isClearCut && gap > 20) {
        // Larger gap required for columns (gutters)
        final left = blocks
            .where((b) => b.boundingBox.right <= splitX)
            .toList();
        final right = blocks
            .where((b) => b.boundingBox.left >= splitX)
            .toList();
        if (left.isNotEmpty && right.isNotEmpty) {
          return [..._recursiveXYCut(left), ..._recursiveXYCut(right)];
        }
      }
    }

    // Fallback: If no clear cut can be found, sort by standard reading order
    blocks.sort((a, b) {
      int cmp = a.boundingBox.top.compareTo(b.boundingBox.top);
      if (cmp != 0) return cmp;
      return a.boundingBox.left.compareTo(b.boundingBox.left);
    });

    return blocks;
  }

  void dispose() {
    _textRecognizer.close();
  }
}
