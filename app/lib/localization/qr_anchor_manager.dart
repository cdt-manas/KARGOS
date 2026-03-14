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

    String normalizedQR = qrString.trim().toUpperCase();
    String nodeCandidate = "";

    // Specific Demo ID Mapping
    if (normalizedQR == "QR_LIB") {
      nodeCandidate = "Library";
    } else if (normalizedQR == "QR_WR") {
      nodeCandidate = "Washroom";
    } else if (normalizedQR == "QR_LAV") {
      nodeCandidate = "Lavatory";
    } else if (normalizedQR == "QR_LAB") {
      nodeCandidate = "Laboratory";
    } else if (normalizedQR.startsWith("NODE:")) {
      nodeCandidate = qrString.split(":")[1];
    } else {
      nodeCandidate = qrString; // Fallback to direct name
    }
    
    // Check if it's a valid node directly
    if (mapRepository.currentGraph!.isValidNode(nodeCandidate)) {
       positionTracker.updatePosition(nodeCandidate);
       print("Position updated to: $nodeCandidate");
    }
  }
}
