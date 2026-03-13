import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../alerts/voice_notifications.dart';
import '../alerts/warning_system.dart';
import '../camera/frame_processor.dart';
import '../localization/position_tracker.dart';
import '../localization/qr_anchor_manager.dart';
import '../maps/indoor_map_loader.dart';
import '../maps/map_repository.dart';
import '../navigation/a_star_algorithm.dart';
import '../navigation/path_planner.dart';
import '../navigation/route_engine.dart';
import '../voice/speech_to_text.dart';
import '../voice/text_to_speech.dart';
import '../voice/voice_command_handler.dart';

import 'camera_view.dart';
import 'voice_button.dart';

class MainNavigationScreen extends StatefulWidget {
  @override
  _MainNavigationScreenState createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  // Services
  late TTSWrapper ttsWrapper;
  late STTWrapper sttWrapper;
  late VoiceNotifications voiceAlerts;
  late VoiceCommandHandler commandHandler;
  late WarningSystem warningSystem;

  late MapRepository mapRepo;
  late IndoorMapLoader mapLoader;
  late PositionTracker positionTracker;
  late QRAnchorManager qrManager;
  late PathPlanner pathPlanner;

  // UI State
  bool isListening = false;
  String currentStatusText = "Scanning for Building Entrance QR...";
  String lastUserCommand = "";

  // Camera
  final MobileScannerController scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    // 1. Voice
    ttsWrapper = TTSWrapper();
    await ttsWrapper.init();
    sttWrapper = STTWrapper();
    await sttWrapper.init();
    
    voiceAlerts = VoiceNotifications(tts: ttsWrapper);
    commandHandler = VoiceCommandHandler();
    warningSystem = WarningSystem(notifications: voiceAlerts);

    // 2. Maps & Location
    mapRepo = MapRepository();
    mapLoader = IndoorMapLoader(repository: mapRepo);
    positionTracker = PositionTracker();
    qrManager = QRAnchorManager(mapRepository: mapRepo, positionTracker: positionTracker);

    // 3. Navigation
    final aStar = AStarAlgorithm(mapRepository: mapRepo);
    final routeEngine = RouteEngine();
    pathPlanner = PathPlanner(aStar: aStar, routeEngine: routeEngine);

    // Welcome Message
    voiceAlerts.queueNotification("Welcome. Please scan a building Entrance QR code to load the map.");
  }

  void _onQRDetected(BarcodeCapture capture) async {
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      String? rawValue = barcode.rawValue;
      if (rawValue == null) continue;

      if (!mapRepo.hasMap) {
        // Initial map loading
        if (rawValue.contains("BUILDING")) {
          setState(() => currentStatusText = "Loading Map...");
          await mapLoader.loadMapFromQR(rawValue);
          
          if (mapRepo.hasMap) {
             positionTracker.updatePosition("Entrance"); // default assumption for hackathon
             setState(() => currentStatusText = "Map Loaded. Current Location: Entrance.");
             voiceAlerts.queueNotification("Map loaded. You are at the Entrance. Press the mic and say 'Navigate me to Library'");
          }
        }
      } else {
        // Continuous Localization
        qrManager.processQRData(rawValue);
        if (positionTracker.currentNode != null) {
            setState(() => currentStatusText = "Location: ${positionTracker.currentNode}");
        }
      }
    }
  }

  void _onVoiceButtonPressed() {
    if (isListening) {
      sttWrapper.stopListening();
      setState(() => isListening = false);
    } else {
      setState(() {
        isListening = true;
        currentStatusText = "Listening...";
      });
      sttWrapper.startListening((words) {
         setState(() {
           lastUserCommand = words;
           isListening = false;
         });
         _processCommand(words);
      });
    }
  }

  void _processCommand(String command) {
    Map<String, String> result = commandHandler.parseCommand(command);
    
    if (result['intent'] == 'navigate') {
       String dest = result['destination']!;
       if (dest.isEmpty) {
         voiceAlerts.queueNotification("Sorry, I didn't catch the destination.");
         return;
       }
       if (positionTracker.hasPosition) {
         List<String> instructions = pathPlanner.planRouteAndGetInstructions(positionTracker.currentNode!, dest);
         
         for (String step in instructions) {
            voiceAlerts.queueNotification(step);
         }
         setState(() => currentStatusText = "Navigating to $dest");
       } else {
         voiceAlerts.queueNotification("Current location unknown. Scan a QR anchor.");
       }
    } else if (result['intent'] == 'locate') {
       if (positionTracker.hasPosition) {
         voiceAlerts.queueNotification("You are near ${positionTracker.currentNode!.replaceAll('_', ' ')}.");
       } else {
         voiceAlerts.queueNotification("I am not sure where you are. Scan a nearby QR code.");
       }
    } else {
       voiceAlerts.queueNotification("Command not recognized.");
    }
  }

  @override
  void dispose() {
    scannerController.dispose();
    ttsWrapper.stop();
    sttWrapper.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background Camera View
          Positioned.fill(
            child: CameraView(
              controller: scannerController,
              onDetect: _onQRDetected,
            ),
          ),
          
          // Debug / Status Info Layer
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black54,
                 borderRadius: BorderRadius.circular(12)
              ),
              child: Column(
                children: [
                  Text(
                    currentStatusText,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  if (lastUserCommand.isNotEmpty)
                    Text("You said: $lastUserCommand", style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),

          // Main Voice Button Layer
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: VoiceButton(
                isListening: isListening,
                onPressed: _onVoiceButtonPressed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
