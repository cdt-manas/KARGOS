class Edge {
  final String from;
  final String to;
  final double distance;
  final String direction;

  Edge({
    required this.from,
    required this.to,
    required this.distance,
    required this.direction,
  });

  factory Edge.fromJson(List<dynamic> json) {
    return Edge(
      from: json[0] as String,
      to: json[1] as String,
      distance: (json[2] as num).toDouble(),
      direction: json.length > 3 ? json[3] as String : "straight",
    );
  }
}

class GraphModel {
  final List<String> nodes;
  final List<Edge> edges;
  final Map<String, List<Edge>> adjacencyList = {};

  GraphModel({required this.nodes, required this.edges}) {
    for (var node in nodes) {
      adjacencyList[node] = [];
    }
    for (var edge in edges) {
      // Add forward edge
      adjacencyList[edge.from]?.add(edge);
      // Add reciprocal edge with inverse direction
      String inverseDir = "straight";
      if (edge.direction == "left") {
        inverseDir = "right";
      } else if (edge.direction == "right") {
        inverseDir = "left";
      }

      adjacencyList[edge.to]?.add(Edge(
        from: edge.to,
        to: edge.from,
        distance: edge.distance,
        direction: inverseDir,
      ));
    }
  }

  factory GraphModel.fromJson(Map<String, dynamic> json) {
    var nodesList = (json['nodes'] as List).cast<String>();
    var edgesList = (json['edges'] as List).map((e) => Edge.fromJson(e)).toList();
    return GraphModel(nodes: nodesList, edges: edgesList);
  }

  bool isValidNode(String node) {
    return nodes.contains(node);
  }

  double? getDistance(String from, String to) {
    if (!adjacencyList.containsKey(from)) return null;
    for (var edge in adjacencyList[from]!) {
      if (edge.to == to) return edge.distance;
    }
    return null;
  }

  String getDirection(String from, String to) {
    if (!adjacencyList.containsKey(from)) return "straight";
    for (var edge in adjacencyList[from]!) {
      if (edge.to == to) return edge.direction;
    }
    return "straight";
  }
}
