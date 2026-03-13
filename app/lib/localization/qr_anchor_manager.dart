import 'position_tracker.dart';
import '../maps/map_repository.dart';

class QRAnchorManager {
  final MapRepository mapRepository;
  final PositionTracker positionTracker;

  QRAnchorManager({
    required this.mapRepository,
    required this.positionTracker,
  });

  /// Decodes QR data and checks if it corresponds to a valid Map Node
  /// Automatically updates current position if valid
  void processQRData(String qrString) {
    if (!mapRepository.hasMap) return;

    // Example Mapping: QR code text is "QR_02" which correlates to "Corridor_A" Node.
    // For Hackathon prototype, we can assume QR text structurally embodies the Node Name itself for simplicity,
    // ie: QR format contains "NODE:Corridor_A"
    
    if (qrString.startsWith("NODE:")) {
      String nodeName = qrString.split(":")[1];
      if (mapRepository.currentGraph!.isValidNode(nodeName)) {
        positionTracker.updatePosition(nodeName);
        print("Position updated to: $nodeName");
      }
    }
  }
}
