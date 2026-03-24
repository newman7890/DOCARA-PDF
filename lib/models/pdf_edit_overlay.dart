import 'package:flutter/material.dart';

enum EditType { text, drawing }

abstract class PdfEditItem {
  final String id;
  final int pageIndex;
  final EditType type;
  Offset position; // Position relative to PDF page

  PdfEditItem({
    required this.id,
    required this.pageIndex,
    required this.type,
    required this.position,
  });

  Map<String, dynamic> toMap();

  static PdfEditItem fromMap(Map<String, dynamic> map) {
    final type = EditType.values.firstWhere((e) => e.toString() == map['type']);
    if (type == EditType.text) {
      return TextEditItem.fromMap(map);
    } else {
      return DrawingEditItem.fromMap(map);
    }
  }
}

class TextEditItem extends PdfEditItem {
  String text;
  double fontSize;
  Color color;
  double width;
  bool isBold;
  bool isItalic;
  bool isUnderline;
  bool isStrikethrough;
  bool isH1;
  bool isH2;
  TextAlign textAlign;

  TextEditItem({
    required super.id,
    required super.pageIndex,
    required super.position,
    required this.text,
    this.fontSize = 14.0,
    this.color = Colors.black,
    this.width = 150.0,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.isStrikethrough = false,
    this.isH1 = false,
    this.isH2 = false,
    this.textAlign = TextAlign.left,
  }) : super(type: EditType.text);

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pageIndex': pageIndex,
      'type': type.toString(),
      'x': position.dx,
      'y': position.dy,
      'text': text,
      'fontSize': fontSize,
      'colorValue': color.toARGB32(),
      'width': width,
      'isBold': isBold,
      'isItalic': isItalic,
      'isUnderline': isUnderline,
      'isStrikethrough': isStrikethrough,
      'isH1': isH1,
      'isH2': isH2,
      'textAlign': textAlign.index,
    };
  }

  factory TextEditItem.fromMap(Map<String, dynamic> map) {
    return TextEditItem(
      id: map['id'],
      pageIndex: map['pageIndex'],
      position: Offset(map['x'], map['y']),
      text: map['text'],
      fontSize: map['fontSize'].toDouble(),
      color: Color(map['colorValue']),
      width: map['width'].toDouble(),
      isBold: map['isBold'],
      isItalic: map['isItalic'],
      isUnderline: map['isUnderline'],
      isStrikethrough: map['isStrikethrough'],
      isH1: map['isH1'] ?? false,
      isH2: map['isH2'] ?? false,
      textAlign: TextAlign.values[map['textAlign']],
    );
  }
}

class DrawingEditItem extends PdfEditItem {
  List<Offset> points;
  Color color;
  double strokeWidth;

  DrawingEditItem({
    required super.id,
    required super.pageIndex,
    required this.points,
    this.color = Colors.red,
    this.strokeWidth = 2.0,
  }) : super(
         type: EditType.drawing,
         position: points.isNotEmpty ? points.first : Offset.zero,
       );

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pageIndex': pageIndex,
      'type': type.toString(),
      'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
      'colorValue': color.toARGB32(),
      'strokeWidth': strokeWidth,
    };
  }

  factory DrawingEditItem.fromMap(Map<String, dynamic> map) {
    return DrawingEditItem(
      id: map['id'],
      pageIndex: map['pageIndex'],
      points: (map['points'] as List)
          .map((p) => Offset(p['x'].toDouble(), p['y'].toDouble()))
          .toList(),
      color: Color(map['colorValue']),
      strokeWidth: map['strokeWidth'].toDouble(),
    );
  }
}
