class PositionTracker {
  String? _currentNode;

  void updatePosition(String newNode) {
    _currentNode = newNode;
  }

  String? get currentNode => _currentNode;

  bool get hasPosition => _currentNode != null;
}
