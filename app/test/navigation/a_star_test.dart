import 'package:flutter_test/flutter_test.dart';
import 'package:app/maps/graph_model.dart';
import 'package:app/maps/map_repository.dart';
import 'package:app/navigation/a_star_algorithm.dart';

void main() {
  group('A* Algorithm Path Planning', () {
    late MapRepository repository;
    late AStarAlgorithm aStar;

    setUp(() {
      repository = MapRepository();
      aStar = AStarAlgorithm(mapRepository: repository);

      final graph = GraphModel.fromJson({
         "nodes": ["A", "B", "C", "D"],
         "edges": [
           ["A", "B", 10],
           ["B", "C", 5],
           ["A", "C", 20],
           ["C", "D", 5]
         ]
      });
      repository.setCurrentGraph(graph);
    });

    test('Computes shortest path from A to D', () {
      final path = aStar.findPath("A", "D");
      expect(path, ["A", "B", "C", "D"]);
    });

    test('Computes shortest path from A to C', () {
      final path = aStar.findPath("A", "C");
      // A->B (10) + B->C (5) = 15, which is < A->C (20)
      expect(path, ["A", "B", "C"]);
    });

    test('Returns empty list for unconnected nodes', () {
       // Mock a broken graph scenario if needed, or invalid nodes
       final path = aStar.findPath("A", "Z");
       expect(path, []);
    });
  });
}
