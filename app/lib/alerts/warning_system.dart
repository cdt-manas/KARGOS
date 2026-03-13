import 'voice_notifications.dart';

class WarningSystem {
  final VoiceNotifications notifications;
  
  // To avoid spamming "Chair ahead. Chair ahead." every frame
  final Map<String, DateTime> _lastWarningTime = {};

  WarningSystem({required this.notifications});

  void processDetectedObstacles(List<String> labels) {
    DateTime now = DateTime.now();

    for (String label in labels) {
      // If we haven't warned about this specific type in the last 4 seconds
      if (!_lastWarningTime.containsKey(label) ||
          now.difference(_lastWarningTime[label]!).inSeconds > 4) {
        
        notifications.queueNotification("$label ahead. Please be careful.", priority: true);
        _lastWarningTime[label] = now;
      }
    }
  }
}
