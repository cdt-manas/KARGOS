import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';

class EmergencyService {
  static const String emergencyNumber = "+919835709105"; 
  final AudioPlayer _audioPlayer = AudioPlayer();

  Future<void> triggerEmergency() async {
    print("EMERGENCY triggered!");
    
    // 1. Play loud alarm
    _playAlarm();

    // 2. Call emergency contact
    _makeCall();
  }

  Future<void> _playAlarm() async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(AssetSource('siren.mp3'));
    } catch (e) {
      print("Error playing alarm: $e");
    }
  }

  Future<void> _makeCall() async {
    final Uri callUri = Uri(scheme: 'tel', path: emergencyNumber);
    if (await canLaunchUrl(callUri)) {
      await launchUrl(callUri);
    }
  }

  void stopAlarm() {
    _audioPlayer.stop();
  }
}
