class RouteEngine {
  /// Converts a path of nodes into step-by-step spoken commands
  /// Example input path: ['Entrance', 'Corridor_A', 'Library']
  /// Provides a high-level summary of the route
  String getRouteSummary(List<String> path) {
    if (path.isEmpty) return "No route available.";
    if (path.length == 1) return "You are already there.";
    
    final destination = path.last.replaceAll('_', ' ');
    if (path.length == 2) return "Heading to $destination.";
    
    return "Route planned to $destination. Passing through ${path.skip(1).take(path.length - 2).map((e) => e.replaceAll('_', ' ')).join(', ')}.";
  }

  /// Returns a specific instruction for moving from current node to the next in the path
  String getInstructionForStep(String current, String next, [double? distance]) {
    String distanceStr = distance != null ? " for ${distance.toInt()} steps" : "";
    return "Walk straight towards ${next.replaceAll('_', ' ')}$distanceStr.";
  }

  /// Original method maintained for backward compatibility if needed, but improved phrasing
  List<String> generateInstructions(List<String> path) {
    if (path.isEmpty) return ["No valid path found."];
    if (path.length == 1) return ["You are already at your destination."];

    List<String> instructions = [];
    instructions.add(getRouteSummary(path));
    
    for (int i = 0; i < path.length - 1; i++) {
        instructions.add("Step ${i + 1}: From ${path[i].replaceAll('_', ' ')}, ${getInstructionForStep(path[i], path[i+1])}");
    }
    
    instructions.add("You have reached your destination: ${path.last.replaceAll('_', ' ')}.");
    return instructions;
  }
}
