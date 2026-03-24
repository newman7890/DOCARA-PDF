import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:flutter/foundation.dart';

class TranslationService {
  final _languageIdentifier = LanguageIdentifier(confidenceThreshold: 0.5);

  /// Identifies the source language of the text.
  Future<String> identifyLanguage(String text) async {
    try {
      final languageCode = await _languageIdentifier.identifyLanguage(text);
      debugPrint("Translation: Identified language as $languageCode");
      return languageCode;
    } catch (e) {
      debugPrint("Translation: Identification error: $e");
      return 'en'; // Fallback to English
    }
  }

  /// Translates text from source to target language.
  Future<String> translate({
    required String text,
    required String targetLanguageCode,
    String? sourceLanguageCode,
  }) async {
    final source = sourceLanguageCode ?? await identifyLanguage(text);
    if (source == targetLanguageCode) return text;

    final sourceModel = _mapLanguageCode(source);
    final targetModel = _mapLanguageCode(targetLanguageCode);

    if (sourceModel == null || targetModel == null) return text;

    final translator = OnDeviceTranslator(
      sourceLanguage: sourceModel,
      targetLanguage: targetModel,
    );

    try {
      final result = await translator.translateText(text);
      return result;
    } catch (e) {
      debugPrint("Translation error: $e");
      return text; // Return original on error
    } finally {
      translator.close();
    }
  }

  TranslateLanguage? _mapLanguageCode(String code) {
    // Map common BCP47 codes to TranslateLanguage
    final map = {
      'en': TranslateLanguage.english,
      'es': TranslateLanguage.spanish,
      'fr': TranslateLanguage.french,
      'de': TranslateLanguage.german,
      'it': TranslateLanguage.italian,
      'pt': TranslateLanguage.portuguese,
      'ru': TranslateLanguage.russian,
      'zh': TranslateLanguage.chinese,
      'ja': TranslateLanguage.japanese,
      'ko': TranslateLanguage.korean,
      'ar': TranslateLanguage.arabic,
      'hi': TranslateLanguage.hindi,
    };
    return map[code.split('-')[0].toLowerCase()];
  }

  void dispose() {
    _languageIdentifier.close();
  }
}
