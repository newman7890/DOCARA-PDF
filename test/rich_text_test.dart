import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_scanner_editor/services/rich_text_service.dart';

void main() {
  test(
    'StyledTextController handles multiline bold markers without treating them as literal text',
    () {
      final controller = StyledTextController();

      // Simulating multiple lines wrapped in bold markers
      controller.text = '**Line 1\nLine 2\nLine 3**';

      final span = controller.buildTextSpan(
        context: null as dynamic,
        withComposing: false,
      );

      // It should have correctly extracted the inner text and NOT left literal ** in the final plain text output.
      final textOutput = span.toPlainText();
      expect(textOutput.contains('Line 1'), isTrue);
      expect(textOutput.contains('**'), isFalse);
    },
  );

  test(
    'StyledTextController does not crash on formatting with invalid selection out of focus',
    () {
      final controller = StyledTextController();
      controller.text = 'Some text';
      // TextEditor out of focus inherently has an invalid selection (-1, -1)
      controller.selection = const TextSelection.collapsed(offset: -1);

      // Attempting to apply Bold when selection is -1 should not throw RangeError
      expect(() => controller.toggleBold(), returnsNormally);
      // Attempting to apply Bullet list when selection is -1 should not throw RangeError
      expect(() => controller.toggleBulletList(), returnsNormally);
      // Assert it appends correctly to the end or gracefully degrades
    },
  );

  test(
    'StyledTextController does not crash when parsing malformed color tags',
    () {
      final controller = StyledTextController();

      // A malformed, non-hex color tag shorter than the 15 character extraction range
      controller.text = '[:color:red:]';

      // buildTextSpan should not throw a substring index out of bounds error
      expect(() {
        final span = controller.buildTextSpan(
          context: null as dynamic,
          withComposing: false,
        );
        expect(span, isNotNull);
      }, returnsNormally);
    },
  );
}
