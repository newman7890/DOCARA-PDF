import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:pdfx/pdfx.dart' as dynamic_pdfx;
import '../models/pdf_edit_overlay.dart';

enum ScanFilter { original, enhanced, grayscale, blackAndWhite }

// Top-level function required by compute() — must not be an instance method.
// Runs image decode+resize+filtering in a background Dart isolate.
Future<Uint8List> _resizeImageIsolate(Map<String, dynamic> params) async {
  final String imagePath = params['path'];
  // Use string key to avoid any enum serialization issues between isolates
  final String filterName = params['filter'] ?? 'original';
  const int maxDim = 1920;
  
  final File file = File(imagePath);
  if (!await file.exists()) return Uint8List(0);

  final Uint8List rawBytes = await file.readAsBytes();
  try {
    img.Image? image = img.decodeImage(rawBytes);
    if (image == null) return rawBytes;

    // 1. Resize if too large to prevent OOM
    if (image.width > maxDim || image.height > maxDim) {
      image = img.copyResize(
        image,
        width: image.width > image.height ? maxDim : -1,
        height: image.height >= image.width ? maxDim : -1,
      );
    }

    // 2. Apply Professional Filters
    if (filterName == 'enhanced') {
      image = img.adjustColor(image, contrast: 1.2, brightness: 0.05);
    } else if (filterName == 'grayscale') {
      image = img.grayscale(image);
      image = img.adjustColor(image, contrast: 1.1);
    } else if (filterName == 'blackAndWhite') {
      image = img.grayscale(image);
      // More robust B&W thresholding
      for (final pixel in image) {
        // Handle both 0-255 and 0-1.0 ranges just in case
        final r = pixel.r;
        final g = pixel.g;
        final b = pixel.b;
        final double lum = (r * 0.299 + g * 0.587 + b * 0.114);
        
        // If image is 0-255, threshold is 128. If 0-1.0, threshold is 0.5.
        final threshold = r > 1.0 ? 128.0 : 0.5;
        final val = lum > threshold ? (r > 1.0 ? 255 : 1.0) : 0;
        
        pixel.r = val;
        pixel.g = val;
        pixel.b = val;
      }
    }

    // 3. Optimize output
    return Uint8List.fromList(img.encodeJpg(image, quality: 90));
  } catch (e) {
    debugPrint("ISOLATE ERROR: $e");
    return rawBytes;
  }
}

/// Service to handle PDF generation.
class PDFService {
  /// Converts a list of image paths into a single PDF file with an optional filter.
  Future<File> imagesToPdf(
    List<String> imagePaths, 
    String outputPath, {
    ScanFilter filter = ScanFilter.original,
  }) async {
    final PdfDocument document = PdfDocument();
    document.compressionLevel = PdfCompressionLevel.none;

    for (final imagePath in imagePaths) {
      // Process image in a BACKGROUND ISOLATE.
      final Uint8List imageData = await compute(_resizeImageIsolate, {
        'path': imagePath,
        'filter': filter.name, // Pass as string name
      });
      
      if (imageData.isEmpty) continue;
      
      final PdfBitmap bitmap = PdfBitmap(imageData);

      // Create a page matching the image aspect ratio
      // ML Kit scanner returns cropped document images
      final PdfPage page = document.pages.add();
      
      // Points in PDF are 1/72 of an inch. 
      // We want to scale the image to fit the page while maintaining aspect ratio,
      // OR better yet, just make the page the size of the image in points.
      // Most mobile captures are high resolution, so we'll normalize to a reasonable DPI.
      
      final double pageWidth = page.getClientSize().width;
      final double pageHeight = page.getClientSize().height;
      
      final double imageWidth = bitmap.width.toDouble();
      final double imageHeight = bitmap.height.toDouble();
      
      final double aspectRatio = imageWidth / imageHeight;
      
      double drawWidth = pageWidth;
      double drawHeight = pageWidth / aspectRatio;
      
      if (drawHeight > pageHeight) {
        drawHeight = pageHeight;
        drawWidth = pageHeight * aspectRatio;
      }

      // Center the image on the page
      final double x = (pageWidth - drawWidth) / 2;
      final double y = (pageHeight - drawHeight) / 2;

      page.graphics.drawImage(
        bitmap,
        Rect.fromLTWH(x, y, drawWidth, drawHeight),
      );
    }

    final List<int> bytes = await document.save();
    document.dispose();

    final File file = File(outputPath);
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Exports a Spreadsheet object to a professional PDF table.
  Future<File> exportSpreadsheetToPdf(
    dynamic spreadsheet,
    String outputPath,
  ) async {
    final PdfDocument document = PdfDocument();
    
    final colCount = spreadsheet.activeSheet.columns.length;

    // 1. Dynamic Font & Paper Scaling Engine
    // Goal: Find the largest font size (9 down to 6) and smallest paper size (Portrait -> Landscape -> Legal)
    // that allows "Each word to be full in the column" (no wrapping).
    
    double optimalFontSize = 9.0;
    Map<int, double> colWidths = {};
    double finalTotalWidth = 0;
    
    // We try to fit into these width thresholds (points minus margins)
    const double a4PortraitMax = 515.0;
    const double a4LandscapeMax = 760.0;
    const double legalLandscapeMax = 940.0;

    for (double fs = 9.0; fs >= 6.0; fs -= 0.5) {
        optimalFontSize = fs;
        final cellFont = PdfStandardFont(PdfFontFamily.helvetica, optimalFontSize);
        final headerFont = PdfStandardFont(PdfFontFamily.helvetica, optimalFontSize + 1, style: PdfFontStyle.bold);
        const double padding = 12.0; 
        
        colWidths.clear();
        for (int i = 0; i < colCount; i++) {
            final colId = spreadsheet.activeSheet.columns[i].id;
            double maxWidth = headerFont.measureString(spreadsheet.activeSheet.columns[i].title).width + padding;
            for (var rowMap in spreadsheet.activeSheet.rows) {
                final val = rowMap[colId]?.value ?? '';
                final width = cellFont.measureString(val).width + padding;
                if (width > maxWidth) maxWidth = width;
            }
            colWidths[i] = maxWidth;
        }

        finalTotalWidth = colWidths.values.fold(0.0, (sum, w) => sum + w);
        
        // If it fits in Legal Landscape at this font size, we can stop searching.
        // We'll refine the orientation later based on the finalTotalWidth.
        if (finalTotalWidth <= legalLandscapeMax) break;
    }

    // 2. Select Orientation and Paper Size based on the calculated width
    if (finalTotalWidth <= a4PortraitMax) {
        document.pageSettings.orientation = PdfPageOrientation.portrait;
        document.pageSettings.size = PdfPageSize.a4;
    } else if (finalTotalWidth <= a4LandscapeMax) {
        document.pageSettings.orientation = PdfPageOrientation.landscape;
        document.pageSettings.size = PdfPageSize.a4;
    } else {
        document.pageSettings.orientation = PdfPageOrientation.landscape;
        document.pageSettings.size = PdfPageSize.legal;
    }

    final PdfPage page = document.pages.add();
    final double pageWidth = page.getClientSize().width;
    final double pageHeight = page.getClientSize().height;

    // Last resort: If still too wide for Legal Landscape at 6pt, 
    // scale widths down (which might cause minor clipping, but at least fits the page).
    if (finalTotalWidth > pageWidth) {
        final scale = pageWidth / finalTotalWidth;
        for (int i = 0; i < colCount; i++) {
            colWidths[i] = colWidths[i]! * scale;
        }
    }

    // 3. Premium Header Design
    page.graphics.drawRectangle(
      brush: PdfSolidBrush(PdfColor(33, 115, 70)),
      bounds: Rect.fromLTWH(0, 0, pageWidth, 60),
    );

    page.graphics.drawString(
      spreadsheet.title.toUpperCase(),
      PdfStandardFont(PdfFontFamily.helvetica, 20, style: PdfFontStyle.bold),
      brush: PdfBrushes.white,
      bounds: Rect.fromLTWH(0, 15, pageWidth, 30),
      format: PdfStringFormat(alignment: PdfTextAlignment.center),
    );

    page.graphics.drawString(
      'DOCARA SMART SPREADSHEET | GENERATED ON ${DateTime.now().toString().split('.')[0]}',
      PdfStandardFont(PdfFontFamily.helvetica, 8, style: PdfFontStyle.bold),
      brush: PdfSolidBrush(PdfColor(230, 230, 230)),
      bounds: Rect.fromLTWH(0, 42, pageWidth, 15),
      format: PdfStringFormat(alignment: PdfTextAlignment.center),
    );

    // 4. Create the Grid
    final PdfGrid grid = PdfGrid();
    grid.columns.add(count: colCount);
    for (int i = 0; i < colCount; i++) {
        grid.columns[i].width = colWidths[i]!;
    }
    
    grid.repeatHeader = true;
    
    // Header Style
    final headerStyle = PdfGridCellStyle(
      backgroundBrush: PdfSolidBrush(PdfColor(45, 45, 45)),
      textBrush: PdfBrushes.white,
      font: PdfStandardFont(PdfFontFamily.helvetica, optimalFontSize + 1, style: PdfFontStyle.bold),
      cellPadding: PdfPaddings(left: 6, right: 6, top: 8, bottom: 8),
      format: PdfStringFormat(wordWrap: PdfWordWrapType.none, alignment: PdfTextAlignment.left),
      borders: PdfBorders(bottom: PdfPen(PdfColor(33, 115, 70), width: 2)),
    );

    final PdfGridRow header = grid.headers.add(1)[0];
    for (int i = 0; i < colCount; i++) {
        header.cells[i].value = spreadsheet.activeSheet.columns[i].title;
        header.cells[i].style = headerStyle;
    }

    // Row Style
    final cellStyle = PdfGridCellStyle(
      cellPadding: PdfPaddings(left: 6, right: 6, top: 4, bottom: 4),
      font: PdfStandardFont(PdfFontFamily.helvetica, optimalFontSize),
      format: PdfStringFormat(wordWrap: PdfWordWrapType.none, alignment: PdfTextAlignment.left),
    );

    for (int i = 0; i < spreadsheet.activeSheet.rows.length; i++) {
      final rowMap = spreadsheet.activeSheet.rows[i];
      final PdfGridRow row = grid.rows.add();
      row.style = PdfGridRowStyle(
          backgroundBrush: i % 2 != 0 ? PdfSolidBrush(PdfColor(248, 252, 248)) : PdfBrushes.white,
      );

      for (int j = 0; j < colCount; j++) {
        final colId = spreadsheet.activeSheet.columns[j].id;
        row.cells[j].value = rowMap[colId]?.value ?? '';
        row.cells[j].style = cellStyle;
      }
    }

    // Grid Appearance
    grid.style = PdfGridStyle(
      cellPadding: PdfPaddings(left: 8, right: 8, top: 6, bottom: 6),
      font: PdfStandardFont(PdfFontFamily.helvetica, 9),
      borderOverlapStyle: PdfBorderOverlapStyle.overlap,
    );

    // 5. Draw the grid with a margin
    grid.draw(
      page: page,
      bounds: Rect.fromLTWH(0, 80, pageWidth, pageHeight - 110),
    );

    // 5. Advanced Footer (Page numbers, Branding)
    // BUT we want footers on ALL pages. Let's add a post-generation footer loop.
    for (int i = 0; i < document.pages.count; i++) {
       final PdfPage p = document.pages[i];
       final double pW = p.getClientSize().width;
       final double pH = p.getClientSize().height;

       p.graphics.drawLine(
         PdfPen(PdfColor(220, 220, 220)),
         Offset(0, pH - 25),
         Offset(pW, pH - 25),
       );

       // Branding
       p.graphics.drawString(
         'Docara Professional Assistant',
         PdfStandardFont(PdfFontFamily.helvetica, 8, style: PdfFontStyle.italic),
         brush: PdfBrushes.gray,
         bounds: Rect.fromLTWH(0, pH - 20, pW, 15),
         format: PdfStringFormat(alignment: PdfTextAlignment.left),
       );

       // Page Numbering
       p.graphics.drawString(
         'Page ${i + 1} of ${document.pages.count}',
         PdfStandardFont(PdfFontFamily.helvetica, 8),
         brush: PdfBrushes.gray,
         bounds: Rect.fromLTWH(0, pH - 20, pW, 15),
         format: PdfStringFormat(alignment: PdfTextAlignment.right),
       );
    }

    final List<int> bytes = await document.save();
    document.dispose();

    final File file = File(outputPath);
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Extracts text blocks with bounding boxes from a native (digital) PDF.
  /// Falls back to OCR if no native text is found.
  Future<List<PdfTextBlock>> extractTextBlocksFromPdf(
    String pdfPath, {
    required dynamic ocrService,
  }) async {
    final bytes = await File(pdfPath).readAsBytes();
    final PdfDocument document = PdfDocument(inputBytes: bytes);
    final List<PdfTextBlock> blocks = [];

    try {
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      for (int i = 0; i < document.pages.count; i++) {
        final List<TextLine> lines = extractor.extractTextLines(
          startPageIndex: i,
          endPageIndex: i,
        );
        for (var line in lines) {
          // Heuristic based on line height (points)
          // Standard text is ~10-12pt with height ~12-14pt
          bool isH1 = line.bounds.height > 18;
          bool isAllCaps =
              line.text.length >= 4 &&
              line.text == line.text.toUpperCase() &&
              RegExp(r'[A-Z]').hasMatch(line.text);
          bool isH2 = (line.bounds.height > 14 || isAllCaps) && !isH1;

          blocks.add(
            PdfTextBlock(
              text: line.text,
              bounds: line.bounds,
              pageIndex: i,
              isH1: isH1,
              isH2: isH2,
            ),
          );
        }
      }

      // FALLBACK: If no blocks identified, try OCR
      if (blocks.isEmpty) {
        final dynamic_pdfx.PdfDocument pdfxDoc =
            await dynamic_pdfx.PdfDocument.openFile(pdfPath);
        try {
          for (int i = 0; i < pdfxDoc.pagesCount; i++) {
            final page = await pdfxDoc.getPage(i + 1);
            final pageImage = await page.render(
              width: page.width * 2,
              height: page.height * 2,
              format: dynamic_pdfx.PdfPageImageFormat.jpeg,
              quality: 100,
            );

            if (pageImage != null) {
              final tempFile = File('${Directory.systemTemp.path}/page_$i.jpg');
              await tempFile.writeAsBytes(pageImage.bytes);

              final ocrBlocks = await ocrService.extractBlocksFromImage(
                tempFile,
              );

              // Calculate median height for heuristic
              double totalHeight = 0;
              int count = 0;
              for (var b in ocrBlocks) {
                totalHeight += b.boundingBox.height;
                count++;
              }
              final medianHeight = count > 0 ? (totalHeight / count) : 12.0;

              for (var b in ocrBlocks) {
                final text = b.text.trim();
                final avgLineHeight =
                    b.boundingBox.height /
                    (b.lines.isNotEmpty ? b.lines.length : 1);
                bool isAllCaps =
                    text.length >= 4 &&
                    text == text.toUpperCase() &&
                    RegExp(r'[A-Z]').hasMatch(text);

                blocks.add(
                  PdfTextBlock(
                    text: text,
                    bounds: b.boundingBox,
                    pageIndex: i,
                    isH1: avgLineHeight > medianHeight * 1.5,
                    isH2: avgLineHeight > medianHeight * 1.2 || isAllCaps,
                  ),
                );
              }
              await tempFile.delete();
            }
            await page.close();
          }
        } finally {
          await pdfxDoc.close();
        }
      }
      return blocks;
    } finally {
      document.dispose();
    }
  }

  /// Extracts text from each page of a native PDF, with OCR fallback for scanned docs.
  Future<String> extractTextFromPdf(
    String pdfPath, {
    required dynamic ocrService,
  }) async {
    try {
      final bytes = await File(pdfPath).readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      String nativeText = '';
      try {
        final PdfTextExtractor extractor = PdfTextExtractor(document);
        for (int i = 0; i < document.pages.count; i++) {
          final List<TextLine> lines = extractor.extractTextLines(
            startPageIndex: i,
            endPageIndex: i,
          );

          if (lines.isEmpty) continue;

          // Apply True Recursive XY-cut
          final sortedLines = _recursiveXYCut(lines);

          // Build text from sorted lines with smart proximity joining
          for (int k = 0; k < sortedLines.length; k++) {
            final current = sortedLines[k];
            var text = current.text.trim();

            // Header detection heuristic based on line height
            bool isAllCaps =
                text.length >= 4 &&
                text == text.toUpperCase() &&
                RegExp(r'[A-Z]').hasMatch(text);
            if (current.bounds.height > 18) {
              text = "[H1] $text";
            } else if (current.bounds.height > 14 || isAllCaps) {
              text = "[H2] $text";
            }

            nativeText += text;

            if (k < sortedLines.length - 1) {
              final next = sortedLines[k + 1];

              // Vertical proximity
              double verticalGap = next.bounds.top - current.bounds.bottom;
              // Same visual line check
              bool sameLine =
                  (next.bounds.top - current.bounds.top).abs() <
                  (current.bounds.height * 0.4);

              // Join with a space if it's on the same line OR if the line doesn't end in terminal punctuation
              bool endsInStop = RegExp(r'[.!?:]$').hasMatch(text);

              if (sameLine ||
                  (!endsInStop && verticalGap < current.bounds.height * 1.5)) {
                nativeText += " ";
              } else if (verticalGap < current.bounds.height * 1.5) {
                nativeText += "\n";
              } else {
                nativeText += "\n\n";
              }
            }
          }
          nativeText += "\n\n";
        }
        nativeText = nativeText.trim();
      } finally {
        document.dispose();
      }

      // If native extraction is not meaningful, try OCR
      // Force OCR if the text is too short or lacks alphanumeric density
      if (!_isMeaningful(nativeText) || nativeText.length < 50) {
        debugPrint("PDF: Native extraction failed or too short, falling back to OCR");
        final pdfDocument = await dynamic_pdfx.PdfDocument.openFile(pdfPath);
        try {
          String ocrText = "";

          for (int i = 1; i <= pdfDocument.pagesCount; i++) {
            final page = await pdfDocument.getPage(i);
            try {
              final pageImage = await page.render(
                width: page.width * 2,
                height: page.height * 2,
                format: dynamic_pdfx.PdfPageImageFormat.jpeg,
              );

              if (pageImage != null) {
                final tempDir = Directory.systemTemp;
                final tempFile = File('${tempDir.path}/page_$i.jpg');
                await tempFile.writeAsBytes(pageImage.bytes);

                // Filter out border noise: limit OCR to central 90% of page
                final text = await ocrService.extractTextFromImage(tempFile);
                final cleanText = _cleanNoiseAndHallucinations(text);
                if (cleanText.trim().isNotEmpty) {
                  ocrText += "$cleanText\n\n";
                }

                await tempFile.delete();
              }
            } finally {
              await page.close();
            }
          }
          return ocrText.trim();
        } finally {
          await pdfDocument.close();
        }
      }

      return nativeText;
    } catch (e) {
      debugPrint("Extraction failed: $e");
      return "";
    }
  }

  /// Creates a new PDF with mixed styling support.
  Future<File> saveTextAsPdf(
    String text,
    String outputPath, {
    String title = 'Edited Document',
    List<Offset>? signaturePoints,
  }) async {
    // Sanitize text to remove unsupported Unicode characters
    final String sanitizedText = sanitizeForPdf(text);

    final PdfDocument document = PdfDocument();

    const double margin = 40.0;

    PdfPage page = document.pages.add();
    double y = margin;
    final double pageWidth = page.getClientSize().width;
    final double pageHeight = page.getClientSize().height;

    // Parse the entire text into styled chunks
    final List<StyledChunk> chunks = _parseStyledLine(sanitizedText);

    double x = margin;
    double maxLineHeight = 14.0; // Standard base for normal layout
    bool ignoreNextNewline = false;
    int fieldCounter = 1;
    bool lineAdjusted = false; // Persistent across chunks

    for (var chunk in chunks) {
      final font = PdfStandardFont(
        PdfFontFamily.helvetica,
        chunk.fontSize,
        style: chunk.style,
      );

      // Handle horizontal rule chunk specifically
      if (chunk.text == '---') {
        // Force newline if not at start
        if (x > margin) {
          y += maxLineHeight;
          x = margin;
        }
        page.graphics.drawLine(
          PdfPen(PdfColor(200, 200, 200), width: 1),
          Offset(margin, y + 5),
          Offset(pageWidth - margin, y + 5),
        );
        y += 15.0;
        ignoreNextNewline = true;
        if (y > pageHeight - margin) {
          page = document.pages.add();
          y = margin;
        }
        continue;
      }

      // Split chunk by newlines to respect manual line breaks
      List<String> linesInChunk = chunk.text.split('\n');

      if (ignoreNextNewline &&
          linesInChunk.isNotEmpty &&
          linesInChunk.first.isEmpty) {
        linesInChunk.removeAt(0);
      }
      ignoreNextNewline = false;

      if (linesInChunk.isEmpty) continue;

      for (int lineIdx = 0; lineIdx < linesInChunk.length; lineIdx++) {
        final lineText = linesInChunk[lineIdx];

        // Handle signature inline
        if (chunk.isSignature && signaturePoints != null && signaturePoints.isNotEmpty) {
          const double sigBoxWidth = 140.0;
          const double sigBoxHeight = 50.0;
          
          if (x + sigBoxWidth > pageWidth - margin) {
            y += maxLineHeight;
            x = margin;
          }

          if (y + sigBoxHeight > pageHeight - margin) {
             page = document.pages.add();
             y = margin;
          }

          double drawX = x;
          if (chunk.isCentered) {
            drawX = (pageWidth - sigBoxWidth) / 2;
          } else if (chunk.isRight) {
            drawX = pageWidth - margin - sigBoxWidth;
          }

          // Draw signature strokes
          double minX = signaturePoints[0].dx;
          double minY = signaturePoints[0].dy;
          double maxX = signaturePoints[0].dx;
          double maxY = signaturePoints[0].dy;
          for (final p in signaturePoints) {
            if (p.dx < minX) minX = p.dx;
            if (p.dy < minY) minY = p.dy;
            if (p.dx > maxX) maxX = p.dx;
            if (p.dy > maxY) maxY = p.dy;
          }
          final double srcW = (maxX - minX) == 0 ? 1 : (maxX - minX);
          final double srcH = (maxY - minY) == 0 ? 1 : (maxY - minY);

          final sigPen = PdfPen(PdfColor(0, 0, 0), width: 2.0);
          sigPen.lineCap = PdfLineCap.round;
          const double pad = 4.0;

          Offset normSig(Offset raw) => Offset(
            drawX + pad + (raw.dx - minX) / srcW * (sigBoxWidth - pad * 2),
            y + pad + (raw.dy - minY) / srcH * (sigBoxHeight - pad * 2),
          );

          for (int i = 0; i < signaturePoints.length - 1; i++) {
            page.graphics.drawLine(
              sigPen,
              normSig(signaturePoints[i]),
              normSig(signaturePoints[i + 1]),
            );
          }

          x += sigBoxWidth + 5;
          if (sigBoxHeight > maxLineHeight) {
             maxLineHeight = sigBoxHeight;
          }
          continue;
        }

        // If this is a subsequent line in the same chunk, reset x and move y
        if (lineIdx > 0 && !lineAdjusted) {
          y += maxLineHeight;
          x = margin;
          // Reset maxLineHeight for the new line
          maxLineHeight = 14.0; // Standard baseline
          if (y > pageHeight - margin) {
            page = document.pages.add();
            y = margin;
          }
        }
        lineAdjusted = false;

        // Update maxLineHeight based on this chunk's requirements for the current line
        // Standard spacing (1.2 multiplier)
        if (chunk.fontSize * 1.2 > maxLineHeight) {
          maxLineHeight = chunk.fontSize * 1.2;
        }

        // Handle bullet points manually for circular appearance (BEFORE isEmpty check)
        if (lineIdx == 0 && chunk.isBullet) {
            double bulletSize = chunk.fontSize * 0.28;
            // Center bullet vertically relative to text height
            double bulletY = y + (chunk.fontSize * 0.7) - (bulletSize / 2);
            page.graphics.drawEllipse(
                Rect.fromLTWH(x + 2, bulletY, bulletSize, bulletSize),
                brush: PdfSolidBrush(chunk.color)
            );
            x += bulletSize + 8;
            // Don't continue here if there might be text in the same chunk, 
            // but for bullets, the chunk text is empty anyway.
        }

        if (lineText.isEmpty) {
          // No extra jump here, lineIdx > 0 above handles the newline
          continue;
        }

        final words = lineText.split(' ');
        String currentStr = '';

        for (int i = 0; i < words.length; i++) {
          final String word = words[i];
          final bool hasSpace = i < words.length - 1;
          final String piece = word + (hasSpace ? ' ' : '');

          final String testStr = currentStr + piece;
          final Size testSize = font.measureString(testStr);

          if (x + testSize.width > pageWidth - margin &&
              currentStr.isNotEmpty) {
            // Draw current line buffer
            final Size cSize = font.measureString(currentStr);
            double drawX = x;
            if (chunk.isCentered) {
              drawX = (pageWidth - cSize.width) / 2;
            } else if (chunk.isRight) {
              drawX = pageWidth - margin - cSize.width;
            }

            if (chunk.isField) {
              final PdfTextBoxField field = PdfTextBoxField(
                page,
                'field_$fieldCounter',
                Rect.fromLTWH(
                  drawX,
                  y,
                  cSize.width + 10,
                  maxLineHeight,
                ),
              );
              field.text = currentStr;
              field.font = font;
              document.form.fields.add(field);
              fieldCounter++;
            } else {
              page.graphics.drawString(
                currentStr,
                font,
                brush: PdfSolidBrush(chunk.color),
                bounds: Rect.fromLTWH(
                  drawX,
                  y,
                  cSize.width + 2,
                  maxLineHeight + 10, // Added safety buffer to prevent clipping
                ),
              );
            }

            // Underline/Strike handling
            if (chunk.isUnderline) {
              page.graphics.drawLine(
                PdfPen(chunk.color, width: 0.8),
                Offset(drawX, y + chunk.fontSize * 0.95),
                Offset(
                  drawX + font.measureString(currentStr.trimRight()).width,
                  y + chunk.fontSize * 0.95,
                ),
              );
            }
            if (chunk.isStrike) {
              page.graphics.drawLine(
                PdfPen(chunk.color, width: 0.8),
                Offset(drawX, y + chunk.fontSize * 0.5),
                Offset(
                  drawX + font.measureString(currentStr.trimRight()).width,
                  y + chunk.fontSize * 0.5,
                ),
              );
            }

            y += maxLineHeight;
            x = margin;
            lineAdjusted = false; // Reset since we already moved y
            if (y > pageHeight - margin) {
              page = document.pages.add();
              y = margin;
            }
            currentStr = piece;
          } else {
            currentStr = testStr;
          }
        }

        if (currentStr.isNotEmpty) {
          final Size cSize = font.measureString(currentStr);

          double drawX = x;
          bool forceNextLine = false;

          if (chunk.isCentered) {
            // Centering usually wants its own line unless handled very specially
            if (x > margin) {
              y += maxLineHeight;
              x = margin;
              if (y > pageHeight - margin) {
                page = document.pages.add();
                y = margin;
              }
            }
            drawX = (pageWidth - cSize.width) / 2;
            forceNextLine = true; 
          } else if (chunk.isRight) {
            drawX = pageWidth - margin - cSize.width;
            // If right-aligned text would overlap with current x, force a newline
            if (drawX < x) {
              y += maxLineHeight;
              x = margin;
              drawX = pageWidth - margin - cSize.width;
              if (y > pageHeight - margin) {
                page = document.pages.add();
                y = margin;
              }
            }
            // After right-aligned text on a mixed line, we usually want to move to next line
            forceNextLine = true;
          }

          if (chunk.isField) {
            final PdfTextBoxField field = PdfTextBoxField(
              page,
              'field_$fieldCounter',
              Rect.fromLTWH(
                drawX,
                y,
                cSize.width + 10,
                maxLineHeight + 4,
              ),
            );
            field.text = currentStr;
            field.font = font;
            document.form.fields.add(field);
            fieldCounter++;
          } else {
            page.graphics.drawString(
              currentStr,
              font,
              brush: PdfSolidBrush(chunk.color),
              bounds: Rect.fromLTWH(
                drawX,
                y,
                cSize.width + 2,
                maxLineHeight + 10, // Added safety buffer to prevent clipping
              ),
            );
          }

          if (forceNextLine) {
            y += maxLineHeight;
            x = margin;
            maxLineHeight = 14.0;
            lineAdjusted = true; 
            ignoreNextNewline = true; // Avoid double jump if user follows with \n
            if (y > pageHeight - margin) {
              page = document.pages.add();
              y = margin;
            }
          } else if (chunk.isCentered) {
            y += maxLineHeight;
            x = margin;
            if (lineIdx == linesInChunk.length - 1) {
              ignoreNextNewline = true;
            }
            if (y > pageHeight - margin) {
              page = document.pages.add();
              y = margin;
            }
          } else {
            x += cSize.width;
          }

          if (chunk.isUnderline) {
            page.graphics.drawLine(
              PdfPen(chunk.color, width: 0.8),
              Offset(drawX, y + chunk.fontSize * 0.95),
              Offset(
                drawX + font.measureString(currentStr.trimRight()).width,
                y + chunk.fontSize * 0.95,
              ),
            );
          }
          if (chunk.isStrike) {
            page.graphics.drawLine(
              PdfPen(chunk.color, width: 0.8),
              Offset(drawX, y + chunk.fontSize * 0.5),
              Offset(
                drawX + font.measureString(currentStr.trimRight()).width,
                y + chunk.fontSize * 0.5,
              ),
            );
          }
        }
      }
    }

    // Optional: render signature at the bottom of the last page if provided and NOT already placed (fallback)
    // For now, if signaturePoints is provided, we still draw it at the bottom UNLESS the user prefers it only inline.
    // Given the user specifically asked for it inline, we might want to skip the bottom one if [:sig:] was found.
    // Let's add a flag to track if it was drawn.
    // Actually, let's keep it simple: if the user adds [:sig:], it's inline. If not, it's at the bottom.
    bool signaturePlaced = chunks.any((c) => c.isSignature == true);

    if (!signaturePlaced && signaturePoints != null && signaturePoints.isNotEmpty) {
      const double sigBoxWidth = 180.0;
      const double sigBoxHeight = 60.0;
      final double sigX = margin;
      double sigY = y + 20;

      // Add a new page if signature won't fit
      if (sigY + sigBoxHeight + 30 > pageHeight - margin) {
        page = document.pages.add();
        sigY = margin;
      }

      // Label
      final sigLabelFont = PdfStandardFont(PdfFontFamily.helvetica, 10);
      page.graphics.drawString(
        'Signature:',
        sigLabelFont,
        brush: PdfSolidBrush(PdfColor(100, 100, 100)),
        bounds: Rect.fromLTWH(sigX, sigY, 100, 14),
      );
      sigY += 16;

      // Signature border box
      page.graphics.drawRectangle(
        pen: PdfPen(PdfColor(200, 200, 200)),
        bounds: Rect.fromLTWH(sigX, sigY, sigBoxWidth, sigBoxHeight),
      );

      // Normalise and draw signature strokes inside the box
      double minX = signaturePoints[0].dx;
      double minY = signaturePoints[0].dy;
      double maxX = signaturePoints[0].dx;
      double maxY = signaturePoints[0].dy;
      for (final p in signaturePoints) {
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }
      final double srcW = (maxX - minX) == 0 ? 1 : (maxX - minX);
      final double srcH = (maxY - minY) == 0 ? 1 : (maxY - minY);

      final sigPen = PdfPen(PdfColor(0, 0, 0), width: 2.5);
      sigPen.lineCap = PdfLineCap.round;
      const double pad = 6.0;

      Offset normSig(Offset raw) => Offset(
        sigX + pad + (raw.dx - minX) / srcW * (sigBoxWidth - pad * 2),
        sigY + pad + (raw.dy - minY) / srcH * (sigBoxHeight - pad * 2),
      );

      for (int i = 0; i < signaturePoints.length - 1; i++) {
        page.graphics.drawLine(
          sigPen,
          normSig(signaturePoints[i]),
          normSig(signaturePoints[i + 1]),
        );
      }

      // Underline
      page.graphics.drawLine(
        PdfPen(PdfColor(150, 150, 150)),
        Offset(sigX, sigY + sigBoxHeight + 4),
        Offset(sigX + sigBoxWidth, sigY + sigBoxHeight + 4),
      );
    }

    final List<int> bytes = await document.save();
    document.dispose();

    final File file = File(outputPath);
    await file.writeAsBytes(bytes);
    return file;
  }

  List<StyledChunk> _parseStyledLine(String text) {
    return _parseRecursive(
      text,
      PdfFontStyle.regular,
      12.0,
      PdfColor(0, 0, 0),
      false,
      false,
    );
  }

  List<StyledChunk> _parseRecursive(
    String text,
    PdfFontStyle currentStyle,
    double currentFontSize,
    PdfColor currentColor,
    bool currentUnderline,
    bool currentStrike, {
    bool isCentered = false,
  }) {
    if (text.isEmpty) return [];
    final List<StyledChunk> chunks = [];

    // Prioritize headers and expanded markdown in the regex
    final regExp = RegExp(
      r'(\*\*\*[\s\S]*?\*\*\*)|' // 1: Bold+Italic
      r'(\[(?:H1|h1)\][\s\S]*?\[/(?:H1|h1)\]|^\s*#\s+.*?$)|' // 2: H1
      r'(\[(?:H2|h2)\][\s\S]*?\[/(?:H2|h2)\]|^\s*##\s+.*?$)|' // 3: H2
      r'(\[(?:H3|h3)\][\s\S]*?\[/(?:H3|h3)\]|^\s*###\s+.*?$)|' // 4: H3
      r'(\*\*[\s\S]*?\*\*)|' // 5: Bold
      r'((?:__|_)[\s\S]*?(?:__|_))|' // 6: Underline
      r'(\*[\s\S]*?\*)|' // 7: Italic
      r'(~~[\s\S]*?~~)|' // 8: Strike
      r'(^- .*?$|^- .*?\n)|' // 9: Bullet
      r'(^\d+\. .*?$|^\d+\. .*?\n)|' // 10: Numbered (RESTORED)
      r'(^---+$|^---+\n)|' // 11: HR
      r'(\[/?(?:H1|h1|H2|h2|H3|h3)\]|\*\*\*|\*\*|\*|__|~~|---+|#+|\[:[\s\S]*?:\]|(?<!\w)_(?!\w)|\[:/?field:\]|\[:sig:\])', // 12: Markers
      multiLine: true,
    );

    int lastMatchEnd = 0;

    const double h1Size = 22.0;
    const double h2Size = 18.0;
    const double h3Size = 14.0;

    bool isCentered = false;
    bool isRight = false;
    bool isField = false;

    for (var match in regExp.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        final plainText = text.substring(lastMatchEnd, match.start);
        
        // If plain text contains newlines, alignment should reset after the last newline
        if (plainText.contains('\n')) {
          final lines = plainText.split('\n');
          for (int i = 0; i < lines.length; i++) {
            chunks.add(
              StyledChunk(
                text: lines[i] + (i < lines.length - 1 ? '\n' : ''),
                style: currentStyle,
                fontSize: currentFontSize,
                color: currentColor,
                isUnderline: currentUnderline,
                isStrike: currentStrike,
                isCentered: isCentered,
                isRight: isRight,
                isField: isField,
              ),
            );
            // After any \n, reset alignment unless it's the last piece and doesn't end with \n
            if (i < lines.length - 1) {
              isCentered = false;
              isRight = false;
            }
          }
        } else {
          chunks.add(
            StyledChunk(
              text: plainText,
              style: currentStyle,
              fontSize: currentFontSize,
              color: currentColor,
              isUnderline: currentUnderline,
              isStrike: currentStrike,
              isCentered: isCentered,
              isRight: isRight,
              isField: isField,
            ),
          );
        }
      }

      final mText = match.group(0)!;

      if (match.group(12) != null) {
        // Color / Meta
        if (mText.startsWith('[:color:') && mText.endsWith(':]')) {
          final hex = mText.substring(8, mText.length - 2);
          try {
            final r = int.parse(hex.substring(1, 3), radix: 16);
            final g = int.parse(hex.substring(3, 5), radix: 16);
            final b = int.parse(hex.substring(5, 7), radix: 16);
            currentColor = PdfColor(r, g, b);
          } catch (_) {}
        } else if (mText == '[:left:]') {
          isCentered = false;
          isRight = false;
        } else if (mText == '[:center:]') {
          isCentered = true;
          isRight = false;
        } else if (mText == '[:right:]') {
          isCentered = false;
          isRight = true;
        } else if (mText == '[:field:]') {
          isField = true;
        } else if (mText == '[:/field:]') {
          isField = false;
        } else if (mText == '[:sig:]') {
          chunks.add(
            StyledChunk(
              text: '',
              color: currentColor,
              isSignature: true,
              isCentered: isCentered,
              isRight: isRight,
            ),
          );
        }
      } else if (match.group(1) != null) {
        // *** Bold + Italic ***
        if (mText.length >= 6) {
          chunks.addAll(
            _parseRecursive(
              mText.substring(3, mText.length - 3),
              PdfFontStyle.bold,
              currentFontSize,
              currentColor,
              currentUnderline,
              currentStrike,
            ),
          );
        } else {
          chunks.add(StyledChunk(
            text: mText,
            style: currentStyle,
            fontSize: currentFontSize,
            color: currentColor,
          ));
        }
      } else if (match.group(2) != null) {
        // H1
        String content;
        if (mText.toLowerCase().startsWith('[h1]')) {
          content = mText.substring(4, mText.length - 5);
        } else {
          final hashMatch = RegExp(r'^\s*#\s+').firstMatch(mText)!;
          content = mText.substring(hashMatch.group(0)!.length);
        }
        chunks.addAll(
          _parseRecursive(
            content.trim(), // Trimmed to avoid trailing marker newlines
            PdfFontStyle.bold,
            h1Size,
            currentColor,
            currentUnderline,
            currentStrike,
            isCentered: true,
          ),
        );
      } else if (match.group(3) != null) {
        // H2
        String content;
        if (mText.toLowerCase().startsWith('[h2]')) {
          content = mText.substring(4, mText.length - 5);
        } else {
          final hashMatch = RegExp(r'^\s*##\s+').firstMatch(mText)!;
          content = mText.substring(hashMatch.group(0)!.length);
        }
        chunks.addAll(
          _parseRecursive(
            content.trim(), // Trimmed to avoid trailing marker newlines
            PdfFontStyle.bold,
            h2Size,
            currentColor,
            currentUnderline,
            currentStrike,
            isCentered: true,
          ),
        );
      } else if (match.group(4) != null) {
        // H3
        String content;
        if (mText.toLowerCase().startsWith('[h3]')) {
          content = mText.substring(4, mText.length - 5);
        } else {
          final hashMatch = RegExp(r'^\s*###\s+').firstMatch(mText)!;
          content = mText.substring(hashMatch.group(0)!.length);
        }
        chunks.addAll(
          _parseRecursive(
            content.trim(), // Trimmed to avoid trailing marker newlines
            PdfFontStyle.bold,
            h3Size,
            currentColor,
            currentUnderline,
            currentStrike,
            isCentered: true,
          ),
        );
      } else if (match.group(5) != null) {
        // Bold **
        if (mText.length >= 4) {
          chunks.addAll(
            _parseRecursive(
              mText.substring(2, mText.length - 2),
              PdfFontStyle.bold,
              currentFontSize,
              currentColor,
              currentUnderline,
              currentStrike,
            ),
          );
        } else {
          chunks.add(StyledChunk(
            text: mText,
            style: currentStyle,
            fontSize: currentFontSize,
            color: currentColor,
          ));
        }
      } else if (match.group(6) != null) {
        // Underline __ or _
        final isDouble = mText.startsWith('__');
        final mLen = isDouble ? 2 : 1;
        if (mText.length >= mLen * 2) {
          chunks.addAll(
            _parseRecursive(
              mText.substring(mLen, mText.length - mLen),
              currentStyle,
              currentFontSize,
              currentColor,
              true,
              currentStrike,
            ),
          );
        } else {
          chunks.add(StyledChunk(
            text: mText,
            style: currentStyle,
            fontSize: currentFontSize,
            color: currentColor,
          ));
        }
      } else if (match.group(7) != null) {
        // Italic *
        if (mText.length >= 2) {
          chunks.addAll(
            _parseRecursive(
              mText.substring(1, mText.length - 1),
              PdfFontStyle.italic,
              currentFontSize,
              currentColor,
              currentUnderline,
              currentStrike,
            ),
          );
        } else {
          chunks.add(StyledChunk(
            text: mText,
            style: currentStyle,
            fontSize: currentFontSize,
            color: currentColor,
          ));
        }
      } else if (match.group(8) != null) {
        // Strike ~~
        if (mText.length >= 4) {
          chunks.addAll(
            _parseRecursive(
              mText.substring(2, mText.length - 2),
              currentStyle,
              currentFontSize,
              currentColor,
              currentUnderline,
              true,
            ),
          );
        } else {
          chunks.add(StyledChunk(
            text: mText,
            style: currentStyle,
            fontSize: currentFontSize,
            color: currentColor,
          ));
        }
      } else if (match.group(9) != null) {
        // Bullet
        chunks.add(
          StyledChunk(
            text: '', // Empty text because we draw the circle manually
            style: PdfFontStyle.bold,
            fontSize: currentFontSize,
            color: currentColor,
            isBullet: true,
          ),
        );
        chunks.addAll(
          _parseRecursive(
            mText.substring(2),
            currentStyle,
            currentFontSize,
            currentColor,
            currentUnderline,
            currentStrike,
          ),
        );
      } else if (match.group(10) != null) {
        // Numbered list
        final dotIndex = mText.indexOf('. ');
        chunks.add(
          StyledChunk(
            text: mText.substring(0, dotIndex > 0 ? dotIndex + 2 : 2),
            style: PdfFontStyle.bold,
            fontSize: currentFontSize,
            color: currentColor,
          ),
        );
        chunks.addAll(
          _parseRecursive(
            mText.substring(dotIndex > 0 ? dotIndex + 2 : 2),
            currentStyle,
            currentFontSize,
            currentColor,
            currentUnderline,
            currentStrike,
          ),
        );
      } else if (match.group(11) != null) {
        // HR
        chunks.add(
          StyledChunk(
            text: '─' * 50 + '\n',
            color: PdfColor(150, 150, 150),
            fontSize: 10,
          ),
        );
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      final trailingText = text.substring(lastMatchEnd);
      if (trailingText.contains('\n')) {
        final lines = trailingText.split('\n');
        for (int i = 0; i < lines.length; i++) {
          chunks.add(
            StyledChunk(
              text: lines[i] + (i < lines.length - 1 ? '\n' : ''),
              style: currentStyle,
              fontSize: currentFontSize,
              color: currentColor,
              isUnderline: currentUnderline,
              isStrike: currentStrike,
              isCentered: isCentered,
              isRight: isRight,
              isField: isField,
            ),
          );
          if (i < lines.length - 1) {
            isCentered = false;
            isRight = false;
          }
        }
      } else {
        chunks.add(
          StyledChunk(
            text: trailingText,
            style: currentStyle,
            fontSize: currentFontSize,
            color: currentColor,
            isUnderline: currentUnderline,
            isStrike: currentStrike,
            isCentered: isCentered,
            isRight: isRight,
            isField: isField,
          ),
        );
      }
    }

    return chunks;
  }

  String sanitizeForPdf(String text) {
    if (text.isEmpty) return text;

    // Map common extended Unicode characters to ASCII equivalents
    // This covers characters likely to be used in names/text that are not in Latin-1
    final Map<String, String> replacements = {
      'đ': 'd',
      'Đ': 'D',
      'ă': 'a',
      'Ă': 'A',
      'â': 'a',
      'Â': 'A',
      'á': 'a',
      'Á': 'A',
      'à': 'a',
      'À': 'A',
      'ả': 'a',
      'Ả': 'A',
      'ã': 'a',
      'Ã': 'A',
      'ạ': 'a',
      'Ạ': 'A',
      'ấ': 'a',
      'Ấ': 'A',
      'ầ': 'a',
      'Ầ': 'A',
      'ẩ': 'a',
      'Ẩ': 'A',
      'ẫ': 'a',
      'Ẫ': 'A',
      'ậ': 'a',
      'Ậ': 'A',
      'ắ': 'a',
      'Ắ': 'A',
      'ằ': 'a',
      'Ằ': 'A',
      'ẳ': 'a',
      'Ẳ': 'A',
      'ẵ': 'a',
      'Ẵ': 'A',
      'ặ': 'a',
      'Ặ': 'A',
      'é': 'e',
      'É': 'E',
      'è': 'e',
      'È': 'E',
      'ẻ': 'e',
      'Ẻ': 'E',
      'ẽ': 'e',
      'Ẽ': 'E',
      'ẹ': 'e',
      'Ẹ': 'E',
      'ê': 'e',
      'Ê': 'E',
      'ế': 'e',
      'Ế': 'E',
      'ề': 'e',
      'Ề': 'E',
      'ể': 'e',
      'Ể': 'E',
      'ễ': 'e',
      'Ễ': 'E',
      'ệ': 'e',
      'Ệ': 'E',
      'í': 'i',
      'Í': 'I',
      'ì': 'i',
      'Ì': 'I',
      'ỉ': 'i',
      'Ỉ': 'I',
      'ĩ': 'i',
      'Ĩ': 'I',
      'ị': 'i',
      'Ị': 'I',
      'ó': 'o',
      'Ó': 'O',
      'ò': 'o',
      'Ò': 'O',
      'ỏ': 'o',
      'Ỏ': 'O',
      'õ': 'o',
      'Õ': 'O',
      'ọ': 'o',
      'Ọ': 'O',
      'ô': 'o',
      'Ô': 'O',
      'ố': 'o',
      'Ố': 'O',
      'ồ': 'o',
      'Ồ': 'O',
      'ổ': 'o',
      'Ổ': 'O',
      'ỗ': 'o',
      'Ỗ': 'O',
      'ộ': 'o',
      'Ộ': 'O',
      'ơ': 'o',
      'Ơ': 'O',
      'ớ': 'o',
      'Ớ': 'O',
      'ờ': 'o',
      'Ờ': 'O',
      'ở': 'o',
      'Ở': 'O',
      'ỡ': 'o',
      'Ỡ': 'O',
      'ợ': 'o',
      'Ợ': 'O',
      'ú': 'u',
      'Ú': 'U',
      'ù': 'u',
      'Ù': 'U',
      'ủ': 'u',
      'Ủ': 'U',
      'ũ': 'u',
      'Ũ': 'U',
      'ụ': 'u',
      'Ụ': 'U',
      'ư': 'u',
      'Ư': 'U',
      'ứ': 'u',
      'Ứ': 'U',
      'ừ': 'u',
      'Ừ': 'U',
      'ử': 'u',
      'Ử': 'U',
      'ữ': 'u',
      'Ữ': 'U',
      'ự': 'u',
      'Ự': 'U',
      'ý': 'y',
      'Ý': 'Y',
      'ỳ': 'y',
      'Ỳ': 'Y',
      'ỷ': 'y',
      'Ỷ': 'Y',
      'ỹ': 'y',
      'Ỹ': 'Y',
      'ỵ': 'y',
      'Ỵ': 'Y',
    };

    String result = text;
    replacements.forEach((key, value) {
      result = result.replaceAll(key, value);
    });

    // Final safety pass for any character > 255 (PDF standard font limit)
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < result.length; i++) {
      int charCode = result.codeUnitAt(i);
      if (charCode > 255) {
        buffer.write('?');
      } else {
        buffer.write(result[i]);
      }
    }

    return buffer.toString();
  }

  String _cleanFormatting(String text) {
    if (text.isEmpty) return "";
    return text
        .replaceAllMapped(
          RegExp(r'\[H\d\].*?\[/H\d\]'),
          (m) => m.group(0)!.substring(4, m.group(0)!.length - 5),
        )
        .replaceAll('***', '')
        .replaceAll('**', '')
        .replaceAll('*', '')
        .replaceAll('___', '')
        .replaceAll('__', '')
        .replaceAll('_', '')
        .replaceAll('~~~', '')
        .replaceAll('~~', '')
        .replaceAll('~', '')
        .replaceAll(RegExp(r'\[/H\d\]'), '')
        .replaceAll(RegExp(r'\[H\d\]'), '')
        .replaceAll(RegExp(r'\[:[\s\S]*?:\]'), '')
        .trim();
  }

  Future<File> flattenEditsToPdf(
    String originalPdfPath,
    Map<int, List<PdfEditItem>> edits,
    String outputPath,
  ) async {
    final bytes = await File(originalPdfPath).readAsBytes();
    final PdfDocument document = PdfDocument(inputBytes: bytes);

    for (final entry in edits.entries) {
      final int pdfPageIndex = entry.key - 1;

      if (pdfPageIndex >= 0 && pdfPageIndex < document.pages.count) {
        final PdfPage page = document.pages[pdfPageIndex];
        final PdfGraphics graphics = page.graphics;

        for (final edit in entry.value) {
          if (edit is TextEditItem) {
            final String cleanText = _cleanFormatting(edit.text);

            PdfFontStyle fontStyle = PdfFontStyle.regular;
            if (edit.isBold || edit.isH1 || edit.isH2) {
              fontStyle = PdfFontStyle.bold;
            }
            if (edit.isItalic && fontStyle != PdfFontStyle.bold) {
              fontStyle = PdfFontStyle.italic;
            }

            double pdfFontSize = edit.fontSize * 1.5;
            if (edit.isH1) {
              pdfFontSize *= 1.8;
            } else if (edit.isH2) {
              pdfFontSize *= 1.4;
            }

            final PdfFont font = PdfStandardFont(
              PdfFontFamily.helvetica,
              pdfFontSize,
              style: fontStyle,
            );

            final PdfColor color = PdfColor(
              (edit.color.r * 255).round().clamp(0, 255),
              (edit.color.g * 255).round().clamp(0, 255),
              (edit.color.b * 255).round().clamp(0, 255),
              (edit.color.a * 255).round().clamp(0, 255),
            );

            final double px = edit.position.dx * page.getClientSize().width;
            final double py = edit.position.dy * page.getClientSize().height;

            graphics.drawString(
              cleanText,
              font,
              brush: PdfSolidBrush(color),
              bounds: Rect.fromLTWH(
                px,
                py,
                1000,
                1000,
              ), // Large bounds for simplicity
            );

            if (edit.isUnderline) {
              graphics.drawLine(
                PdfPen(color, width: 0.8),
                Offset(px, py + pdfFontSize * 0.95),
                Offset(
                  px + font.measureString(cleanText).width,
                  py + pdfFontSize * 0.95,
                ),
              );
            }
            if (edit.isStrikethrough) {
              graphics.drawLine(
                PdfPen(color, width: 0.8),
                Offset(px, py + pdfFontSize * 0.5),
                Offset(
                  px + font.measureString(cleanText).width,
                  py + pdfFontSize * 0.5,
                ),
              );
            }
          } else if (edit is DrawingEditItem && edit.points.isNotEmpty) {
            final PdfPen pen = PdfPen(
              PdfColor(
                (edit.color.r * 255).round().clamp(0, 255),
                (edit.color.g * 255).round().clamp(0, 255),
                (edit.color.b * 255).round().clamp(0, 255),
                (edit.color.a * 255).round().clamp(0, 255),
              ),
              width: edit.strokeWidth,
            );
            pen.lineCap = PdfLineCap.round;

            final double pw = page.getClientSize().width;
            final double ph = page.getClientSize().height;

            for (int i = 0; i < edit.points.length - 1; i++) {
              final p1 = Offset(edit.points[i].dx * pw, edit.points[i].dy * ph);
              final p2 = Offset(
                edit.points[i + 1].dx * pw,
                edit.points[i + 1].dy * ph,
              );
              graphics.drawLine(pen, p1, p2);
            }
          }
        }
      }
    }

    final List<int> newBytes = await document.save();
    document.dispose();

    final File newFile = File(outputPath);
    await newFile.writeAsBytes(newBytes);
    return newFile;
  }

  bool _isMeaningful(String text) {
    if (text.isEmpty) return false;
    final cleanText = text.trim();
    if (cleanText.length < 5) return false;

    // Check alphanumeric ratio
    int alpha = 0;
    int totalNonSpace = 0;

    for (int i = 0; i < cleanText.length; i++) {
      final char = cleanText[i];
      if (char.trim().isEmpty) continue;

      totalNonSpace++;
      if (RegExp(r'[a-zA-Z0-9]').hasMatch(char)) {
        alpha++;
      }
    }

    if (totalNonSpace == 0) return false;
    // Lowered threshold to 25% to catch more messy OCR
    final ratio = alpha / totalNonSpace;
    return ratio > 0.25 && alpha > 5;
  }

  /// Strips out known OCR hallucinations and nonsensical short strings.
  String _cleanNoiseAndHallucinations(String text) {
    if (text.isEmpty) return "";

    // 0. Remove OCR header tags [H1], [H2] etc.
    String cleanStr = text.replaceAll(RegExp(r'\[H[1-6]\]'), '');

    // 1. Remove common "phantom" words (case-insensitive)
    final wordsToFilter = RegExp(
      r'\b(aah|ae|avoe|aa|ii|oo|uu|aeo|aei|aot)\b',
      caseSensitive: false,
    );

    // 2. Remove very short nonsensical blocks (e.g. "at" by itself on its own line)
    // and lines that are purely symbols
    return cleanStr
        .split('\n')
        .where((line) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) {
            return true;
          }

          // Strip known hallucinated exact lines
          final lower = trimmed.toLowerCase();
          if (lower == 'at' || lower == '@') {
            return false;
          }

          // If the line consists only of one or two noise words, skip it
          final cleanLine = trimmed.replaceAll(wordsToFilter, '').trim();
          if (cleanLine.isEmpty && trimmed.length <= 5) {
            return false;
          }

          // Skip lines that are purely non-alphanumeric noise
          if (trimmed.length < 3 && !RegExp(r'[a-zA-Z0-9]').hasMatch(trimmed)) {
            return false;
          }

          return true;
        })
        .join('\n')
        .replaceAll(wordsToFilter, '')
        .replaceAll(RegExp(r' +'), ' ')
        .trim();
  }

  /// True Recursive XY-Cut for PDF TextLines.
  List<TextLine> _recursiveXYCut(List<TextLine> lines) {
    if (lines.length <= 1) return lines;

    // --- Try Horizontal Splits First ---
    final sortedByTop = List<TextLine>.from(lines);
    sortedByTop.sort((a, b) => a.bounds.top.compareTo(b.bounds.top));

    for (int i = 0; i < sortedByTop.length - 1; i++) {
      double splitY =
          (sortedByTop[i].bounds.bottom + sortedByTop[i + 1].bounds.top) / 2;

      bool isClearCut = true;
      for (var l in lines) {
        if (l.bounds.top < splitY && l.bounds.bottom > splitY) {
          isClearCut = false;
          break;
        }
      }

      double gap = sortedByTop[i + 1].bounds.top - sortedByTop[i].bounds.bottom;
      if (isClearCut && gap > 0.5) {
        final top = lines.where((l) => l.bounds.bottom <= splitY).toList();
        final bottom = lines.where((l) => l.bounds.top >= splitY).toList();
        if (top.isNotEmpty && bottom.isNotEmpty) {
          return [..._recursiveXYCut(top), ..._recursiveXYCut(bottom)];
        }
      }
    }

    // --- Try Vertical Splits Next ---
    final sortedByLeft = List<TextLine>.from(lines);
    sortedByLeft.sort((a, b) => a.bounds.left.compareTo(b.bounds.left));

    for (int i = 0; i < sortedByLeft.length - 1; i++) {
      double splitX =
          (sortedByLeft[i].bounds.right + sortedByLeft[i + 1].bounds.left) / 2;

      bool isClearCut = true;
      for (var l in lines) {
        if (l.bounds.left < splitX && l.bounds.right > splitX) {
          isClearCut = false;
          break;
        }
      }

      double gap =
          sortedByLeft[i + 1].bounds.left - sortedByLeft[i].bounds.right;
      if (isClearCut && gap > 15) {
        // Threshold for gutter
        final left = lines.where((l) => l.bounds.right <= splitX).toList();
        final right = lines.where((l) => l.bounds.left >= splitX).toList();
        if (left.isNotEmpty && right.isNotEmpty) {
          return [..._recursiveXYCut(left), ..._recursiveXYCut(right)];
        }
      }
    }

    // Fallback: Reading order
    lines.sort((a, b) {
      int cmp = a.bounds.top.compareTo(b.bounds.top);
      if (cmp != 0) return cmp;
      return a.bounds.left.compareTo(b.bounds.left);
    });

    return lines;
  }
}

class StyledChunk {
  final String text;
  final PdfFontStyle style;
  final double fontSize;
  final PdfColor color;
  final bool isUnderline;
  final bool isStrike;
  final bool isCentered;
  final bool isRight;
  final bool isField;
  final bool isBullet;
  final bool isSignature;

  StyledChunk({
    required this.text,
    this.style = PdfFontStyle.regular,
    this.fontSize = 12.0,
    required this.color,
    this.isUnderline = false,
    this.isStrike = false,
    this.isCentered = false,
    this.isRight = false,
    this.isField = false,
    this.isBullet = false,
    this.isSignature = false,
  });

  StyledChunk copyWith({
    String? text,
    PdfFontStyle? style,
    double? fontSize,
    PdfColor? color,
    bool? isUnderline,
    bool? isStrike,
    bool? isCentered,
    bool? isRight,
    bool? isField,
    bool? isBullet,
    bool? isSignature,
  }) {
    return StyledChunk(
      text: text ?? this.text,
      style: style ?? this.style,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      isUnderline: isUnderline ?? this.isUnderline,
      isStrike: isStrike ?? this.isStrike,
      isCentered: isCentered ?? this.isCentered,
      isRight: isRight ?? this.isRight,
      isField: isField ?? this.isField,
      isBullet: isBullet ?? this.isBullet,
      isSignature: isSignature ?? this.isSignature,
    );
  }
}

class PdfTextBlock {
  final String text;
  final Rect bounds;
  final int pageIndex;
  final bool isH1;
  final bool isH2;

  PdfTextBlock({
    required this.text,
    required this.bounds,
    required this.pageIndex,
    this.isH1 = false,
    this.isH2 = false,
  });
}
