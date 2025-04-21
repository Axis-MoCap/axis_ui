import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'python_bridge.dart';

enum CameraType {
  raspberryPi,
  webCamera,
  none,
}

class CameraService {
  // Singleton pattern
  static final CameraService _instance = CameraService._internal();
  factory CameraService() => _instance;

  CameraService._internal() {
    _pythonBridge = PythonBridge();
    _init();
  }

  // Python bridge for camera access
  late final PythonBridge _pythonBridge;

  // Camera state
  CameraType _cameraType = CameraType.none;
  CameraType get cameraType => _cameraType;
  bool _isCameraInitialized = false;
  bool get isCameraInitialized => _isCameraInitialized;

  // Stream controllers for camera status
  final _cameraStatusController = StreamController<CameraType>.broadcast();
  Stream<CameraType> get cameraStatusStream => _cameraStatusController.stream;

  // Camera detection process
  StreamSubscription? _detectionSubscription;
  String? _cameraPath;

  // Initialize and detect available cameras
  Future<void> _init() async {
    await detectCamera();
  }

  // Detect available cameras
  Future<CameraType> detectCamera() async {
    try {
      // First try to detect Raspberry Pi camera
      final piCameraStream = await _pythonBridge.runPythonScript(
        scriptName: 'detect_camera.py',
        args: ['--type=raspberry'],
        processId: 'detect_pi_camera',
      );

      if (piCameraStream != null) {
        bool found = false;
        await for (final output in piCameraStream) {
          if (output.contains('CAMERA_FOUND:')) {
            _cameraPath = output.split('CAMERA_FOUND:')[1].trim();
            _cameraType = CameraType.raspberryPi;
            found = true;
            break;
          }
        }

        if (found) {
          _isCameraInitialized = true;
          _cameraStatusController.add(_cameraType);
          debugPrint('Raspberry Pi camera found at: $_cameraPath');
          return _cameraType;
        }
      }

      // If Pi camera not found, try to detect web camera
      final webCameraStream = await _pythonBridge.runPythonScript(
        scriptName: 'detect_camera.py',
        args: ['--type=webcam'],
        processId: 'detect_web_camera',
      );

      if (webCameraStream != null) {
        bool found = false;
        await for (final output in webCameraStream) {
          if (output.contains('CAMERA_FOUND:')) {
            _cameraPath = output.split('CAMERA_FOUND:')[1].trim();
            _cameraType = CameraType.webCamera;
            found = true;
            break;
          }
        }

        if (found) {
          _isCameraInitialized = true;
          _cameraStatusController.add(_cameraType);
          debugPrint('Web camera found at: $_cameraPath');
          return _cameraType;
        }
      }

      // No camera found
      _cameraType = CameraType.none;
      _isCameraInitialized = false;
      _cameraStatusController.add(_cameraType);
      debugPrint('No camera found');
      return _cameraType;
    } catch (e) {
      debugPrint('Error detecting camera: $e');
      _cameraType = CameraType.none;
      _isCameraInitialized = false;
      _cameraStatusController.add(_cameraType);
      return _cameraType;
    }
  }

  // Start camera stream
  Future<Stream<Image>?> startCameraStream() async {
    if (_cameraType == CameraType.none) {
      await detectCamera();
      if (_cameraType == CameraType.none) {
        return null;
      }
    }

    try {
      final streamController = StreamController<Image>.broadcast();

      // Start the camera streaming script
      final cameraStream = await _pythonBridge.runPythonScript(
        scriptName: 'stream_camera.py',
        args: [
          '--camera_path=$_cameraPath',
          '--type=${_cameraType == CameraType.raspberryPi ? "raspberry" : "webcam"}',
        ],
        processId: 'camera_stream',
        captureOutput: true,
      );

      if (cameraStream == null) {
        return null;
      }

      // Process the frame data from the script
      // Note: In a real implementation, you would process binary frame data
      // This is a placeholder for the actual frame processing logic
      _detectionSubscription = cameraStream.listen(
        (data) {
          // In a real implementation, this would process binary image data
          // For demonstration, we'll just create a placeholder image
          // You'd need a more complex implementation to handle actual video frames
          streamController.add(Image.asset('assets/placeholder_frame.png'));
        },
        onError: (error) {
          debugPrint('Camera stream error: $error');
        },
        onDone: () {
          streamController.close();
        },
      );

      return streamController.stream;
    } catch (e) {
      debugPrint('Error starting camera stream: $e');
      return null;
    }
  }

  // Stop camera stream
  Future<void> stopCameraStream() async {
    await _pythonBridge.killProcess('camera_stream');
    await _detectionSubscription?.cancel();
    _detectionSubscription = null;
  }

  // Dispose
  void dispose() {
    stopCameraStream();
    _cameraStatusController.close();
  }
}

// Placeholder component for camera not found
class CameraNotFound extends StatelessWidget {
  const CameraNotFound({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_off,
              color: Colors.red,
              size: 48,
            ),
            SizedBox(height: 16),
            Text(
              'Camera Not Found',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Please connect a camera and restart the app',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
