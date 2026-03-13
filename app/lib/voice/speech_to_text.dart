import 'package:speech_to_text/speech_to_text.dart';

class STTWrapper {
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;

  Future<void> init() async {
    _speechEnabled = await _speechToText.initialize();
  }

  void startListening(Function(String) onResult) {
    if (_speechEnabled) {
      _speechToText.listen(
        onResult: (result) {
          if (result.finalResult) {
            onResult(result.recognizedWords);
          }
        },
      );
    }
  }

  void stopListening() {
    _speechToText.stop();
  }
}
