import 'package:camera_app/utils/file_utils.dart';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';

/// This example demonstrates the AVFoundation photo controls added to
/// CamerAwesome: exposure, focus, white balance, lighting (torch), color and
/// ratio based zoom.
///
/// ⚠️ These controls are currently implemented on **iOS only**. On Android the
/// underlying methods throw an "unimplemented" error, so the panel disables
/// itself and shows a message.
void main() {
  runApp(const CameraAwesomeApp());
}

class CameraAwesomeApp extends StatelessWidget {
  const CameraAwesomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Photo Controls',
      home: CameraPage(),
    );
  }
}

class CameraPage extends StatelessWidget {
  const CameraPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CameraAwesomeBuilder.awesome(
        saveConfig: SaveConfig.photo(),
        sensorConfig: SensorConfig.single(
          flashMode: FlashMode.none,
          aspectRatio: CameraAspectRatios.ratio_16_9,
        ),
        previewFit: CameraPreviewFit.contain,
        onMediaTap: (mediaCapture) {
          mediaCapture.captureRequest.when(
            single: (single) => single.file?.open(),
          );
        },
        // Keep the default top actions (flash, etc.) and bottom actions
        // (capture button) but replace the middle content with a button that
        // opens the manual controls panel.
        middleContentBuilder: (state) {
          return Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xD9FFFFFF),
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.tune),
                label: const Text('Photo controls'),
                onPressed: () => _openControls(context),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openControls(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.85,
        child: PhotoControlsPanel(),
      ),
    );
  }
}

class PhotoControlsPanel extends StatefulWidget {
  const PhotoControlsPanel({super.key});

  @override
  State<PhotoControlsPanel> createState() => _PhotoControlsPanelState();
}

class _PhotoControlsPanelState extends State<PhotoControlsPanel> {
  // Current device settings + ranges (read from the plugin on open).
  CameraSettings? _settings;

  // Exposure
  ExposureMode _exposureMode = ExposureMode.continuousAuto;
  double _exposureBias = 0;
  double _iso = 100;
  double _shutterSeconds = 1 / 60;

  // Focus
  FocusMode _focusMode = FocusMode.continuousAuto;
  double _lensPosition = 0.5;
  FocusRangeRestriction _focusRange = FocusRangeRestriction.none;
  bool _smoothFocus = false;

  // White balance
  WhiteBalanceMode _wbMode = WhiteBalanceMode.continuousAuto;
  double _temperature = 5000;
  double _tint = 0;

  // Lighting
  TorchMode _torchMode = TorchMode.off;
  double _torchLevel = 1;
  bool _lowLightBoost = false;

  // Color
  List<AwesomeColorSpace> _colorSpaces = [];
  AwesomeColorSpace? _colorSpace;
  bool _redEye = false;

  // Zoom
  double _minZoom = 1;
  double _maxZoom = 1;
  double _zoomRatio = 1;

  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRanges();
  }

  /// Reads the values **currently applied** on the device (modes,
  /// temperature/tint, zoom, etc.) plus the supported ranges, and initializes
  /// every control from them — so reopening the panel reflects the real state
  /// instead of resetting to defaults.
  ///
  /// On Android these calls throw, so we catch and disable the panel.
  Future<void> _loadRanges() async {
    try {
      final settings = await CamerawesomePlugin.getCameraSettings();
      final colorSpaces = await CamerawesomePlugin.getAvailableColorSpaces();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        // Exposure
        _exposureMode = settings.exposureMode;
        _exposureBias = settings.exposureTargetBias;
        _iso = settings.iso;
        _shutterSeconds = settings.exposureDurationSeconds;
        // Focus
        _focusMode = settings.focusMode;
        _lensPosition = settings.lensPosition;
        // White balance
        _wbMode = settings.whiteBalanceMode;
        _temperature = settings.temperature;
        _tint = settings.tint;
        // Lighting
        _torchMode = settings.torchMode;
        _lowLightBoost = settings.lowLightBoostEnabled;
        // Color
        _colorSpaces = colorSpaces;
        _colorSpace = settings.colorSpace;
        _redEye = settings.autoRedEyeReductionEnabled;
        // Zoom
        _minZoom = settings.minZoomRatio;
        _maxZoom = settings.maxZoomRatio < settings.minZoomRatio
            ? settings.minZoomRatio
            : settings.maxZoomRatio;
        _zoomRatio = settings.zoomRatio;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(color: Colors.white),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildError()
                : ListView(
                    children: [
                      _title('Exposure'),
                      _buildExposure(),
                      const Divider(color: Colors.white24),
                      _title('Focus'),
                      _buildFocus(),
                      const Divider(color: Colors.white24),
                      _title('White balance'),
                      _buildWhiteBalance(),
                      const Divider(color: Colors.white24),
                      _title('Lighting'),
                      _buildLighting(),
                      const Divider(color: Colors.white24),
                      _title('Color'),
                      _buildColor(),
                      const Divider(color: Colors.white24),
                      _title('Zoom'),
                      _buildZoom(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, color: Colors.orangeAccent, size: 40),
          const SizedBox(height: 12),
          const Text(
            'These photo controls are implemented on iOS only for now.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // --- Exposure ---

  Widget _buildExposure() {
    final state = _settings!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _modeSelector<ExposureMode>(
          values: ExposureMode.values,
          selected: _exposureMode,
          label: (m) => m.name,
          onChanged: (m) {
            setState(() => _exposureMode = m);
            _run(() => CamerawesomePlugin.setExposureMode(m));
          },
        ),
        _slider(
          label: 'EV bias',
          value: _exposureBias,
          min: state.minExposureTargetBias,
          max: state.maxExposureTargetBias,
          onChanged: (v) => setState(() => _exposureBias = v),
          onChangeEnd: (v) =>
              _run(() => CamerawesomePlugin.setExposureTargetBias(v)),
        ),
        if (_exposureMode == ExposureMode.custom) ...[
          _slider(
            label: 'ISO',
            value: _iso.clamp(state.minIso, state.maxIso),
            min: state.minIso,
            max: state.maxIso,
            onChanged: (v) => setState(() => _iso = v),
            onChangeEnd: (_) => _applyManualExposure(),
            displayValue: _iso.toStringAsFixed(0),
          ),
          _slider(
            label: 'Shutter (s)',
            value: _shutterSeconds.clamp(
              state.minExposureDurationSeconds,
              state.maxExposureDurationSeconds,
            ),
            min: state.minExposureDurationSeconds,
            max: state.maxExposureDurationSeconds,
            onChanged: (v) => setState(() => _shutterSeconds = v),
            onChangeEnd: (_) => _applyManualExposure(),
            displayValue: '1/${(1 / _shutterSeconds).toStringAsFixed(0)}',
          ),
        ],
      ],
    );
  }

  void _applyManualExposure() {
    _run(() => CamerawesomePlugin.setManualExposure(
          iso: _iso,
          exposureDurationSeconds: _shutterSeconds,
        ));
  }

  // --- Focus ---

  Widget _buildFocus() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _modeSelector<FocusMode>(
          values: FocusMode.values,
          selected: _focusMode,
          label: (m) => m.name,
          onChanged: (m) {
            setState(() => _focusMode = m);
            _run(() => CamerawesomePlugin.setFocusMode(m));
          },
        ),
        if (_focusMode == FocusMode.locked)
          _slider(
            label: 'Lens position',
            value: _lensPosition,
            min: 0,
            max: 1,
            onChanged: (v) => setState(() => _lensPosition = v),
            onChangeEnd: (v) =>
                _run(() => CamerawesomePlugin.setLensPosition(v)),
          ),
        _modeSelector<FocusRangeRestriction>(
          values: FocusRangeRestriction.values,
          selected: _focusRange,
          label: (m) => m.name,
          onChanged: (m) {
            setState(() => _focusRange = m);
            _run(() => CamerawesomePlugin.setAutoFocusRangeRestriction(m));
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Smooth auto focus'),
          value: _smoothFocus,
          onChanged: (v) {
            setState(() => _smoothFocus = v);
            _run(() => CamerawesomePlugin.setSmoothAutoFocusEnabled(v));
          },
        ),
      ],
    );
  }

  // --- White balance ---

  Widget _buildWhiteBalance() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _modeSelector<WhiteBalanceMode>(
          values: WhiteBalanceMode.values,
          selected: _wbMode,
          label: (m) => m.name,
          onChanged: (m) {
            setState(() => _wbMode = m);
            _run(() => CamerawesomePlugin.setWhiteBalanceMode(m));
          },
        ),
        _slider(
          label: 'Temperature (K)',
          value: _temperature,
          min: 3000,
          max: 8000,
          onChanged: (v) => setState(() => _temperature = v),
          onChangeEnd: (_) => _applyTemperatureTint(),
          displayValue: _temperature.toStringAsFixed(0),
        ),
        _slider(
          label: 'Tint',
          value: _tint,
          min: -150,
          max: 150,
          onChanged: (v) => setState(() => _tint = v),
          onChangeEnd: (_) => _applyTemperatureTint(),
          displayValue: _tint.toStringAsFixed(0),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () =>
                _run(() => CamerawesomePlugin.setGrayWorldWhiteBalance()),
            child: const Text('Apply gray world white balance'),
          ),
        ),
      ],
    );
  }

  void _applyTemperatureTint() {
    setState(() => _wbMode = WhiteBalanceMode.locked);
    _run(() => CamerawesomePlugin.setWhiteBalanceTemperatureTint(
          temperature: _temperature,
          tint: _tint,
        ));
  }

  // --- Lighting ---

  Widget _buildLighting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _modeSelector<TorchMode>(
          values: TorchMode.values,
          selected: _torchMode,
          label: (m) => m.name,
          onChanged: (m) {
            setState(() => _torchMode = m);
            _run(() => CamerawesomePlugin.setTorchMode(m));
          },
        ),
        _slider(
          label: 'Torch level',
          value: _torchLevel,
          min: 0,
          max: 1,
          onChanged: (v) => setState(() => _torchLevel = v),
          onChangeEnd: (v) => _run(() => CamerawesomePlugin.setTorchLevel(v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Low light boost'),
          value: _lowLightBoost,
          onChanged: (v) {
            setState(() => _lowLightBoost = v);
            _run(() => CamerawesomePlugin.setLowLightBoostEnabled(v));
          },
        ),
      ],
    );
  }

  // --- Color ---

  Widget _buildColor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_colorSpaces.isEmpty)
          const Text('No color spaces reported',
              style: TextStyle(color: Colors.white54))
        else
          _modeSelector<AwesomeColorSpace>(
            values: _colorSpaces,
            selected: _colorSpace ?? _colorSpaces.first,
            label: (m) => m.name,
            onChanged: (m) {
              setState(() => _colorSpace = m);
              _run(() => CamerawesomePlugin.setColorSpace(m));
            },
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Auto red eye reduction'),
          value: _redEye,
          onChanged: (v) {
            setState(() => _redEye = v);
            _run(() => CamerawesomePlugin.setAutoRedEyeReductionEnabled(v));
          },
        ),
      ],
    );
  }

  // --- Zoom ---

  Widget _buildZoom() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _slider(
          label: 'Zoom ratio',
          value: _zoomRatio.clamp(_minZoom, _maxZoom),
          min: _minZoom,
          max: _maxZoom,
          onChanged: (v) => setState(() => _zoomRatio = v),
          onChangeEnd: (v) => _run(() => CamerawesomePlugin.setZoomRatio(v)),
          displayValue: '${_zoomRatio.toStringAsFixed(1)}x',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () {
              setState(() => _zoomRatio = _maxZoom);
              _run(() => CamerawesomePlugin.rampToZoomRatio(_maxZoom));
            },
            child: const Text('Ramp to max zoom'),
          ),
        ),
      ],
    );
  }

  // --- Shared widgets ---

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );

  Widget _modeSelector<T>({
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onChanged,
  }) {
    return Wrap(
      spacing: 8,
      children: values.map((value) {
        return ChoiceChip(
          label: Text(label(value)),
          selected: value == selected,
          onSelected: (_) => onChanged(value),
        );
      }).toList(),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
    String? displayValue,
  }) {
    final safeMax = max > min ? max : min + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '$label: ${displayValue ?? value.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        Slider(
          value: value.clamp(min, safeMax),
          min: min,
          max: safeMax,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}
