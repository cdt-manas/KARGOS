import 'package:flutter_tts/flutter_tts.dart';

class TTSWrapper {
  final FlutterTts flutterTts = FlutterTts();

  Future<void> init() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(1.0);
  }

  Future<void> speak(String text) async {
    await flutterTts.speak(text);
  }

  Future<void> stop() async {
    await flutterTts.stop();
  }
}
