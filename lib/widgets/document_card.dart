import 'package:flutter/material.dart';
import '../models/scanned_document.dart';
import 'package:intl/intl.dart';

/// A reusable card widget to display a document in the list.
class DocumentCard extends StatelessWidget {
  final ScannedDocument doc;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final VoidCallback onRename;
  final VoidCallback? onExtractText;
  final VoidCallback? onEditPdf;

  const DocumentCard({
    super.key,
    required this.doc,
    required this.onTap,
    required this.onDelete,
    required this.onShare,
    required this.onRename,
    this.onExtractText,
    this.onEditPdf,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.indigo.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            doc.isPdf ? Icons.picture_as_pdf : Icons.image,
            color: Colors.indigo,
            size: 30,
          ),
        ),
        title: Text(
          doc.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('MMM dd, yyyy - hh:mm a').format(doc.dateCreated),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            Text(
              doc.getFileSize(),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'share') onShare();
            if (value == 'extract' && onExtractText != null) onExtractText!();
            if (value == 'editPdf' && onEditPdf != null) onEditPdf!();
            if (value == 'rename') onRename();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'extract',
              child: Row(
                children: [
                  Icon(
                    Icons.text_snippet_outlined,
                    size: 20,
                    color: Colors.indigo,
                  ),
                  SizedBox(width: 8),
                  Text('Extract & Refine'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'share',
              child: Row(
                children: [
                  Icon(Icons.share, size: 20),
                  SizedBox(width: 8),
                  Text('Share'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'rename',
              child: Row(
                children: [
                  Icon(Icons.drive_file_rename_outline, size: 20),
                  SizedBox(width: 8),
                  Text('Rename'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
