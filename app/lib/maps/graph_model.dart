class Edge {
  final String from;
  final String to;
  final double distance;

  Edge({required this.from, required this.to, required this.distance});

  factory Edge.fromJson(List<dynamic> json) {
    return Edge(
      from: json[0] as String,
      to: json[1] as String,
      distance: (json[2] as num).toDouble(),
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
      // Assuming undirected graph for indoor walking
      adjacencyList[edge.from]?.add(edge);
      adjacencyList[edge.to]?.add(Edge(
        from: edge.to,
        to: edge.from,
        distance: edge.distance,
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
}
