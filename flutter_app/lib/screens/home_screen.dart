import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import '../services/camera_service.dart';
import '../services/location_service.dart';
import '../services/osm_service.dart';
import '../models/poi.dart';
import '../widgets/poi_list_item.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final CameraService _cameraService = CameraService();
  final LocationService _locationService = LocationService();
  final OSMService _osmService = OSMService();

  String _locationStatus = 'Starting...';
  String _apiStatus = 'Initializing...';
  List<POI> _pois = [];
  Timer? _scanTimer;
  bool _isScanning = false;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      setState(() {
        _locationStatus = 'Getting location...';
        _apiStatus = 'Initializing...';
      });

      await _cameraService.initialize();
      setState(() {
        _apiStatus = 'Camera ready, getting location...';
      });

      _currentPosition = await _locationService.getCurrentPosition();
      setState(() {
        _locationStatus =
            'Location: ${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}';
      });

      // Start scanning loop
      _isScanning = true;
      _scan(); // First scan immediately
      _scanTimer = Timer.periodic(const Duration(seconds: 5), (timer) => _scan());

      // Watch position updates
      _locationService.getPositionStream().listen((position) {
        setState(() {
          _currentPosition = position;
          _locationStatus =
              'Location: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
        });
      });
    } catch (e) {
      setState(() {
        _locationStatus = 'Error: $e';
        _apiStatus = 'Failed to start';
      });
      print('Initialization error: $e');
    }
  }

  Future<void> _scan() async {
    if (!_isScanning || _currentPosition == null) return;

    try {
      final pois = await _osmService.getNearbyPOIs(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );

      if (mounted) {
        setState(() {
          _pois = pois;
          _apiStatus = 'Found ${pois.length} nearby locations';
        });
      }
    } catch (e) {
      print('Scan error: $e');
    }
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Feed
          if (_cameraService.controller != null &&
              _cameraService.controller!.value.isInitialized)
            SizedBox.expand(
              child: CameraPreview(_cameraService.controller!),
            )
          else
            const Center(child: CircularProgressIndicator()),

          // Status Overlay
          Positioned(
            top: 40,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusBadge(_locationStatus),
                const SizedBox(height: 10),
                _buildStatusBadge(_apiStatus),
              ],
            ),
          ),

          // Output Panel (POI List)
          Positioned(
            top: 120,
            right: 20,
            width: 300,
            bottom: 140, // Leave space for controls if needed
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nearby Locations',
                    style: TextStyle(
                      color: Color(0xFF667eea),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _pois.isEmpty
                        ? const Text(
                            'Scanning...',
                            style: TextStyle(color: Colors.white70),
                          )
                        : ListView.builder(
                            itemCount: _pois.length,
                            itemBuilder: (context, index) {
                              return POIListItem(poi: _pois[index]);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    );
  }
}
