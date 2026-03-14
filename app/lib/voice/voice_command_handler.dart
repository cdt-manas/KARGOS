class VoiceCommandHandler {
  /// Simple intent parsing for Demo purposes
  /// Returns a map with 'intent' and 'destination' if applicable.
  Map<String, String> parseCommand(String text) {
    String lower = text.toLowerCase();
    
    if (lower.contains("navigate") || lower.contains("take me to")) {
      // Very naive extraction: "take me to library" -> "Library"
      String dest = _extractDestination(lower);
      return {'intent': 'navigate', 'destination': dest};
    } else if (lower.contains("where am i")) {
      return {'intent': 'locate'};
    } else if (lower.contains("repeat")) {
      return {'intent': 'repeat'};
    } else if (lower.contains("emergency") || lower.contains("help")) {
      return {'intent': 'emergency'};
    } else if (lower.contains("stop alarm")) {
      return {'intent': 'stop_alarm'};
    }
    
    return {'intent': 'unknown'};
  }

  String _extractDestination(String lower) {
    // Hardcoded node list mapping for hackathon stability
    if (lower.contains("library")) return "Library";
    if (lower.contains("entrance")) return "Entrance";
    if (lower.contains("corridor a")) return "Corridor_A";
    if (lower.contains("corridor b")) return "Corridor_B";
    if (lower.contains("stairs")) return "Stairs";
    if (lower.contains("washroom")) return "Washroom";
    if (lower.contains("lavatory")) return "Lavatory";
    if (lower.contains("laboratory")) return "Laboratory";

    return "";
  }
}
