import 'package:flutter_test/flutter_test.dart';
import 'package:app/voice/voice_command_handler.dart';

void main() {
  group('Voice Intent Parsing', () {
    late VoiceCommandHandler handler;

    setUp(() {
      handler = VoiceCommandHandler();
    });

    test('Parses navigate intent correctly', () {
      final result = handler.parseCommand("Please take me to Library");
      expect(result['intent'], 'navigate');
      expect(result['destination'], 'Library');
    });

    test('Parses locate intent correctly', () {
      final result = handler.parseCommand("Where am i right now?");
      expect(result['intent'], 'locate');
    });

    test('Returns unknown for gibberish', () {
      final result = handler.parseCommand("Hello how is the weather");
      expect(result['intent'], 'unknown');
    });
  });
}
