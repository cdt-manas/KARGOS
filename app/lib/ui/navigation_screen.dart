import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:camera/camera.dart';

import '../alerts/voice_notifications.dart';
import '../alerts/warning_system.dart';
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

import '../camera/yolo_detector.dart';
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
  String? _lastAnnouncedNode;

  // Navigation Session
  List<String>? _activePath;
  int _nextPathIndex = 0;

  // QR Scanner
  MobileScannerController? scannerController;

  // YOLO Detector (runs on a separate camera stream)
  late YoloDetector yoloDetector;
  CameraController? _yoloCameraController;
  bool _isYoloProcessing = false;
  int _yoloFrameCount = 0;

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

    // 4. QR Scanner (MobileScanner — proven reliable)
    scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );

    // 5. YOLO Detector
    yoloDetector = YoloDetector();
    await yoloDetector.loadModel();
    await _initYoloCamera();

    // Welcome Message
    voiceAlerts.queueNotification("Welcome. Please scan a building Entrance QR code to load the map.");
    setState(() {});
  }

  Future<void> _initYoloCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      _yoloCameraController = CameraController(
        cameras[0],
        ResolutionPreset.low, // Low res is enough for YOLO 320x320
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _yoloCameraController!.initialize();
      _yoloCameraController!.startImageStream(_onYoloFrame);
    } catch (e) {
      print("YOLO camera init error: $e");
    }
  }

  void _onYoloFrame(CameraImage image) {
    _yoloFrameCount++;
    // Process every 20th frame to save CPU
    if (_yoloFrameCount % 20 != 0) return;
    if (_isYoloProcessing) return;

    _isYoloProcessing = true;
    yoloDetector.detectObstacles(image).then((obstacles) {
      if (obstacles.isNotEmpty) {
        warningSystem.processDetectedObstacles(obstacles);
      }
      _isYoloProcessing = false;
    }).catchError((e) {
      print("YOLO detection error: $e");
      _isYoloProcessing = false;
    });
  }

  void _onQRDetected(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        _handleQRResult(barcode.rawValue!);
      }
    }
  }

  void _handleQRResult(String qrValue) async {
      if (!mapRepo.hasMap) {
        // Initial map loading
        if (qrValue.contains("BUILDING")) {
          setState(() => currentStatusText = "Loading Map...");
          await mapLoader.loadMapFromQR(qrValue);
          
          if (mapRepo.hasMap) {
             positionTracker.updatePosition("Entrance"); 
             _lastAnnouncedNode = "Entrance";
             setState(() => currentStatusText = "Map Loaded. Current Location: Entrance.");
             voiceAlerts.queueNotification("Map loaded. You are at the Entrance. Press the button and tell the desired place you want to go.");
          }
        }
      } else {
        // Continuous Localization
        qrManager.processQRData(qrValue);
        final currentNode = positionTracker.currentNode;
        if (currentNode != null) {
            setState(() {
               currentStatusText = "Location: ${currentNode.replaceAll('_', ' ')}";
            });
            
            if (currentNode != _lastAnnouncedNode) {
               _lastAnnouncedNode = currentNode;
               
               voiceAlerts.queueNotification("You have reached ${currentNode.replaceAll('_', ' ')}.");

               if (_activePath != null && _nextPathIndex < _activePath!.length) {
                 if (currentNode == _activePath![_nextPathIndex]) {
                   _nextPathIndex++;
                   
                   if (_nextPathIndex < _activePath!.length) {
                     final nextNode = _activePath![_nextPathIndex];
                     final distance = mapRepo.currentGraph?.getDistance(currentNode, nextNode);
                     final instr = pathPlanner.routeEngine.getInstructionForStep(
                       currentNode, 
                       nextNode,
                       distance
                     );
                     voiceAlerts.queueNotification(instr);
                   } else {
                     voiceAlerts.queueNotification("You have reached your destination.");
                     _activePath = null;
                   }
                 }
               }
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
         List<String> rawPath = pathPlanner.findPath(positionTracker.currentNode!, dest);
         
         if (rawPath.isEmpty) {
           voiceAlerts.queueNotification("I couldn't find a path to $dest.");
         } else if (rawPath.length == 1) {
           voiceAlerts.queueNotification("You are already at the ${dest.replaceAll('_', ' ')}.");
         } else {
           setState(() {
             _activePath = rawPath;
             _nextPathIndex = 1;
             currentStatusText = "Navigating to $dest";
           });

           voiceAlerts.queueNotification(pathPlanner.routeEngine.getRouteSummary(rawPath));
           
           final firstDistance = mapRepo.currentGraph?.getDistance(rawPath[0], rawPath[1]);
           voiceAlerts.queueNotification(pathPlanner.routeEngine.getInstructionForStep(rawPath[0], rawPath[1], firstDistance));
         }
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
    scannerController?.dispose();
    _yoloCameraController?.dispose();
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
          // Background QR Scanner (MobileScanner — primary camera feed)
          Positioned.fill(
            child: scannerController != null
              ? MobileScanner(
                  controller: scannerController!,
                  onDetect: _onQRDetected,
                )
              : const Center(child: CircularProgressIndicator()),
          ),
          
          // Status Info Layer
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
