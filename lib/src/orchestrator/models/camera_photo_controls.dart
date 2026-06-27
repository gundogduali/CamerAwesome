import 'package:camerawesome/pigeon.dart';

/// Exposure mode mirroring `AVCaptureDevice.ExposureMode`.
///
/// Currently implemented on iOS only.
enum ExposureMode {
  /// The exposure is locked at its current value.
  locked,

  /// The device performs a single autoexposure operation then reverts to
  /// [locked].
  auto,

  /// The device continuously adjusts the exposure.
  continuousAuto,

  /// You set the ISO and shutter speed manually through
  /// [CamerawesomePlugin.setManualExposure].
  custom;

  PigeonExposureMode get pigeon => PigeonExposureMode.values[index];
}

/// Focus mode mirroring `AVCaptureDevice.FocusMode`.
///
/// Currently implemented on iOS only.
enum FocusMode {
  /// The focus is locked. Drive the lens manually with
  /// [CamerawesomePlugin.setLensPosition].
  locked,

  /// The device performs a single autofocus operation then reverts to [locked].
  auto,

  /// The device continuously adjusts the focus.
  continuousAuto;

  PigeonFocusMode get pigeon => PigeonFocusMode.values[index];
}

/// White balance mode mirroring `AVCaptureDevice.WhiteBalanceMode`.
///
/// Currently implemented on iOS only.
enum WhiteBalanceMode {
  /// The white balance is locked. Set it manually with
  /// [CamerawesomePlugin.setWhiteBalanceGains] or
  /// [CamerawesomePlugin.setWhiteBalanceTemperatureTint].
  locked,

  /// The device performs a single white balance operation then reverts to
  /// [locked].
  auto,

  /// The device continuously adjusts the white balance.
  continuousAuto;

  PigeonWhiteBalanceMode get pigeon => PigeonWhiteBalanceMode.values[index];
}

/// Torch (continuous light) mode mirroring `AVCaptureDevice.TorchMode`. This is
/// independent from the photo flash configured through
/// [CamerawesomePlugin.setFlashMode].
///
/// Currently implemented on iOS only.
enum TorchMode {
  off,
  on,
  auto;

  PigeonTorchMode get pigeon => PigeonTorchMode.values[index];
}

/// Auto focus range restriction mirroring
/// `AVCaptureDevice.AutoFocusRangeRestriction`.
///
/// Currently implemented on iOS only.
enum FocusRangeRestriction {
  none,
  near,
  far;

  PigeonFocusRangeRestriction get pigeon =>
      PigeonFocusRangeRestriction.values[index];
}

/// Color space mirroring `AVCaptureColorSpace`.
///
/// Currently implemented on iOS only.
enum AwesomeColorSpace {
  sRGB,
  p3D65,
  hlgBT2020,
  appleLog;

  PigeonColorSpace get pigeon => PigeonColorSpace.values[index];
}

/// Snapshot of the device exposure capabilities and current values.
/// Durations are expressed in seconds.
class ExposureState {
  final double minIso;
  final double maxIso;
  final double currentIso;
  final double minExposureDurationSeconds;
  final double maxExposureDurationSeconds;
  final double currentExposureDurationSeconds;
  final double minExposureTargetBias;
  final double maxExposureTargetBias;
  final double currentExposureTargetBias;

  ExposureState({
    required this.minIso,
    required this.maxIso,
    required this.currentIso,
    required this.minExposureDurationSeconds,
    required this.maxExposureDurationSeconds,
    required this.currentExposureDurationSeconds,
    required this.minExposureTargetBias,
    required this.maxExposureTargetBias,
    required this.currentExposureTargetBias,
  });

  factory ExposureState.fromPigeon(PigeonExposureState state) => ExposureState(
        minIso: state.minIso,
        maxIso: state.maxIso,
        currentIso: state.currentIso,
        minExposureDurationSeconds: state.minExposureDurationSeconds,
        maxExposureDurationSeconds: state.maxExposureDurationSeconds,
        currentExposureDurationSeconds: state.currentExposureDurationSeconds,
        minExposureTargetBias: state.minExposureTargetBias,
        maxExposureTargetBias: state.maxExposureTargetBias,
        currentExposureTargetBias: state.currentExposureTargetBias,
      );
}

/// RGB white balance gains mirroring `AVCaptureDevice.WhiteBalanceGains`.
class WhiteBalanceGains {
  final double red;
  final double green;
  final double blue;

  WhiteBalanceGains({
    required this.red,
    required this.green,
    required this.blue,
  });

  factory WhiteBalanceGains.fromPigeon(PigeonWhiteBalanceGains gains) =>
      WhiteBalanceGains(
        red: gains.red,
        green: gains.green,
        blue: gains.blue,
      );

  PigeonWhiteBalanceGains get pigeon =>
      PigeonWhiteBalanceGains(red: red, green: green, blue: blue);
}

/// A snapshot of all current device photo control values **and** their
/// supported ranges, read directly from the active device. Use it to
/// initialize a UI with the values that are actually applied.
///
/// Currently available on iOS only.
class CameraSettings {
  // Exposure
  final ExposureMode exposureMode;
  final double exposureTargetBias;
  final double minExposureTargetBias;
  final double maxExposureTargetBias;
  final double iso;
  final double minIso;
  final double maxIso;
  final double exposureDurationSeconds;
  final double minExposureDurationSeconds;
  final double maxExposureDurationSeconds;

  // Focus
  final FocusMode focusMode;
  final double lensPosition;

  // White balance
  final WhiteBalanceMode whiteBalanceMode;
  final double temperature;
  final double tint;

  // Lighting
  final TorchMode torchMode;
  final bool torchActive;
  final bool lowLightBoostEnabled;

  // Color
  final AwesomeColorSpace colorSpace;
  final bool autoRedEyeReductionEnabled;

  // Zoom
  final double zoomRatio;
  final double minZoomRatio;
  final double maxZoomRatio;

  CameraSettings({
    required this.exposureMode,
    required this.exposureTargetBias,
    required this.minExposureTargetBias,
    required this.maxExposureTargetBias,
    required this.iso,
    required this.minIso,
    required this.maxIso,
    required this.exposureDurationSeconds,
    required this.minExposureDurationSeconds,
    required this.maxExposureDurationSeconds,
    required this.focusMode,
    required this.lensPosition,
    required this.whiteBalanceMode,
    required this.temperature,
    required this.tint,
    required this.torchMode,
    required this.torchActive,
    required this.lowLightBoostEnabled,
    required this.colorSpace,
    required this.autoRedEyeReductionEnabled,
    required this.zoomRatio,
    required this.minZoomRatio,
    required this.maxZoomRatio,
  });

  factory CameraSettings.fromPigeon(PigeonCameraSettings s) => CameraSettings(
        exposureMode: ExposureMode.values[s.exposureMode.index],
        exposureTargetBias: s.exposureTargetBias,
        minExposureTargetBias: s.minExposureTargetBias,
        maxExposureTargetBias: s.maxExposureTargetBias,
        iso: s.iso,
        minIso: s.minIso,
        maxIso: s.maxIso,
        exposureDurationSeconds: s.exposureDurationSeconds,
        minExposureDurationSeconds: s.minExposureDurationSeconds,
        maxExposureDurationSeconds: s.maxExposureDurationSeconds,
        focusMode: FocusMode.values[s.focusMode.index],
        lensPosition: s.lensPosition,
        whiteBalanceMode: WhiteBalanceMode.values[s.whiteBalanceMode.index],
        temperature: s.temperature,
        tint: s.tint,
        torchMode: TorchMode.values[s.torchMode.index],
        torchActive: s.torchActive,
        lowLightBoostEnabled: s.lowLightBoostEnabled,
        colorSpace: AwesomeColorSpace.values[s.colorSpace.index],
        autoRedEyeReductionEnabled: s.autoRedEyeReductionEnabled,
        zoomRatio: s.zoomRatio,
        minZoomRatio: s.minZoomRatio,
        maxZoomRatio: s.maxZoomRatio,
      );
}
