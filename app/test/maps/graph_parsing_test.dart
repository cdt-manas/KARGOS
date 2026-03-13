import 'package:flutter_test/flutter_test.dart';
import 'package:app/maps/graph_model.dart';
import 'package:app/maps/map_repository.dart';

void main() {
  group('Graph Model Parsing', () {
    test('Parses JSON accurately', () {
      final json = {
        "nodes": ["A", "B", "C"],
        "edges": [
          ["A", "B", 10],
          ["B", "C", 5]
        ]
      };

      final graph = GraphModel.fromJson(json);

      expect(graph.nodes.length, 3);
      expect(graph.edges.length, 2);
      expect(graph.isValidNode("B"), true);
      expect(graph.isValidNode("Z"), false);

      // Verify adjacency list connects B back to A
      expect(graph.adjacencyList["B"]?.any((edge) => edge.to == "A"), true);
      expect(graph.adjacencyList["A"]?.any((edge) => edge.to == "B"), true);
    });
  });

  group('Map Repository State', () {
    test('Stores and retrieves map', () {
      final repo = MapRepository();
      expect(repo.hasMap, false);

      final graph = GraphModel(nodes: ["A"], edges: []);
      repo.setCurrentGraph(graph);

      expect(repo.hasMap, true);
      expect(repo.currentGraph?.nodes.first, "A");
    });
  });
}
