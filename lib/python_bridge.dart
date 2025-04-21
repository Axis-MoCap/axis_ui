import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';

class PythonBridge {
  // Singleton pattern
  static final PythonBridge _instance = PythonBridge._internal();
  factory PythonBridge() => _instance;
  PythonBridge._internal();

  // Scripts directory
  final String _scriptsPath = '/home/pi/axis_mocap/scripts';

  // Active processes
  final Map<String, Process> _activeProcesses = {};

  // Stream controllers for process output
  final Map<String, StreamController<String>> _outputControllers = {};

  // Get stream for a specific process
  Stream<String>? getProcessStream(String processId) {
    return _outputControllers[processId]?.stream;
  }

  // Check if a process is running
  bool isProcessRunning(String processId) {
    return _activeProcesses.containsKey(processId);
  }

  // Execute Python script and return a stream of its output
  Future<Stream<String>?> runPythonScript({
    required String scriptName,
    List<String> args = const [],
    String processId = '',
    bool captureOutput = true,
  }) async {
    try {
      final id = processId.isEmpty ? scriptName : processId;

      // Check if we already have this process running
      if (_activeProcesses.containsKey(id)) {
        return _outputControllers[id]?.stream;
      }

      // Create stream controller for process output
      if (captureOutput) {
        _outputControllers[id] = StreamController<String>.broadcast();
      }

      // Build the command and arguments
      final script = '$_scriptsPath/$scriptName';
      final command = 'python3';
      final commandArgs = [script, ...args];

      debugPrint('Running: $command ${commandArgs.join(' ')}');

      // Start the process
      final process = await Process.start(command, commandArgs);
      _activeProcesses[id] = process;

      // Handle process output
      if (captureOutput) {
        // Handle stdout
        process.stdout.transform(const SystemEncoding().decoder).listen((data) {
          _outputControllers[id]?.add(data);
          debugPrint('[$id] stdout: $data');
        });

        // Handle stderr
        process.stderr.transform(const SystemEncoding().decoder).listen((data) {
          _outputControllers[id]?.add('ERROR: $data');
          debugPrint('[$id] stderr: $data');
        });
      }

      // Handle process exit
      process.exitCode.then((exitCode) {
        debugPrint('[$id] process exited with code $exitCode');
        _activeProcesses.remove(id);

        if (captureOutput) {
          _outputControllers[id]
              ?.add('Process completed with exit code: $exitCode');
          _outputControllers[id]?.close();
          _outputControllers.remove(id);
        }
      });

      return captureOutput ? _outputControllers[id]?.stream : null;
    } catch (e) {
      debugPrint('Error running Python script: $e');
      return null;
    }
  }

  // Kill a running process
  Future<bool> killProcess(String processId) async {
    if (_activeProcesses.containsKey(processId)) {
      try {
        _activeProcesses[processId]?.kill();
        _activeProcesses.remove(processId);

        if (_outputControllers.containsKey(processId)) {
          _outputControllers[processId]?.add('Process terminated by user');
          _outputControllers[processId]?.close();
          _outputControllers.remove(processId);
        }

        return true;
      } catch (e) {
        debugPrint('Error killing process: $e');
        return false;
      }
    }
    return false;
  }

  // Kill all running processes
  Future<void> killAllProcesses() async {
    final processes = List<String>.from(_activeProcesses.keys);
    for (final id in processes) {
      await killProcess(id);
    }
  }
}
