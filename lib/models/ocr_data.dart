import 'dart:ui';
import 'dart:math';

/// Custom OCR data models to replace google_mlkit_text_recognition dependency.

class TextBlock {
  final String text;
  final List<TextLine> lines;
  final Rect boundingBox;
  final List<Point<int>> cornerPoints;
  final List<String> recognizedLanguages;

  TextBlock({
    required this.text,
    required this.lines,
    required this.boundingBox,
    required this.cornerPoints,
    this.recognizedLanguages = const [],
  });
}

class TextLine {
  final String text;
  final List<TextElement> elements;
  final Rect boundingBox;
  final List<Point<int>> cornerPoints;
  final List<String> recognizedLanguages;
  final double confidence;
  final double angle;

  TextLine({
    required this.text,
    required this.elements,
    required this.boundingBox,
    required this.cornerPoints,
    this.recognizedLanguages = const [],
    this.confidence = 1.0,
    this.angle = 0.0,
  });
}

class TextElement {
  final String text;
  final Rect boundingBox;
  final List<Point<int>> cornerPoints;
  final double confidence;

  TextElement({
    required this.text,
    required this.boundingBox,
    required this.cornerPoints,
    this.confidence = 1.0,
  });
}
