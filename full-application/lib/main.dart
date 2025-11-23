// import 'dart:async';
// import 'dart:ui' as ui; // For Image handling
// import 'package:flutter/material.dart';
// import 'package:camera/camera.dart';
// import 'package:flutter_vision/flutter_vision.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart';
//
// // Import your existing services
// import 'osm_service.dart';
// import 'gemini_service.dart';
// import 'fish_audio_service.dart';
//
// late List<CameraDescription> _cameras;
//
// Future<void> main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//
//   // 1. Load Environment Variables
//   try {
//     await dotenv.load(fileName: ".env");
//   } catch (e) {
//     debugPrint("Error loading .env: $e");
//   }
//
//   // 2. Find Cameras
//   try {
//     _cameras = await availableCameras();
//   } catch (e) {
//     debugPrint("Camera Error: $e");
//     _cameras = [];
//   }
//
//   runApp(const VisualGuideApp());
// }
//
// class VisualGuideApp extends StatelessWidget {
//   const VisualGuideApp({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Visual Guide',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData.dark().copyWith(
//         scaffoldBackgroundColor: const Color(0xFF1A1A1A),
//       ),
//       home: const HomeScreen(),
//     );
//   }
// }
//
// class HomeScreen extends StatefulWidget {
//   const HomeScreen({super.key});
//
//   @override
//   State<HomeScreen> createState() => _HomeScreenState();
// }
//
// class _HomeScreenState extends State<HomeScreen> {
//   // === HARDWARE & AI ===
//   CameraController? controller;
//   late FlutterVision vision;
//
//   // === SERVICES ===
//   final OSMService _osmService = OSMService();
//   late GeminiService _geminiService;
//   late FishAudioService _fishAudioService;
//   final DangerAnalyzer _analyzer = DangerAnalyzer();
//   final StickyTracker _tracker = StickyTracker();
//
//   // === STATE ===
//   bool _isLoaded = false;       // Are models/camera ready?
//   bool _isActive = false;       // Is the "Start" button pressed?
//   bool _isDetecting = false;    // Is YOLO currently processing a frame?
//   String _statusText = "Initializing...";
//
//   // === DATA ===
//   List<Map<String, dynamic>> _yoloResults = [];
//   Map<int, int> _trackAssignments = {};
//   CameraImage? _cameraImage;    // For painting boxes
//   String _globalDangerStatus = "SAFE";
//
//   // === TIMERS ===
//   Timer? _environmentTimer;     // The slow loop (Gemini/OSM)
//   DateTime? _lastDangerAudio;   // To prevent spamming "Stop! Stop!"
//
//   // === DIAGNOSTICS ===
//   int _fps = 0;
//   int _inferenceMs = 0;
//   DateTime? _lastFrameTime;
//
//   @override
//   void initState() {
//     super.initState();
//     _initializeSystem();
//   }
//
//   // 1. INITIALIZE EVERYTHING (BUT DO NOT START SCANNING)
//   Future<void> _initializeSystem() async {
//     // A. API Keys
//     final gKey = dotenv.env['GEMINI_API_KEY'] ?? '';
//     final fKey = dotenv.env['FISH_AUDIO_API_KEY'] ?? '';
//     if (gKey.isEmpty || fKey.isEmpty) {
//       setState(() => _statusText = "Error: Missing API Keys");
//       return;
//     }
//     _geminiService = GeminiService(gKey);
//     _fishAudioService = FishAudioService(fKey);
//
//     // B. Permissions
//     await [
//       Permission.camera,
//       Permission.location,
//       Permission.microphone
//     ].request();
//
//     // C. Camera
//     if (_cameras.isEmpty) {
//       setState(() => _statusText = "No Camera Found");
//       return;
//     }
//     controller = CameraController(_cameras[0], ResolutionPreset.high, enableAudio: false);
//     await controller!.initialize();
//
//     // D. Vision Model
//     vision = FlutterVision();
//     await vision.loadYoloModel(
//         modelPath: "assets/yolov8m.tflite", // Ensure this matches your asset
//         labels: "assets/labels.txt",
//         modelVersion: "yolov8",
//         quantization: false,
//         numThreads: 4,
//         useGpu: true
//     );
//
//     setState(() {
//       _isLoaded = true;
//       _statusText = "System Ready. Press Start.";
//     });
//   }
//
//   // 2. TOGGLE LOGIC (THE START/STOP BUTTON)
//   void _toggleSystem() async {
//     if (!_isLoaded) return;
//
//     if (_isActive) {
//       // === STOPPING ===
//       setState(() {
//         _isActive = false;
//         _statusText = "Stopping...";
//         _yoloResults = [];
//         _cameraImage = null;
//         _globalDangerStatus = "SAFE";
//       });
//
//       // Stop Loops
//       _environmentTimer?.cancel();
//       await controller?.stopImageStream();
//       await _fishAudioService.stopAudio();
//
//       setState(() => _statusText = "System Idle");
//
//     } else {
//       // === STARTING ===
//       setState(() {
//         _isActive = true;
//         _statusText = "Starting Vision...";
//       });
//
//       // A. Start Fast Loop (YOLO)
//       await controller?.startImageStream((image) => _yoloLoop(image));
//
//       // B. Start Slow Loop (Gemini/OSM) - Runs every 20 seconds
//       _environmentTimer = Timer.periodic(const Duration(seconds: 20), (t) => _environmentLoop());
//
//       // Trigger first environment scan immediately
//       _environmentLoop();
//
//       setState(() => _statusText = "Scanning...");
//     }
//   }
//
//   // 3. FAST LOOP: YOLO OBJECT DETECTION (~30 FPS)
//   void _yoloLoop(CameraImage image) async {
//     if (_isDetecting || !_isActive) return;
//     _isDetecting = true;
//     final stopwatch = Stopwatch()..start();
//
//     try {
//       // A. Run Inference
//       final result = await vision.yoloOnFrame(
//         bytesList: image.planes.map((plane) => plane.bytes).toList(),
//         imageHeight: image.height,
//         imageWidth: image.width,
//         iouThreshold: 0.4,
//         confThreshold: 0.35,
//         classThreshold: 0.4,
//       );
//
//       // B. Track Objects
//       List<Rect> rects = result.map((r) => Rect.fromLTRB(r["box"][0], r["box"][1], r["box"][2], r["box"][3])).toList();
//       Map<int, int> assignments = _tracker.update(rects);
//       _analyzer.cleanOldHistory(assignments.values.toSet());
//
//       // C. Analyze Danger
//       String maxDanger = "SAFE";
//       String dangerLabel = "";
//
//       for (int i = 0; i < result.length; i++) {
//         int? id = assignments[i];
//         if (id == null) continue;
//
//         double h = result[i]["box"][3] - result[i]["box"][1];
//         var analysis = _analyzer.analyze(id, result[i]["tag"], h, image.height.toDouble());
//
//         if (analysis["status"] == "CRITICAL") {
//           maxDanger = "CRITICAL";
//           dangerLabel = result[i]["tag"];
//         } else if (analysis["status"] == "WARNING" && maxDanger != "CRITICAL") {
//           maxDanger = "WARNING";
//         }
//       }
//
//       // D. IMMEDIATE AUDIO INTERRUPT (Safety First)
//       if (maxDanger == "CRITICAL") {
//         if (_lastDangerAudio == null || DateTime.now().difference(_lastDangerAudio!).inSeconds > 3) {
//           _lastDangerAudio = DateTime.now();
//           debugPrint("🚨 CRITICAL DANGER: $dangerLabel");
//           // Assuming you added an interrupt parameter to FishAudioService,
//           // otherwise regular TTS is fine, it just might queue.
//           _fishAudioService.textToSpeech("Stop! $dangerLabel ahead!");
//         }
//       }
//
//       // E. Update UI
//       stopwatch.stop();
//       if (mounted) {
//         setState(() {
//           _yoloResults = result;
//           _trackAssignments = assignments;
//           _cameraImage = image;
//           _globalDangerStatus = maxDanger;
//           _inferenceMs = stopwatch.elapsedMilliseconds;
//
//           if (_lastFrameTime != null) {
//             int gap = DateTime.now().difference(_lastFrameTime!).inMilliseconds;
//             if (gap > 0) _fps = (1000 / gap).round();
//           }
//           _lastFrameTime = DateTime.now();
//         });
//       }
//
//     } catch (e) {
//       debugPrint("YOLO Loop Error: $e");
//     } finally {
//       _isDetecting = false;
//     }
//   }
//
//   // 4. SLOW LOOP: CONTEXT (GEMINI + OSM) (~Every 20s)
//   Future<void> _environmentLoop() async {
//     if (!_isActive) return;
//     // Don't describe scenery if a car is about to hit the user
//     if (_globalDangerStatus == "CRITICAL") return;
//
//     try {
//       // A. Get Location
//       Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
//
//       // B. Get Places
//       List<POI> pois = await _osmService.getNearbyPOIs(pos.latitude, pos.longitude);
//       final topPois = pois.take(4).toList();
//
//       // C. Get Description
//       String desc = await _geminiService.convertToConversation(topPois);
//
//       // D. Speak (Only if still safe)
//       if (_isActive && _globalDangerStatus != "CRITICAL") {
//         debugPrint("🌍 ENV AUDIO: $desc");
//         await _fishAudioService.textToSpeech(desc);
//       }
//
//     } catch (e) {
//       debugPrint("Env Loop Error: $e");
//     }
//   }
//
//   @override
//   void dispose() {
//     controller?.dispose();
//     vision.closeYoloModel();
//     _environmentTimer?.cancel();
//     _fishAudioService.dispose();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     // 1. Loading Screen (UPDATED TO SHOW ERRORS)
//     if (!_isLoaded) {
//       return Scaffold(
//         backgroundColor: Colors.black,
//         body: Center(child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             // If status contains "Error", show red icon, else show spinner
//             if (_statusText.contains("Error") || _statusText.contains("Missing"))
//               const Icon(Icons.error_outline, color: Colors.red, size: 50)
//             else
//               const CircularProgressIndicator(),
//
//             const SizedBox(height: 20),
//
//             // Show the actual status text so you know what's wrong!
//             Text(
//               _statusText,
//               style: TextStyle(
//                   color: _statusText.contains("Error") ? Colors.redAccent : Colors.white,
//                   fontSize: 16,
//                   fontWeight: FontWeight.bold
//               ),
//               textAlign: TextAlign.center,
//             ),
//           ],
//         )),
//       );
//     }
//
//
//     final Size screenSize = MediaQuery.of(context).size;
//
//     return Scaffold(
//       body: Stack(
//         children: [
//           // A. CAMERA FEED (Zoomed to Cover)
//           if (controller != null && controller!.value.isInitialized)
//             SizedBox(
//               width: screenSize.width,
//               height: screenSize.height,
//               child: FittedBox(
//                 fit: BoxFit.cover,
//                 child: SizedBox(
//                   width: controller!.value.previewSize!.height,
//                   height: controller!.value.previewSize!.width,
//                   child: CameraPreview(controller!),
//                 ),
//               ),
//             ),
//
//           // B. DRAWING OVERLAY (Only when active)
//           if (_isActive && _cameraImage != null)
//             SizedBox(
//               width: screenSize.width,
//               height: screenSize.height,
//               child: CustomPaint(
//                 painter: ResultsPainter(
//                     _yoloResults,
//                     _trackAssignments,
//                     _analyzer,
//                     _cameraImage!.height.toDouble(),
//                     _cameraImage!.width.toDouble(),
//                     screenSize
//                 ),
//               ),
//             ),
//
//           // C. STATUS BAR (Top)
//           Positioned(
//             top: 50, left: 20, right: 20,
//             child: Container(
//               padding: const EdgeInsets.symmetric(vertical: 15),
//               decoration: BoxDecoration(
//                   color: _getStatusColor().withOpacity(0.9),
//                   borderRadius: BorderRadius.circular(15),
//                   boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10)]
//               ),
//               child: Text(
//                 _isActive ? (_globalDangerStatus == "SAFE" ? "PATH CLEAR" : _globalDangerStatus) : "SYSTEM IDLE",
//                 textAlign: TextAlign.center,
//                 style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.5),
//               ),
//             ),
//           ),
//
//           // D. START/STOP BUTTON (Bottom)
//           Positioned(
//             bottom: 40, left: 20, right: 20,
//             child: SizedBox(
//               height: 60,
//               child: ElevatedButton.icon(
//                 onPressed: _toggleSystem,
//                 style: ElevatedButton.styleFrom(
//                     backgroundColor: _isActive ? Colors.redAccent : Colors.blueAccent,
//                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
//                     elevation: 10
//                 ),
//                 icon: Icon(_isActive ? Icons.stop_circle : Icons.play_circle, size: 30),
//                 label: Text(
//                   _isActive ? "STOP GUIDING" : "START GUIDING",
//                   style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
//                 ),
//               ),
//             ),
//           ),
//
//           // E. DEBUG INFO (Small text above button)
//           Positioned(
//             bottom: 110, left: 20,
//             child: _isActive ? Container(
//               padding: const EdgeInsets.all(5),
//               color: Colors.black54,
//               child: Text(
//                 "FPS: $_fps | Inf: ${_inferenceMs}ms | YOLOv8m",
//                 style: const TextStyle(color: Colors.white70, fontSize: 12),
//               ),
//             ) : const SizedBox.shrink(),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Color _getStatusColor() {
//     if (!_isActive) return Colors.grey;
//     if (_globalDangerStatus == "CRITICAL") return Colors.red;
//     if (_globalDangerStatus == "WARNING") return Colors.orange;
//     return Colors.green;
//   }
// }
//
// // ==================== HELPER CLASSES (PASTE THESE AT THE BOTTOM) ====================
//
// // 1. LOGIC: DANGER ANALYZER
// class DangerAnalyzer {
//   static const double DANGER_ZONE_RATIO = 0.45;
//   static const double APPROACH_THRESHOLD = 0.05;
//
//   final List<String> targetClasses = [
//     "person", "bicycle", "car", "motorcycle", "bus", "train", "truck",
//     "laptop", "tv", "cell phone", "keyboard", "mouse"
//   ];
//
//   final Map<int, List<double>> _history = {};
//
//   Map<String, String> analyze(int trackId, String label, double currentH, double frameH) {
//     if (!targetClasses.contains(label)) return {"status": "IGNORE", "message": ""};
//
//     double heightRatio = currentH / frameH;
//     if (heightRatio > DANGER_ZONE_RATIO) {
//       return {"status": "CRITICAL", "message": "STOP! $label"};
//     }
//
//     if (!_history.containsKey(trackId)) _history[trackId] = [];
//     _history[trackId]!.add(currentH);
//     if (_history[trackId]!.length > 10) _history[trackId]!.removeAt(0);
//
//     if (_history[trackId]!.length >= 3) {
//       double pastH = _history[trackId]![0];
//       if (pastH > 0) {
//         double growth = (currentH - pastH) / pastH;
//         if (growth > APPROACH_THRESHOLD) {
//           return {"status": "WARNING", "message": "Approaching"};
//         }
//       }
//     }
//
//     if (["laptop", "tv", "cell phone"].contains(label)) return {"status": "INFO", "message": "Detected"};
//
//     return {"status": "SAFE", "message": ""};
//   }
//
//   void cleanOldHistory(Set<int> activeIds) {
//     _history.removeWhere((key, value) => !activeIds.contains(key));
//   }
// }
//
// // 2. LOGIC: STICKY TRACKER
// class StickyTracker {
//   int _nextId = 0;
//   final Map<int, Offset> _objects = {};
//   final Map<int, int> _disappearedCount = {};
//   final int maxDisappearedFrames = 10;
//
//   Map<int, int> update(List<Rect> rects) {
//     if (rects.isEmpty) {
//       for (int id in _objects.keys) {
//         _disappearedCount[id] = (_disappearedCount[id] ?? 0) + 1;
//       }
//       _cleanup();
//       return {};
//     }
//
//     List<Offset> inputCentroids = rects.map((r) => r.center).toList();
//     Map<int, int> assignments = {};
//     Set<int> usedExistingIds = {};
//     Set<int> usedInputIndexes = {};
//
//     if (_objects.isNotEmpty) {
//       for (int i = 0; i < inputCentroids.length; i++) {
//         Offset inputCenter = inputCentroids[i];
//         int? bestId;
//         double shortestDist = 100.0;
//
//         _objects.forEach((id, existingCenter) {
//           if (usedExistingIds.contains(id)) return;
//           double dist = (inputCenter - existingCenter).distance;
//           if (dist < shortestDist) {
//             shortestDist = dist;
//             bestId = id;
//           }
//         });
//
//         if (bestId != null) {
//           assignments[i] = bestId!;
//           _objects[bestId!] = inputCenter;
//           _disappearedCount[bestId!] = 0;
//           usedExistingIds.add(bestId!);
//           usedInputIndexes.add(i);
//         }
//       }
//     }
//
//     for (int i = 0; i < inputCentroids.length; i++) {
//       if (!usedInputIndexes.contains(i)) {
//         int newId = _nextId++;
//         _objects[newId] = inputCentroids[i];
//         _disappearedCount[newId] = 0;
//         assignments[i] = newId;
//       }
//     }
//     for (int id in _objects.keys) {
//       if (!usedExistingIds.contains(id)) {
//         _disappearedCount[id] = (_disappearedCount[id] ?? 0) + 1;
//       }
//     }
//     _cleanup();
//     return assignments;
//   }
//
//   void _cleanup() {
//     _objects.removeWhere((id, _) => (_disappearedCount[id] ?? 0) > maxDisappearedFrames);
//     _disappearedCount.removeWhere((id, count) => count > maxDisappearedFrames);
//   }
// }
//
// // 3. VISUALS: RESULTS PAINTER
// class ResultsPainter extends CustomPainter {
//   final List<Map<String, dynamic>> results;
//   final Map<int, int> assignments;
//   final DangerAnalyzer analyzer;
//   final double camHeight;
//   final double camWidth;
//   final Size screenSize;
//
//   ResultsPainter(this.results, this.assignments, this.analyzer, this.camHeight, this.camWidth, this.screenSize);
//
//   @override
//   void paint(Canvas canvas, Size size) {
//     double baseScaleX = screenSize.width / camHeight;
//     double baseScaleY = screenSize.height / camWidth;
//     double fittedScale = (baseScaleX > baseScaleY) ? baseScaleX : baseScaleY;
//
//     double offsetX = (screenSize.width - (camHeight * fittedScale)) / 2;
//     double offsetY = (screenSize.height - (camWidth * fittedScale)) / 2;
//
//     for (int i = 0; i < results.length; i++) {
//       final box = results[i]["box"];
//       String tagName = results[i]["tag"];
//       int trackId = assignments[i] ?? -1;
//
//       double objH = box[3] - box[1];
//       var analysis = analyzer.analyze(trackId, tagName, objH, camHeight);
//       String status = analysis['status']!;
//
//       if (status == "IGNORE") continue;
//
//       Color color = Colors.greenAccent;
//       double stroke = 2.0;
//
//       if (status == "WARNING") { color = Colors.orangeAccent; stroke = 4.0; }
//       if (status == "CRITICAL") { color = Colors.redAccent; stroke = 6.0; }
//       if (status == "INFO") { color = Colors.cyanAccent; stroke = 3.0; }
//
//       final paint = Paint()
//         ..color = color
//         ..style = PaintingStyle.stroke
//         ..strokeWidth = stroke;
//
//       double x1 = box[0] * fittedScale + offsetX;
//       double y1 = box[1] * fittedScale + offsetY;
//       double x2 = box[2] * fittedScale + offsetX;
//       double y2 = box[3] * fittedScale + offsetY;
//
//       Rect scaledRect = Rect.fromLTRB(x1, y1, x2, y2);
//       canvas.drawRect(scaledRect, paint);
//
//       String conf = "";
//       if (results[i]["box"].length > 4) conf = "${(results[i]["box"][4] * 100).toInt()}%";
//
//       final textPainter = TextPainter(
//         text: TextSpan(
//           text: "$tagName $conf",
//           style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
//         ),
//         textDirection: TextDirection.ltr,
//       );
//       textPainter.layout();
//
//       canvas.drawRRect(
//           RRect.fromRectAndRadius(
//               Rect.fromLTWH(scaledRect.left, scaledRect.top - 28, textPainter.width + 10, 28),
//               const Radius.circular(6)
//           ),
//           Paint()..color = color.withOpacity(0.85)
//       );
//       textPainter.paint(canvas, Offset(scaledRect.left + 5, scaledRect.top - 26));
//     }
//   }
//
//   @override
//   bool shouldRepaint(ResultsPainter oldDelegate) => true;
// }
//
//




import 'dart:async';
import 'dart:io'; // For File cleanup
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'osm_service.dart';
import 'gemini_service.dart';
import 'fish_audio_service.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Error loading .env: $e");
  }
  try {
    _cameras = await availableCameras();
  } catch (e) {
    _cameras = [];
  }
  runApp(const VisualGuideApp());
}

class VisualGuideApp extends StatelessWidget {
  const VisualGuideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Visual Guide',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // === HARDWARE ===
  CameraController? controller;
  late FlutterVision vision;

  // === SERVICES ===
  final OSMService _osmService = OSMService();
  late GeminiService _geminiService;
  late FishAudioService _fishAudioService;
  final DangerAnalyzer _analyzer = DangerAnalyzer();
  final StickyTracker _tracker = StickyTracker();

  // === STATE ===
  bool _isLoaded = false;
  bool _isActive = false;
  bool _isDetecting = false;
  String _statusText = "Initializing...";

  // === DATA ===
  List<Map<String, dynamic>> _yoloResults = [];
  Map<int, int> _trackAssignments = {};
  CameraImage? _cameraImage;
  String _globalDangerStatus = "SAFE";
  String _lastDangerStatus = "SAFE";

  // === AUDIO QUEUE SYSTEM ===
  String? _queuedEnvironmentText;
  DateTime? _lastDangerAudioTime;

  // === TIMERS ===
  Timer? _environmentTimer; // POI (Maps)
  Timer? _visualTimer;      // Vision (Images)

  // === DIAGNOSTICS ===
  int _fps = 0;
  int _inferenceMs = 0;
  DateTime? _lastFrameTime;

  @override
  void initState() {
    super.initState();
    _initializeSystem();
  }

  Future<void> _initializeSystem() async {
    final gKey = dotenv.env['GEMINI_API_KEY'] ?? dotenv.env['GEMINI_KEY'] ?? '';
    final fKey = dotenv.env['FISH_AUDIO_KEY'] ?? dotenv.env['FISH_AUDIO_API_KEY'] ?? '';

    if (gKey.isEmpty || fKey.isEmpty) {
      setState(() => _statusText = "Error: Missing API Keys");
      return;
    }
    _geminiService = GeminiService(gKey);
    _fishAudioService = FishAudioService(fKey);

    await [Permission.camera, Permission.location, Permission.microphone].request();

    if (_cameras.isEmpty) {
      setState(() => _statusText = "No Camera Found");
      return;
    }
    controller = CameraController(_cameras[0], ResolutionPreset.high, enableAudio: false);
    await controller!.initialize();

    vision = FlutterVision();
    await vision.loadYoloModel(
        modelPath: "assets/yolov8m.tflite",
        labels: "assets/labels.txt",
        modelVersion: "yolov8",
        quantization: false,
        numThreads: 4,
        useGpu: true
    );

    setState(() {
      _isLoaded = true;
      _statusText = "System Ready. Press Start.";
    });
  }

  void _toggleSystem() async {
    if (!_isLoaded) return;

    if (_isActive) {
      // STOP EVERYTHING
      setState(() {
        _isActive = false;
        _statusText = "System Idle";
        _yoloResults = [];
        _cameraImage = null;
        _globalDangerStatus = "SAFE";
      });
      _environmentTimer?.cancel();
      _visualTimer?.cancel();
      await controller?.stopImageStream();
      await _fishAudioService.stopAudio();
    } else {
      // START EVERYTHING
      setState(() {
        _isActive = true;
        _statusText = "Scanning...";
      });

      // 1. Fast Loop (YOLO - Danger)
      await controller?.startImageStream((image) => _yoloLoop(image));

      // 2. Slow Loop (Maps - Context) - Every 30s
      _environmentTimer = Timer.periodic(const Duration(seconds: 12), (t) => _mapsLoop());

      // 3. Medium Loop (Visual - Description) - Every 15s
      // We delay it slightly so it doesn't clash instantly with start
      Future.delayed(const Duration(seconds: 2), () {
        if (_isActive) {
          _visualLoop(); // Run once
          _visualTimer = Timer.periodic(const Duration(seconds: 33), (t) => _visualLoop());
        }
      });
    }
  }

  // === LOOP 1: FAST DANGER DETECTION (YOLO) ===
  void _yoloLoop(CameraImage image) async {
    if (_isDetecting || !_isActive) return;
    _isDetecting = true;
    final stopwatch = Stopwatch()..start();

    try {
      final result = await vision.yoloOnFrame(
        bytesList: image.planes.map((plane) => plane.bytes).toList(),
        imageHeight: image.height,
        imageWidth: image.width,
        iouThreshold: 0.4,
        confThreshold: 0.35,
        classThreshold: 0.4,
      );

      List<Rect> rects = result.map((r) => Rect.fromLTRB(r["box"][0], r["box"][1], r["box"][2], r["box"][3])).toList();
      Map<int, int> assignments = _tracker.update(rects);
      _analyzer.cleanOldHistory(assignments.values.toSet());

      String maxDanger = "SAFE";
      String dangerLabel = "";

      for (int i = 0; i < result.length; i++) {
        int? id = assignments[i];
        if (id == null) continue;
        double h = result[i]["box"][3] - result[i]["box"][1];
        var analysis = _analyzer.analyze(id, result[i]["tag"], h, image.height.toDouble());

        if (analysis["status"] == "CRITICAL") {
          maxDanger = "CRITICAL";
          dangerLabel = result[i]["tag"];
        } else if (analysis["status"] == "WARNING" && maxDanger != "CRITICAL") {
          maxDanger = "WARNING";
        }
      }

      // --- AUDIO PRIORITY LOGIC ---
      if (maxDanger == "CRITICAL") {
        if (_lastDangerAudioTime == null || DateTime.now().difference(_lastDangerAudioTime!).inSeconds > 3) {
          _lastDangerAudioTime = DateTime.now();
          debugPrint("🚨 DANGER INTERRUPT: $dangerLabel");
          _fishAudioService.textToSpeech("Stop! $dangerLabel ahead!", interrupt: true);
        }
      }
      else if (_lastDangerStatus == "CRITICAL" && maxDanger == "SAFE") {
        if (_queuedEnvironmentText != null) {
          debugPrint("✅ Safe. Playing queued description.");
          _fishAudioService.textToSpeech("Safe now. $_queuedEnvironmentText");
          _queuedEnvironmentText = null;
        }
      }
      _lastDangerStatus = maxDanger;
      // ----------------------------

      stopwatch.stop();
      if (mounted) {
        setState(() {
          _yoloResults = result;
          _trackAssignments = assignments;
          _cameraImage = image;
          _globalDangerStatus = maxDanger;
          _inferenceMs = stopwatch.elapsedMilliseconds;
          if (_lastFrameTime != null) {
            int gap = DateTime.now().difference(_lastFrameTime!).inMilliseconds;
            if (gap > 0) _fps = (1000 / gap).round();
          }
          _lastFrameTime = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint("YOLO Error: $e");
    } finally {
      _isDetecting = false;
    }
  }

  // // === LOOP 2: VISUAL DESCRIPTION (GEMINI IMAGES) ===
  // Future<void> _visualLoop() async {
  //   if (!_isActive || controller == null || !controller!.value.isInitialized) return;
  //   if (_globalDangerStatus == "CRITICAL") return; // Don't distract user in danger
  //
  //   try {
  //     // 1. Pause stream briefly to take a picture (safest way to get clean JPG)
  //     // Note: on some phones this might stutter the video feed for 0.2s
  //     await controller?.stopImageStream();
  //
  //     debugPrint("📸 Taking snapshot for Gemini...");
  //     XFile imageFile = await controller!.takePicture();
  //
  //     // Resume stream immediately
  //     await controller?.startImageStream((image) => _yoloLoop(image));
  //
  //     // 2. Send to Gemini
  //     debugPrint("📤 Sending photo to Gemini...");
  //     String desc = await _geminiService.describeEnvironmentFromImage(imageFile);
  //
  //     // 3. Cleanup File
  //     File(imageFile.path).delete();
  //
  //     // 4. Speak
  //     if (_globalDangerStatus == "CRITICAL") {
  //       _queuedEnvironmentText = desc;
  //     } else {
  //       debugPrint("🔊 Speaking Vision: $desc");
  //       _fishAudioService.textToSpeech(desc);
  //     }
  //
  //   } catch (e) {
  //     debugPrint("Visual Loop Error: $e");
  //     // Ensure stream resumes even if error
  //     if (controller != null && !controller!.value.isStreamingImages) {
  //       await controller?.startImageStream((image) => _yoloLoop(image));
  //     }
  //   }
  // }
  //
  // // === LOOP 3: MAP CONTEXT (OSM) ===
  // Future<void> _mapsLoop() async {
  //   if (!_isActive || _globalDangerStatus == "CRITICAL") return;
  //
  //   try {
  //     Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  //     List<POI> pois = await _osmService.getNearbyPOIs(pos.latitude, pos.longitude);
  //     final topPois = pois.take(4).toList();
  //
  //     if (topPois.isNotEmpty) {
  //       String desc = await _geminiService.convertToConversation(topPois);
  //       debugPrint("🔊 Speaking Map: $desc");
  //       // Low priority speech
  //       _fishAudioService.textToSpeech(desc, interrupt: false);
  //     }
  //   } catch (e) {
  //     debugPrint("Map Loop Error: $e");
  //   }
  // }
  // === VISUAL LOOP (Medium Priority) ===
  Future<void> _visualLoop() async {
    if (!_isActive || controller == null || !controller!.value.isInitialized) return;

    // If Danger is active, don't even queue visuals. Focus on safety.
    if (_globalDangerStatus == "CRITICAL") return;

    try {
      await controller?.stopImageStream();
      XFile imageFile = await controller!.takePicture();
      await controller?.startImageStream((image) => _yoloLoop(image));

      String desc = await _geminiService.describeEnvironmentFromImage(imageFile);
      File(imageFile.path).delete();

      // Add to Queue (interrupt: false)
      debugPrint("📸 Queuing Visual Description...");
      _fishAudioService.textToSpeech(desc, interrupt: false);

    } catch (e) {
      debugPrint("Visual Error: $e");
    }
  }

  // === MAP LOOP (Low Priority) ===
  Future<void> _mapsLoop() async {
    if (!_isActive || _globalDangerStatus == "CRITICAL") return;

    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      List<POI> pois = await _osmService.getNearbyPOIs(pos.latitude, pos.longitude);
      final topPois = pois.take(3).toList(); // Take top 3

      if (topPois.isNotEmpty) {
        String desc = await _geminiService.convertToConversation(topPois);

        // Add to Queue (interrupt: false)
        // If Visual is speaking, this will wait until Visual is done!
        debugPrint("🗺️ Queuing Map Description...");
        _fishAudioService.textToSpeech("Nearby: $desc", interrupt: false);
      }
    } catch (e) {
      debugPrint("Map Error: $e");
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    vision.closeYoloModel();
    _environmentTimer?.cancel();
    _visualTimer?.cancel();
    _fishAudioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_statusText.contains("Error"))
              const Icon(Icons.error, color: Colors.red, size: 50)
            else
              const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(_statusText, style: const TextStyle(color: Colors.white)),
          ],
        )),
      );
    }

    final Size screenSize = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // 1. CAMERA
          if (controller != null && controller!.value.isInitialized)
            SizedBox(
              width: screenSize.width,
              height: screenSize.height,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller!.value.previewSize!.height,
                  height: controller!.value.previewSize!.width,
                  child: CameraPreview(controller!),
                ),
              ),
            ),

          // 2. BOXES
          if (_isActive && _cameraImage != null)
            SizedBox(
              width: screenSize.width,
              height: screenSize.height,
              child: CustomPaint(
                painter: ResultsPainter(
                    _yoloResults,
                    _trackAssignments,
                    _analyzer,
                    _cameraImage!.height.toDouble(),
                    _cameraImage!.width.toDouble(),
                    screenSize
                ),
              ),
            ),

          // 3. HUD
          Positioned(
            top: 50, left: 20, right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                  color: _getStatusColor().withOpacity(0.9),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [const BoxShadow(color: Colors.black45, blurRadius: 10)]
              ),
              child: Text(
                _isActive ? (_globalDangerStatus == "SAFE" ? "PATH CLEAR" : _globalDangerStatus) : "SYSTEM IDLE",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // 4. BUTTON
          Positioned(
            bottom: 40, left: 20, right: 20,
            child: SizedBox(
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _toggleSystem,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _isActive ? Colors.redAccent : Colors.blueAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 10
                ),
                icon: Icon(_isActive ? Icons.stop_circle : Icons.play_circle, size: 30),
                label: Text(
                  _isActive ? "STOP GUIDING" : "START GUIDING",
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 110, left: 20,
            child: _isActive ? Text(
              "FPS: $_fps | Inf: ${_inferenceMs}ms",
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ) : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    if (!_isActive) return Colors.grey;
    if (_globalDangerStatus == "CRITICAL") return Colors.red;
    if (_globalDangerStatus == "WARNING") return Colors.orange;
    return Colors.green;
  }
}

// ==================== HELPER CLASSES ====================

class DangerAnalyzer {
  static const double DANGER_ZONE_RATIO = 0.45;
  static const double APPROACH_THRESHOLD = 0.05;
  final List<String> targetClasses = ["person", "bicycle", "car", "motorcycle", "bus", "train", "truck", "laptop", "tv", "cell phone"];
  final Map<int, List<double>> _history = {};

  Map<String, String> analyze(int trackId, String label, double currentH, double frameH) {
    if (!targetClasses.contains(label)) return {"status": "IGNORE", "message": ""};

    double heightRatio = currentH / frameH;
    if (heightRatio > DANGER_ZONE_RATIO) return {"status": "CRITICAL", "message": "STOP! $label"};

    if (!_history.containsKey(trackId)) _history[trackId] = [];
    _history[trackId]!.add(currentH);
    if (_history[trackId]!.length > 10) _history[trackId]!.removeAt(0);

    if (_history[trackId]!.length >= 3) {
      double growth = (currentH - _history[trackId]![0]) / _history[trackId]![0];
      if (growth > APPROACH_THRESHOLD) return {"status": "WARNING", "message": "Approaching"};
    }

    if (["laptop", "tv", "cell phone"].contains(label)) return {"status": "INFO", "message": "Detected"};
    return {"status": "SAFE", "message": ""};
  }
  void cleanOldHistory(Set<int> activeIds) => _history.removeWhere((key, value) => !activeIds.contains(key));
}

class StickyTracker {
  int _nextId = 0;
  final Map<int, Offset> _objects = {};
  final Map<int, int> _disappearedCount = {};

  Map<int, int> update(List<Rect> rects) {
    if (rects.isEmpty) {
      _disappearedCount.updateAll((key, value) => value + 1);
      _cleanup();
      return {};
    }
    List<Offset> inputs = rects.map((r) => r.center).toList();
    Map<int, int> assignments = {};
    Set<int> usedIds = {};
    Set<int> usedInputs = {};

    if (_objects.isNotEmpty) {
      for (int i = 0; i < inputs.length; i++) {
        int? bestId;
        double minDst = 100.0;
        _objects.forEach((id, center) {
          if (usedIds.contains(id)) return;
          double dst = (inputs[i] - center).distance;
          if (dst < minDst) { minDst = dst; bestId = id; }
        });
        if (bestId != null) {
          assignments[i] = bestId!;
          _objects[bestId!] = inputs[i];
          _disappearedCount[bestId!] = 0;
          usedIds.add(bestId!);
          usedInputs.add(i);
        }
      }
    }

    for (int i = 0; i < inputs.length; i++) {
      if (!usedInputs.contains(i)) {
        int id = _nextId++;
        _objects[id] = inputs[i];
        _disappearedCount[id] = 0;
        assignments[i] = id;
      }
    }
    _objects.keys.where((id) => !usedIds.contains(id)).forEach((id) => _disappearedCount[id] = (_disappearedCount[id] ?? 0) + 1);
    _cleanup();
    return assignments;
  }
  void _cleanup() {
    _objects.removeWhere((id, _) => (_disappearedCount[id] ?? 0) > 10);
    _disappearedCount.removeWhere((id, c) => c > 10);
  }
}

class ResultsPainter extends CustomPainter {
  final List<Map<String, dynamic>> results;
  final Map<int, int> assignments;
  final DangerAnalyzer analyzer;
  final double h;
  final double w;
  final Size screen;

  ResultsPainter(this.results, this.assignments, this.analyzer, this.h, this.w, this.screen);

  @override
  void paint(Canvas canvas, Size size) {
    double scale = screen.width / h > screen.height / w ? screen.width / h : screen.height / w;
    double dx = (screen.width - h * scale) / 2;
    double dy = (screen.height - w * scale) / 2;

    for (int i = 0; i < results.length; i++) {
      final box = results[i]["box"];
      int id = assignments[i] ?? -1;
      var analysis = analyzer.analyze(id, results[i]["tag"], box[3] - box[1], h);
      if (analysis['status'] == "IGNORE") continue;

      Color c = analysis['status'] == "CRITICAL" ? Colors.red : (analysis['status'] == "WARNING" ? Colors.orange : Colors.green);
      final paint = Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 3.0;

      Rect r = Rect.fromLTRB(box[0] * scale + dx, box[1] * scale + dy, box[2] * scale + dx, box[3] * scale + dy);
      canvas.drawRect(r, paint);

      TextPainter(
          text: TextSpan(text: "${results[i]['tag']} ${analysis['status']}", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr
      )..layout()..paint(canvas, Offset(r.left, r.top - 20));
    }
  }
  @override
  bool shouldRepaint(ResultsPainter old) => true;
}