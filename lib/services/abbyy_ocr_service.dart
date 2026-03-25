import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/ocr_data.dart';
import 'dart:math';
import 'dart:ui';

class AbbyyOCRService {
  final String _baseUrl = 'https://cloud-westus.ocrsdk.com'; // Adjust based on account region

  Future<List<TextBlock>> processImage(
    File imageFile, {
    required String appId,
    required String password,
  }) async {
    final String auth = 'Basic ${base64Encode(utf8.encode('$appId:$password'))}';

    // 1. Upload and Submit Task
    final Uri uploadUri = Uri.parse('$_baseUrl/v2/processImage?exportFormat=json');
    final http.MultipartRequest request = http.MultipartRequest('POST', uploadUri);
    request.headers['Authorization'] = auth;
    request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));

    final response = await request.send();
    if (response.statusCode != 200) {
      final errorMsg = await response.stream.bytesToString();
      throw Exception('ABBYY Upload Failed: $errorMsg');
    }

    final String responseBody = await response.stream.bytesToString();
    final Map<String, dynamic> taskData = jsonDecode(responseBody);
    final String taskId = taskData['id'];

    // 2. Poll for Completion
    String? resultUrl;
    int retries = 0;
    while (retries < 30) {
      await Future.delayed(const Duration(seconds: 2));
      final statusUri = Uri.parse('$_baseUrl/v2/getTaskStatus?taskId=$taskId');
      final statusResponse = await http.get(statusUri, headers: {'Authorization': auth});
      
      if (statusResponse.statusCode != 200) throw Exception('ABBYY Status Check Failed');
      
      final Map<String, dynamic> statusData = jsonDecode(statusResponse.body);
      final String status = statusData['status'];
      
      if (status == 'Completed') {
        resultUrl = statusData['resultUrls'][0];
        break;
      } else if (status == 'ProcessingFailed') {
        throw Exception('ABBYY Processing Failed');
      }
      retries++;
    }

    if (resultUrl == null) throw Exception('ABBYY Timeout');

    // 3. Download JSON Results
    final resultResponse = await http.get(Uri.parse(resultUrl));
    if (resultResponse.statusCode != 200) throw Exception('ABBYY Result Download Failed');

    final Map<String, dynamic> abbyyJson = jsonDecode(resultResponse.body);
    return _parseAbbyyJson(abbyyJson);
  }

  List<TextBlock> _parseAbbyyJson(Map<String, dynamic> json) {
    final List<TextBlock> blocks = [];
    
    // ABBYY JSON structure varies by version, but V2 ExportFormat=json 
    // typically returns pages[] -> blocks[] -> lines[] -> characters[]
    final pages = json['pages'] as List?;
    if (pages == null || pages.isEmpty) return [];

    for (final page in pages) {
      final abbyyBlocks = page['blocks'] as List?;
      if (abbyyBlocks == null) continue;

      for (final b in abbyyBlocks) {
        final List<TextLine> lines = [];
        final abbyyLines = b['lines'] as List?;
        if (abbyyLines == null) continue;

        String blockText = "";

        for (final l in abbyyLines) {
          final String text = l['text'] ?? '';
          blockText += (blockText.isEmpty ? '' : '\n') + text;

          // ML Kit TextLine requires bounding box and elements
          // ABBYY provides top, left, bottom, right
          final lineRect = _parseRect(l);

          lines.add(TextLine(
            text: text,
            elements: [],
            boundingBox: lineRect,
            recognizedLanguages: [],
            cornerPoints: [
              Point(lineRect.left.toInt(), lineRect.top.toInt()),
              Point(lineRect.right.toInt(), lineRect.top.toInt()),
              Point(lineRect.right.toInt(), lineRect.bottom.toInt()),
              Point(lineRect.left.toInt(), lineRect.bottom.toInt()),
            ],
            confidence: 1.0,
            angle: 0.0,
          ));
        }

        final blockRect = _parseRect(b);
        blocks.add(TextBlock(
          text: blockText,
          lines: lines,
          boundingBox: blockRect,
          recognizedLanguages: [],
          cornerPoints: [
            Point(blockRect.left.toInt(), blockRect.top.toInt()),
            Point(blockRect.right.toInt(), blockRect.top.toInt()),
            Point(blockRect.right.toInt(), blockRect.bottom.toInt()),
            Point(blockRect.left.toInt(), blockRect.bottom.toInt()),
          ],
        ));
      }
    }

    return blocks;
  }

  Rect _parseRect(Map<String, dynamic> item) {
    // ABBYY uses left, top, right, bottom in its JSON export
    final double left = (item['left'] ?? 0).toDouble();
    final double top = (item['top'] ?? 0).toDouble();
    final double right = (item['right'] ?? 0).toDouble();
    final double bottom = (item['bottom'] ?? 0).toDouble();
    return Rect.fromLTRB(left, top, right, bottom);
  }
}
