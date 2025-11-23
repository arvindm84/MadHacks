import 'package:camera/camera.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;

  Future<void> initialize() async {
    _cameras = await availableCameras();
    if (_cameras != null && _cameras!.isNotEmpty) {
      // Use the first available camera (usually back camera)
      _controller = CameraController(_cameras![0], ResolutionPreset.high);
      await _controller!.initialize();
    } else {
      throw Exception('No cameras available');
    }
  }

  CameraController? get controller => _controller;

  void dispose() {
    _controller?.dispose();
  }
}
