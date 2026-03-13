class RouteEngine {
  /// Converts a path of nodes into step-by-step spoken commands
  /// Example input path: ['Entrance', 'Corridor_A', 'Library']
  List<String> generateInstructions(List<String> path) {
    if (path.isEmpty) return ["No valid path found."];
    if (path.length == 1) return ["You are already at your destination."];

    List<String> instructions = [];
    instructions.add("Walk straight towards ${path[1].replaceAll('_', ' ')}.");

    for (int i = 1; i < path.length - 1; i++) {
        // Logic will need to depend on orientation/magnetometer for actual "Turn Left/Right"
        // For a simulated graph MVP without compass parsing, we announce node progression
        instructions.add("From ${path[i].replaceAll('_', ' ')}, head towards ${path[i+1].replaceAll('_', ' ')}.");
    }
    
    instructions.add("Destination reached: ${path.last.replaceAll('_', ' ')}.");
    return instructions;
  }
}
