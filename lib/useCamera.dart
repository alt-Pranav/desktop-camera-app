import 'dart:async';

import 'package:flutter/material.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';

import 'package:flutter/services.dart';

class UseCamera extends StatefulWidget {
  const UseCamera({Key? key}) : super(key: key);

  @override
  State<UseCamera> createState() => _UseCameraState();
}

class _UseCameraState extends State<UseCamera> {
  /// Stores current state info of the camera.
  String _cameraInfo = 'Unknown';

  /// Stores list of cameras found on device.
  List<CameraDescription> _cameras = [];

  /// Used to iter through _cameras.
  int _cameraIndex = 0;

  /// Used to store camera ID.
  int _cameraId = -1;

  /// true if camera is initialised, otherwise false.
  bool _initialised = false;

  /// true if video is being recorded, otherwise false.
  bool _recording = false;

  /// true if a timed video is being recorded, otherwise false.
  bool _recordingTimed = false;

  /// true if audio is enabled for recording, otherwise false.
  bool _recordAudio = true;

  /// true if preview is paused i.e. camera is paused
  /// otherwise false.
  bool _previewPaused = false;

  /// sets preview size of the camera, can be null.
  Size? _previewSize;

  /// sets resolution of the preview
  /// initialised to very high i.e. 1920 x 1080.
  ResolutionPreset _resolutionPreset = ResolutionPreset.veryHigh;

  /// Subscribes to camera error stream.
  StreamSubscription<CameraErrorEvent>? _errorStreamSubscription;

  /// Subscribes to camera closing stream i.e. on dispose.
  StreamSubscription<CameraClosingEvent>? _cameraClosingStreamSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsFlutterBinding.ensureInitialized();

    /// Ensures that at first the available cameras are found.
    _fetchCameras();
  }

  @override
  void dispose() {
    /// ends current preview
    _disposeCurrentCamera();

    /// both the streams are canceled and reset to null just in case

    _errorStreamSubscription?.cancel();
    _errorStreamSubscription = null;

    _cameraClosingStreamSubscription?.cancel();
    _cameraClosingStreamSubscription = null;
    super.dispose();
  }

  /// Fetch list of available cameras from camera_windows_plugin
  Future<void> _fetchCameras() async {
    String cameraInfo;
    List<CameraDescription> cameras = [];

    int cameraIndex = 0;

    try {
      cameras = await CameraPlatform.instance.availableCameras();
      if (cameras.isEmpty) {
        cameraInfo = 'No available cameras';
      } else {
        cameraIndex = _cameraIndex % cameras.length;
        cameraInfo = "Found camera: ${cameras[cameraIndex].name}";
      }
    } on PlatformException catch (e) {
      cameraInfo = 'Failed to get cameras: ${e.code} : ${e.message}';
    }

    if (mounted) {
      setState(() {
        _cameraIndex = cameraIndex;
        _cameraInfo = cameraInfo;
        _cameras = cameras;
      });
    }
  }

  /// Initialises the camera on device
  Future<void> _initiliaseCamera() async {
    assert(!_initialised);

    if (_cameras.isEmpty) {
      return;
    }

    int cameraId = -1;
    try {
      final int cameraIndex = _cameraIndex % _cameras.length;
      final CameraDescription camera = _cameras[cameraIndex];

      cameraId = await CameraPlatform.instance
          .createCamera(camera, _resolutionPreset, enableAudio: _recordAudio);

      _errorStreamSubscription?.cancel();
      _errorStreamSubscription = CameraPlatform.instance
          .onCameraError(cameraId)
          .listen(_onCameraError);

      _cameraClosingStreamSubscription?.cancel();
      _cameraClosingStreamSubscription = CameraPlatform.instance
          .onCameraClosing(cameraId)
          .listen(_onCameraClosing);

      final Future<CameraInitializedEvent> initiliazed =
          CameraPlatform.instance.onCameraInitialized(cameraId).first;

      await CameraPlatform.instance.initializeCamera(
        cameraId,
        imageFormatGroup: ImageFormatGroup.unknown,
      );

      final CameraInitializedEvent event = await initiliazed;

      _previewSize = Size(
        event.previewWidth,
        event.previewHeight,
      );

      if (mounted) {
        setState(() {
          _initialised = true;
          _cameraId = cameraId;
          _cameraIndex = cameraIndex;
          _cameraInfo = "Capturing Camera: ${camera.name}";
        });
      }
    } on CameraException catch (e) {
      try {
        /// in case the streams are running
        /// i.e. the cameraId was successfully set and the error occurred later
        if (cameraId >= 0) {
          await CameraPlatform.instance.dispose(cameraId);
        }
      } on CameraException catch (e) {
        debugPrint('Failed to dispose camera: ${e.code}: ${e.description}');
      }

      /// Reset State
      if (mounted) {
        setState(() {
          _initialised = false;
          _cameraId = -1;
          _cameraIndex = 0;
          _previewSize = null;
          _recording = false;
          _recordingTimed = false;
          _cameraInfo =
              'Failed to initliase camera: ${e.code}: ${e.description}';
        });
      }
    }
  }

  /// Disposes the current camera view
  Future<void> _disposeCurrentCamera() async {
    if (_cameraId >= 0 && _initialised) {
      try {
        await CameraPlatform.instance.dispose(_cameraId);

        if (mounted) {
          setState(() {
            _initialised = false;
            _cameraId = -1;
            _cameraIndex = 0;
            _previewSize = null;
            _recording = false;
            _recordingTimed = false;
            _cameraInfo = 'Camera Disposed';
          });
        }
      } on CameraException catch (e) {
        if (mounted) {
          setState(() {
            _cameraInfo =
                'Failed to dispose camera: ${e.code}: ${e.description}';
          });
        }
      }
    }
  }

  /// Builds the camera preview using the _previewSize defined.
  Widget _buildPreview() {
    return CameraPlatform.instance.buildPreview(_cameraId);
  }

  /// Takes a photo and stores it in the Photos folder in C:/Users/OneDrive/Photos
  Future<void> _takePicture() async {
    final XFile _file = await CameraPlatform.instance.takePicture(_cameraId);
    _showInSnackBar("Picture captured to: ${_file.path}");
  }

  /// Records a timed video and stores it in the Videos folder in C:/Users/OneDrive/Videos
  Future<void> _recordTimed(int seconds) async {
    if (_initialised && _cameraId >= 0 && !_recordingTimed) {
      CameraPlatform.instance
          .onVideoRecordedEvent(_cameraId)
          .first
          .then((event) async {
        if (mounted) {
          setState(() {
            _recordingTimed = false;
          });

          _showInSnackBar('Video captured to: ${event.file.path}');
        }
      });

      await CameraPlatform.instance.startVideoRecording(
        _cameraId,
        maxVideoDuration: Duration(seconds: seconds),
      );

      if (mounted) {
        setState(() {
          _recordingTimed = true;
        });
      }
    }
  }

  /// If a video is being recorded, this will stop it. Else, it will start recording.
  Future<void> _toggleRecord() async {
    if (_initialised && _cameraId >= 0) {
      if (_recordingTimed) {
        /// Request to stop timed recording short
        await CameraPlatform.instance.stopVideoRecording(_cameraId);
      } else {
        if (!_recording) {
          await CameraPlatform.instance.startVideoRecording(_cameraId);
        } else {
          final XFile _file =
              await CameraPlatform.instance.stopVideoRecording(_cameraId);

          _showInSnackBar('Video captured to: ${_file.path}');
        }
        if (mounted) {
          setState(() {
            _recording = !_recording;
          });
        }
      }
    }
  }

  /// This switches the preview between paused and unpaused.
  Future<void> _togglePreview() async {
    if (_initialised && _cameraId >= 0) {
      if (!_previewPaused) {
        await CameraPlatform.instance.pausePreview(_cameraId);
      } else {
        await CameraPlatform.instance.resumePreview(_cameraId);
      }

      if (mounted) {
        setState(() {
          _previewPaused = !_previewPaused;
        });
      }
    }
  }

  /// This switches camera provided the device is connected to multiple cameras.
  Future<void> _switchCamera() async {
    if (_cameras.isNotEmpty) {
      /// select next index
      _cameraIndex = (_cameraIndex + 1) % _cameras.length;
      if (_initialised && _cameraId >= 0) {
        await _disposeCurrentCamera();
        await _fetchCameras();
        if (_cameras.isNotEmpty) {
          await _initiliaseCamera();
        } else {
          await _fetchCameras();
        }
      }
    }
  }

  /// This updates the resolution of the camera preview.
  Future<void> _onResolutionChange(ResolutionPreset newValue) async {
    setState(() {
      _resolutionPreset = newValue;
    });

    if (_initialised && _cameraId >= 0) {
      /// re-inits camera with new resolution preset
      await _disposeCurrentCamera();
      await _initiliaseCamera();
    }
  }

  /// This updates whether or not audio recording is enabled.
  Future<void> _onAudioChange(bool recordAudio) async {
    setState(() {
      _recordAudio = recordAudio;
    });

    if (_initialised && _cameraId >= 0) {
      /// re-inits camera with new audio setting
      await _disposeCurrentCamera();
      await _initiliaseCamera();
    }
  }

  /// This function handles camera error by disposing the active camera.
  /// It then fetches a new camera.
  void _onCameraError(CameraErrorEvent event) {
    if (mounted) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error: ${event.description}')));

      /// Dispose camera on camera error as it can't be used anymore
      _disposeCurrentCamera();
      _fetchCameras();
    }
  }

  /// This function shows a snackbar when camera is closed.
  void _onCameraClosing(CameraClosingEvent event) {
    if (mounted) {
      _showInSnackBar('Camera is closing');
    }
  }

  /// This shows snackbar with the message passed as parameter to it.
  void _showInSnackBar(String message) {
    _scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 1),
    ));
  }

  /// This is a global key used to maintain state for the Snackbar
  /// in case previous snackbars are still running
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    /// This creates a Dropdown menu list which shows the possible ResolutionPreset values
    final List<DropdownMenuItem<ResolutionPreset>> resolutionItems =
        ResolutionPreset.values
            .map<DropdownMenuItem<ResolutionPreset>>((ResolutionPreset value) {
      return DropdownMenuItem<ResolutionPreset>(
          value: value, child: Text(value.toString()));
    }).toList();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Test Camera Plugin'),
        ),
        body: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 5,
                horizontal: 10,
              ),
              child: Text(_cameraInfo),
            ),
            if (_cameras.isEmpty)
              ElevatedButton(
                onPressed: _fetchCameras,
                child: const Text('Recheck available cameras'),
              ),
            if (_cameras.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DropdownButton<ResolutionPreset>(
                    value: _resolutionPreset,
                    onChanged: (ResolutionPreset? value) {
                      if (value != null) {
                        _onResolutionChange(value);
                      }
                    },
                    items: resolutionItems,
                  ),
                  const SizedBox(
                    width: 20,
                  ),
                  const Text('Audio: '),
                  Switch(
                      value: _recordAudio,
                      onChanged: (bool state) => _onAudioChange(state)),
                  const SizedBox(
                    width: 20,
                  ),
                  ElevatedButton(
                    onPressed: _initialised
                        ? _disposeCurrentCamera
                        : _initiliaseCamera,
                    child:
                        Text(_initialised ? 'Dipose Camera' : 'Create Camera'),
                  ),
                  const SizedBox(
                    width: 5,
                  ),
                  ElevatedButton(
                    onPressed: _initialised ? _takePicture : null,
                    child: const Text('Take a picture'),
                  ),
                  const SizedBox(
                    width: 5,
                  ),
                  ElevatedButton(
                    onPressed: _initialised ? _togglePreview : null,
                    child: Text(
                        _previewPaused ? 'Resume Preview' : 'Pause Preview'),
                  ),
                  const SizedBox(width: 5),
                  ElevatedButton(
                    onPressed: _initialised ? _toggleRecord : null,
                    child: Text(
                      (_recording || _recordingTimed)
                          ? 'Stop Recording'
                          : 'Record Video',
                    ),
                  ),
                  const SizedBox(
                    width: 5,
                  ),
                  ElevatedButton(
                    onPressed: (_initialised && !_recording && !_recordingTimed)
                        ? () => _recordTimed(5)
                        : null,
                    child: const Text('Record 5 seconds'),
                  ),
                  if (_cameras.length > 1) ...[
                    const SizedBox(
                      width: 5,
                    ),
                    ElevatedButton(
                      onPressed: _switchCamera,
                      child: const Text('Switch Camera'),
                    ),
                  ]
                ],
              ),
            const SizedBox(
              height: 5,
            ),
            if (_initialised && _cameraId > 0 && _previewSize != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Align(
                  alignment: Alignment.center,
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 500),
                    child: AspectRatio(
                      aspectRatio: _previewSize!.width / _previewSize!.height,
                      child: _buildPreview(),
                    ),
                  ),
                ),
              ),
            if (_previewSize != null)
              Center(
                child: Text(
                  'Preview Size: ${_previewSize!.width.toStringAsFixed(0)} x ${_previewSize!.height.toStringAsFixed(0)}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
