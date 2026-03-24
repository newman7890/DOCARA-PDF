import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OCRTableService {
  final _textRecognizer = TextRecognizer();

  Future<List<List<String>>> scanTable(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final recognizedText = await _textRecognizer.processImage(inputImage);

    if (recognizedText.blocks.isEmpty) return [];

    // Group text lines into rows based on Y-coordinate similarity
    final List<TextLine> allLines = [];
    for (var block in recognizedText.blocks) {
      for (var line in block.lines) {
        allLines.add(line);
      }
    }

    // Sort by Y-coordinate
    allLines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    final List<List<TextLine>> rowsOfLines = [];
    if (allLines.isNotEmpty) {
      List<TextLine> currentRow = [allLines.first];
      for (int i = 1; i < allLines.length; i++) {
        final line = allLines[i];
        final prevLine = allLines[i - 1];
        
        // If Y-coordinate difference is small, they are in the same row
        if ((line.boundingBox.top - prevLine.boundingBox.top).abs() < 15) {
          currentRow.add(line);
        } else {
          rowsOfLines.add(currentRow);
          currentRow = [line];
        }
      }
      rowsOfLines.add(currentRow);
    }

    // Sort each row by X-coordinate
    final List<List<String>> finalData = [];
    for (var row in rowsOfLines) {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      finalData.add(row.map((line) => line.text).toList());
    }

    return finalData;
  }

  void dispose() {
    _textRecognizer.close();
  }
}
