import '../voice/text_to_speech.dart';

class VoiceNotifications {
  final TTSWrapper tts;
  bool _isSpeaking = false;
  final List<String> _queue = [];

  VoiceNotifications({required this.tts});

  void queueNotification(String message, {bool priority = false}) {
    if (priority) {
      _queue.insert(0, message);
      _playNext();
    } else {
      _queue.add(message);
      if (!_isSpeaking) _playNext();
    }
  }

  void _playNext() async {
    if (_queue.isEmpty) {
      _isSpeaking = false;
      return;
    }

    _isSpeaking = true;
    String next = _queue.removeAt(0);
    await tts.speak(next);
    
    // Simulate completion callback (TTS package has its own listener which can be hooked)
    Future.delayed(Duration(seconds: 2), () {
      _playNext();
    });
  }
}
