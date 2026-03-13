import 'graph_model.dart';

class MapRepository {
  GraphModel? _currentGraph;

  void setCurrentGraph(GraphModel graph) {
    _currentGraph = graph;
  }

  GraphModel? get currentGraph => _currentGraph;

  bool get hasMap => _currentGraph != null;
}
