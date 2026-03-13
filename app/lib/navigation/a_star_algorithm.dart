import '../maps/graph_model.dart';
import '../maps/map_repository.dart';

class AStarAlgorithm {
  final MapRepository mapRepository;

  AStarAlgorithm({required this.mapRepository});

  List<String> findPath(String start, String target) {
    if (!mapRepository.hasMap) return [];
    
    GraphModel graph = mapRepository.currentGraph!;
    if (!graph.isValidNode(start) || !graph.isValidNode(target)) return [];

    // For A* on a predefined graph without coordinates, heuristic is 0,
    // essentially boiling down to Dijkstra's. We can extend with X,Y coordinates if needed.
    Map<String, double> gScore = {for (var node in graph.nodes) node: double.infinity};
    gScore[start] = 0;

    Map<String, double> fScore = {for (var node in graph.nodes) node: double.infinity};
    fScore[start] = 0;

    Map<String, String> cameFrom = {};
    List<String> openSet = [start];

    while (openSet.isNotEmpty) {
      // Get the node with the lowest fScore
      String current = openSet.reduce((curr, next) => (fScore[curr] ?? double.infinity) < (fScore[next] ?? double.infinity) ? curr : next);

      if (current == target) {
        return _reconstructPath(cameFrom, current);
      }

      openSet.remove(current);

      for (Edge edge in graph.adjacencyList[current] ?? []) {
        String neighbor = edge.to == current ? edge.from : edge.to;
        double tentativeGScore = gScore[current]! + edge.distance;

        if (tentativeGScore < (gScore[neighbor] ?? double.infinity)) {
          cameFrom[neighbor] = current;
          gScore[neighbor] = tentativeGScore;
          fScore[neighbor] = tentativeGScore; // + heuristic(neighbor, target) if coordinates were present

          if (!openSet.contains(neighbor)) {
            openSet.add(neighbor);
          }
        }
      }
    }

    return []; // Path not found
  }

  List<String> _reconstructPath(Map<String, String> cameFrom, String current) {
    List<String> totalPath = [current];
    while (cameFrom.containsKey(current)) {
      current = cameFrom[current]!;
      totalPath.insert(0, current);
    }
    return totalPath;
  }
}
