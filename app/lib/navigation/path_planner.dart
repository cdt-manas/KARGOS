import 'a_star_algorithm.dart';
import 'route_engine.dart';

class PathPlanner {
  final AStarAlgorithm aStar;
  final RouteEngine routeEngine;

  PathPlanner({required this.aStar, required this.routeEngine});

  List<String> planRouteAndGetInstructions(String start, String destination) {
    var rawPath = aStar.findPath(start, destination);
    return routeEngine.generateInstructions(rawPath);
  }
}
