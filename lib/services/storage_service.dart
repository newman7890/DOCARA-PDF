import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/scanned_document.dart';

/// Service to handle local file storage for documents.
/// This service saves metadata about scanned documents in a JSON file.
class StorageService {
  static const String _metadataFile = 'documents_metadata.json';

  /// Gets the local directory for app documents.
  Future<Directory> get _localDirectory async {
    return await getApplicationDocumentsDirectory();
  }

  /// Saves a document's metadata and ensures the file is in the app's directory.
  Future<void> saveDocument(ScannedDocument doc) async {
    final docs = await loadDocuments();

    // Check if the document already exists in metadata
    final index = docs.indexWhere((item) => item.id == doc.id);

    // Populate size if missing
    ScannedDocument docToSave = doc;
    if (docToSave.fileSize == null) {
      final file = File(doc.filePath);
      if (file.existsSync()) {
        docToSave = doc.copyWith(
          fileSize: ScannedDocument.formatBytes(file.lengthSync()),
        );
      }
    }

    if (index != -1) {
      docs[index] = docToSave;
    } else {
      docs.add(docToSave);
    }

    await _saveMetadata(docs);
  }

  /// Loads all saved documents from local storage.
  Future<List<ScannedDocument>> loadDocuments() async {
    try {
      final directory = await _localDirectory;
      final file = File(path.join(directory.path, _metadataFile));

      if (!file.existsSync()) {
        return [];
      }

      final content = await file.readAsString();
      final List<dynamic> jsonList = json.decode(content);
      final List<ScannedDocument> docs = jsonList
          .map((e) => ScannedDocument.fromMap(e))
          .toList();

      // Population of missing file sizes or update existing ones
      for (int i = 0; i < docs.length; i++) {
        if (docs[i].fileSize == null) {
          final docFile = File(docs[i].filePath);
          if (docFile.existsSync()) {
            final size = await docFile.length();
            docs[i] = docs[i].copyWith(
              fileSize: ScannedDocument.formatBytes(size),
            );
          }
        }
      }

      return docs..sort((a, b) => b.dateCreated.compareTo(a.dateCreated));
    } catch (e) {
      debugPrint("Error loading documents: $e");
      return [];
    }
  }

  /// Deletes a document and its associated file.
  Future<void> deleteDocument(ScannedDocument doc) async {
    final docs = await loadDocuments();
    docs.removeWhere((item) => item.id == doc.id);
    await _saveMetadata(docs);

    // Also delete the physical file
    final file = File(doc.filePath);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// Renames a document and its physical file.
  Future<ScannedDocument> renameDocument(
    ScannedDocument doc,
    String newTitle,
  ) async {
    final docs = await loadDocuments();
    final index = docs.indexWhere((item) => item.id == doc.id);

    if (index == -1) throw Exception("Document not found");

    // Clean new title for filename
    String safeName = newTitle.replaceAll(RegExp(r'[^\w\s\-]'), '_');
    if (!safeName.toLowerCase().endsWith('.pdf')) {
      safeName += '.pdf';
    }

    final directory = await _localDirectory;
    final newPath = path.join(directory.path, safeName);

    // Collision check
    if (File(newPath).existsSync() && newPath != doc.filePath) {
      throw Exception("A document with this name already exists.");
    }

    // Rename physical file
    final oldFile = File(doc.filePath);
    if (oldFile.existsSync()) {
      await oldFile.rename(newPath);
    }

    // Update metadata
    final updatedDoc = doc.copyWith(
      title: newTitle.endsWith('.pdf') ? newTitle : '$newTitle.pdf',
      filePath: newPath,
    );

    docs[index] = updatedDoc;
    await _saveMetadata(docs);

    return updatedDoc;
  }

  /// Helper to save the document list to JSON.
  Future<void> _saveMetadata(List<ScannedDocument> docs) async {
    final directory = await _localDirectory;
    final file = File(path.join(directory.path, _metadataFile));
    final jsonContent = json.encode(docs.map((e) => e.toMap()).toList());
    await file.writeAsString(jsonContent);
  }

  /// Clears temporary cache files.
  Future<void> clearCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        final files = tempDir.listSync();
        for (final file in files) {
          if (file is File) {
            try {
              await file.delete();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint("Error clearing cache: $e");
    }
  }

  /// Returns a path for a new PDF file.
  Future<String> getNewFilePath(String fileName) async {
    final directory = await _localDirectory;
    String name = fileName.replaceAll(RegExp(r'[^\w\s\-]'), '_');
    return path.join(directory.path, "$name.pdf");
  }
}
