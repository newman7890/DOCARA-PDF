import 'dart:io';
import '../models/pdf_edit_overlay.dart';

/// Model representing a scanned document or an imported PDF.
class ScannedDocument {
  final String id;
  final String title;
  final String filePath;
  final DateTime dateCreated;
  final bool isPdf;

  final String? sourcePath;
  final bool? isScanned;
  final String? fileSize;
  final Map<int, List<PdfEditItem>>? overlayEdits;
  final String? extractedText;
  final String? documentType; // e.g., 'ID Card', 'Passport', 'License', 'Document'

  ScannedDocument({
    required this.id,
    required this.title,
    required this.filePath,
    required this.dateCreated,
    this.sourcePath,
    this.isPdf = true,
    this.isScanned,
    this.fileSize,
    this.overlayEdits,
    this.extractedText,
    this.documentType,
  });

  /// Factory constructor to create a ScannedDocument from a Map (useful for local storage).
  factory ScannedDocument.fromMap(Map<String, dynamic> map) {
    return ScannedDocument(
      id: map['id'],
      title: map['title'],
      filePath: map['filePath'],
      dateCreated: DateTime.parse(map['dateCreated']),
      isPdf: map['isPdf'] ?? true,
      sourcePath: map['sourcePath'],
      isScanned: map['isScanned'],
      fileSize: map['fileSize'],
      extractedText: map['extractedText'],
      documentType: map['documentType'],
      overlayEdits: map['overlayEdits'] != null
          ? (map['overlayEdits'] as Map).map(
              (key, value) => MapEntry(
                int.parse(key.toString()),
                (value as List)
                    .map((item) => PdfEditItem.fromMap(item))
                    .toList(),
              ),
            )
          : null,
    );
  }

  ScannedDocument copyWith({
    String? title,
    String? filePath,
    String? sourcePath,
    bool? isPdf,
    bool? isScanned,
    String? fileSize,
    Map<int, List<PdfEditItem>>? overlayEdits,
    String? extractedText,
    String? documentType,
  }) {
    return ScannedDocument(
      id: id,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      dateCreated: dateCreated,
      sourcePath: sourcePath ?? this.sourcePath,
      isPdf: isPdf ?? this.isPdf,
      isScanned: isScanned ?? this.isScanned,
      fileSize: fileSize ?? this.fileSize,
      overlayEdits: overlayEdits ?? this.overlayEdits,
      extractedText: extractedText ?? this.extractedText,
      documentType: documentType ?? this.documentType,
    );
  }

  /// Converts the ScannedDocument into a Map for local storage.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'filePath': filePath,
      'sourcePath': sourcePath,
      'dateCreated': dateCreated.toIso8601String(),
      'isPdf': isPdf,
      'isScanned': isScanned,
      'fileSize': fileSize,
      'extractedText': extractedText,
      'documentType': documentType,
      'overlayEdits': overlayEdits?.map(
        (key, value) =>
            MapEntry(key.toString(), value.map((e) => e.toMap()).toList()),
      ),
    };
  }

  /// Returns the file size in a readable format.
  String getFileSize() {
    if (fileSize != null) return fileSize!;

    final file = File(filePath);
    if (!file.existsSync()) return "Unknown size";
    final bytes = file.lengthSync();
    return formatBytes(bytes);
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }
}
