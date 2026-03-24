import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';

enum TTSState { idle, playing, paused }

class TTSService extends ChangeNotifier {
  final FlutterTts _flutterTts = FlutterTts();
  TTSState _state = TTSState.idle;
  double _speed = 1.0;
  String _language = "en-US";
  
  List<String> _sentences = [];
  int _currentIndex = 0;
  String? _currentFilePath;

  TTSService() {
    _initTts();
  }

  double get speed => _speed;
  String? get currentSentence => (_sentences.isNotEmpty && _currentIndex < _sentences.length) ? _sentences[_currentIndex] : null;

  bool canResume(String filePath) => _state == TTSState.paused && _currentFilePath == filePath;

  void setLanguage(String languageCode) {
    _language = languageCode;
    debugPrint("TTS: Language set to $_language");
    notifyListeners();
  }

  void setSpeed(double newSpeed) {
    _speed = newSpeed;
    debugPrint("TTS: Speed set to $_speed");
    notifyListeners();
    // If playing, we might want to restart the current chunk with the new speed
    if (_state == TTSState.playing) {
      _startSpeaking();
    }
  }

  void _setState(TTSState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  void _initTts() async {
    _flutterTts.setStartHandler(() {
      debugPrint("TTS: Started speaking sentence $_currentIndex");
      _setState(TTSState.playing);
    });

    _flutterTts.setCompletionHandler(() {
      debugPrint("TTS: Completed current chunk");
      if (_state == TTSState.playing) {
        _onChunkDone();
      }
    });

    _flutterTts.setErrorHandler((msg) {
      debugPrint("TTS Error: $msg");
      _setState(TTSState.idle);
    });

    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _flutterTts.setSilence(100);
      }
      await _flutterTts.setVolume(1.0);
    } catch (e) {
      debugPrint("TTS Init Error: $e");
    }
  }

  TTSState get state => _state;
  bool get isPlaying => _state == TTSState.playing;
  bool get isPaused => _state == TTSState.paused;

  Future<void> speak(String text, {required String filePath}) async {
    if (text.isEmpty) return;
    
    // Clean out OCR artifacts like header tags [H1], [H2]
    final cleanedText = text.replaceAll(RegExp(r'\[H[1-6]\]'), '');
    
    // If it's the same file and we are paused, just resume
    if (filePath == _currentFilePath && _state == TTSState.paused) {
      return resume();
    }

    // New document or starting over - Ensure old session is stopped
    await stop();

    // New text or starting over
    _currentFilePath = filePath;
    _sentences = _splitIntoSentences(cleanedText);
    _currentIndex = 0;
    _setState(TTSState.playing);

    await _startSpeaking();
  }

  Future<void> _startSpeaking() async {
    if (_currentIndex >= _sentences.length) {
      _setState(TTSState.idle);
      return;
    }

    notifyListeners(); // Ensure UI knows which sentence is current
    await _flutterTts.setLanguage(_language);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(_speed * 0.5); // 0.5 is standard human speed in flutter_tts
    await _flutterTts.setVolume(1.0);

    await _flutterTts.speak(_sentences[_currentIndex]);
  }

  void _onChunkDone() {
    _currentIndex++;
    if (_currentIndex < _sentences.length) {
      if (_state == TTSState.playing) {
        _startSpeaking();
      }
    } else {
      _setState(TTSState.idle);
    }
  }

  Future<void> pause() async {
    debugPrint("TTS: Pausing at index $_currentIndex");
    await _flutterTts.stop();
    _setState(TTSState.paused);
  }

  Future<void> resume() async {
    debugPrint("TTS: Resuming from index $_currentIndex");
    _setState(TTSState.playing);
    await _startSpeaking();
  }

  Future<void> seekBackward() async {
    if (_sentences.isEmpty) return;
    // Go back one sentence, or wrap to 0
    _currentIndex = (_currentIndex - 1).clamp(0, _sentences.length - 1);
    debugPrint("TTS: Seeking backward to index $_currentIndex");
    _setState(TTSState.playing);
    await _startSpeaking();
  }

  Future<void> seekForward() async {
    if (_sentences.isEmpty) return;
    // Skip one sentence
    _currentIndex = (_currentIndex + 1).clamp(0, _sentences.length - 1);
    debugPrint("TTS: Seeking forward to index $_currentIndex");
    _setState(TTSState.playing);
    await _startSpeaking();
  }

  Future<void> stop() async {
    debugPrint("TTS: Stopping completely");
    await _flutterTts.stop();
    _setState(TTSState.idle);
    _currentIndex = 0;
    _sentences = [];
    _currentFilePath = null;
  }

  List<String> _splitIntoSentences(String text) {
    // Regex to split by terminal punctuation followed by space or newline
    final regex = RegExp(r'(?<=[.!?])\s+|\n+');
    return text.split(regex).where((s) => s.trim().isNotEmpty).toList();
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }
}
