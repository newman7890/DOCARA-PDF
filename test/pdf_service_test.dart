import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_scanner_editor/services/pdf_service.dart';

void main() {
  group('PDFService Sanitization Tests', () {
    final pdfService = PDFService();

    test('sanitizeForPdf replaces Unicode character 272 (đ)', () {
      const input = 'Chào ông Nguyễn Văn Đỗ';
      final output = pdfService.sanitizeForPdf(input);
      expect(output, contains('Do'));
      expect(output, isNot(contains('đ')));
      expect(output, isNot(contains('Đ')));
    });

    test('sanitizeForPdf replaces common Vietnamese characters', () {
      const input = 'Tiếng Việt có nhiều dấu';
      final output = pdfService.sanitizeForPdf(input);
      // 'ế' -> 'e', 'ệ' -> 'e', 'ả' -> 'a', etc.
      expect(output, 'Tieng Viet co nhieu dau');
    });

    test('sanitizeForPdf falls back to ? for unknown high characters', () {
      const input = 'Emoji check: 🚀 and complex char: 𐐷';
      final output = pdfService.sanitizeForPdf(input);
      expect(output, isNot(contains('🚀')));
      expect(output.contains('?'), isTrue);
    });

    test('sanitizeForPdf preserves standard ASCII', () {
      const input = 'Hello World! 123 @#\$%';
      final output = pdfService.sanitizeForPdf(input);
      expect(output, input);
    });
  });
}
