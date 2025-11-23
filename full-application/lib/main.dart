import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'osm_service.dart';
import 'gemini_service.dart';
import 'fish_audio_service.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables
  await dotenv.load(fileName: ".env");
  
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
  CameraController? controller;
  final OSMService _osmService = OSMService();
  late final GeminiService _geminiService;
  late final FishAudioService _fishAudioService;

  // State variables
  String _statusText = "Initializing...";
  List<POI> _nearbyPOIs = [];
  bool _isScanning = false;
  bool _isCameraActive = false;
  Timer? _osmTimer;
  Timer? _geminiTimer;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Initialize Gemini service with API key
    final geminiApiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (geminiApiKey.isEmpty) {
      setState(() => _statusText = "Error: Missing Gemini API key");
      return;
    }
    _geminiService = GeminiService(geminiApiKey);
    
    // Initialize Fish Audio service with API key
    final fishApiKey = dotenv.env['FISH_AUDIO_KEY'] ?? '';
    if (fishApiKey.isEmpty) {
      setState(() => _statusText = "Error: Missing Fish Audio API key");
      return;
    }
    _fishAudioService = FishAudioService(fishApiKey);
    
    await _requestPermissions();
    await _initCamera();
    await _startLocationTracking();

    setState(() {
      _isScanning = true;
      _isCameraActive = true;
      _statusText = "Ready";
    });

    // Start OSM POI scanning every 5 seconds
    _osmTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchPOIs();
    });

    // Start Gemini + Fish Audio pipeline every 60 seconds
    _geminiTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      _processWithGeminiAndAudio();
    });

    // Perform first POI fetch immediately
    _fetchPOIs();
    
    // Perform first Gemini/Audio processing after a short delay
    Future.delayed(const Duration(seconds: 2), () {
      _processWithGeminiAndAudio();
    });
  }

  Future<void> _requestPermissions() async {
    await [Permission.camera, Permission.location].request();
  }

  Future<void> _initCamera() async {
    if (_cameras.isEmpty) {
      print("No cameras available");
      return;
    }

    // Select back camera (rear-facing)
    final backCamera = _cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );
    
    controller = CameraController(
      backCamera, 
      ResolutionPreset.high,
      enableAudio: false,
    );
    
    try {
      await controller!.initialize();
      print("Camera initialized successfully");
      if (mounted) setState(() {});
    } catch (e) {
      print("Camera initialization error: $e");
    }
  }

  Future<void> _startLocationTracking() async {
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print("Location services are disabled");
      setState(() => _statusText = "Location services disabled. Please enable location.");
      return;
    }

    // Check location permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print("Location permission denied");
        setState(() => _statusText = "Location permission denied");
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print("Location permission denied forever");
      setState(() => _statusText = "Location permission permanently denied");
      return;
    }

    // Get initial position
    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      print("Initial position: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}");
    } catch (e) {
      print("Error getting initial position: $e");
    }

    // Listen to location stream
    Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10
        )
    ).listen((Position position) {
      _currentPosition = position;
      print("Position update: ${position.latitude}, ${position.longitude}");
    });
  }

  /// Fetch POIs from OpenStreetMap (called every 5 seconds)
  Future<void> _fetchPOIs() async {
    if (!mounted) {
      print("fetchPOIs: Widget not mounted");
      return;
    }
    
    if (_currentPosition == null) {
      print("fetchPOIs: No location available yet");
      return;
    }

    print("=== Fetching POIs from OSM (5s cycle) ===");
    print("Current location: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}");

    try {
      // Step 1: Fetch POIs from OpenStreetMap
      print("Fetching POIs from OpenStreetMap...");
      final results = await _osmService.getNearbyPOIs(
          _currentPosition!.latitude,
          _currentPosition!.longitude
      );
      print("Found ${results.length} POIs from OSM");

      final top5 = results.take(5).toList();
      
      if (top5.isEmpty) {
        print("No POIs found nearby");
        return;
      }
      
      print("Top 5 POIs: ${top5.map((p) => p.name).toList()}");

      // Update state with the latest POIs
      if (mounted) {
        setState(() {
          _nearbyPOIs = top5;
        });
      }
      
      print("=== OSM fetch complete ===");
    } catch (e) {
      print("OSM fetch error: $e");
    }
  }

  /// Process POIs with Gemini and Fish Audio (called every 60 seconds)
  Future<void> _processWithGeminiAndAudio() async {
    if (!mounted) {
      print("processWithGeminiAndAudio: Widget not mounted");
      return;
    }

    if (_nearbyPOIs.isEmpty) {
      print("processWithGeminiAndAudio: No POIs available to process");
      return;
    }

    print("=== Starting Gemini + Fish Audio pipeline (60s cycle) ===");
    print("Processing ${_nearbyPOIs.length} POIs: ${_nearbyPOIs.map((p) => p.name).toList()}");

    try {
      // Step 2: Convert to conversational text using Gemini
      print("Step 1: Sending to Gemini API for conversational text...");
      final conversationalText = await _geminiService.convertToConversation(_nearbyPOIs);
      print("Gemini response: $conversationalText");

      // Step 3: Convert text to speech using Fish Audio
      print("Step 2: Sending to Fish Audio API for TTS...");
      await _fishAudioService.textToSpeech(conversationalText);
      print("Fish Audio TTS complete");
      
      print("=== Gemini + Fish Audio pipeline complete ===");
    } catch (e) {
      print("Gemini/Audio processing error: $e");
    }
  }

  void _toggleCamera() {
    setState(() {
      _isCameraActive = !_isCameraActive;
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    _osmTimer?.cancel();
    _geminiTimer?.cancel();
    _fishAudioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 7,
              child: Container(
                color: Colors.black,
                child: _isCameraActive && controller != null && controller!.value.isInitialized
                    ? ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.center,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: MediaQuery.of(context).size.width,
                              height: MediaQuery.of(context).size.width * controller!.value.aspectRatio,
                              child: CameraPreview(controller!),
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.camera_alt,
                              size: 80,
                              color: Colors.white30,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _isCameraActive ? 'Starting camera...' : 'Camera inactive',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            
            // Divider
            Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF667eea),
                    const Color(0xFF764ba2),
                  ],
                ),
              ),
            ),
            
            // BOTTOM SECTION: Start/Stop Button
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF1A1A1A),
                      const Color(0xFF2A2A2A),
                    ],
                  ),
                ),
                child: Center(
                  child: ElevatedButton(
                    onPressed: _toggleCamera,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 20),
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ).copyWith(
                      backgroundColor: MaterialStateProperty.resolveWith<Color>(
                        (Set<MaterialState> states) {
                          return Colors.transparent;
                        },
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _isCameraActive
                              ? [
                                  const Color(0xFFea5455),
                                  const Color(0xFFf07167),
                                ]
                              : [
                                  const Color(0xFF667eea),
                                  const Color(0xFF764ba2),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: (_isCameraActive 
                                ? const Color(0xFFea5455) 
                                : const Color(0xFF667eea)).withOpacity(0.5),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isCameraActive ? Icons.stop : Icons.play_arrow,
                            color: Colors.white,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _isCameraActive ? 'STOP' : 'START',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
