import 'package:pigeon/pigeon.dart';

class PreviewSize {
  final double width;
  final double height;

  const PreviewSize(this.width, this.height);
}

class PreviewData {
  double? textureId;
  PreviewSize? size;
}

class ExifPreferences {
  bool saveGPSLocation;

  ExifPreferences({required this.saveGPSLocation});
}

class PigeonSensor {
  final PigeonSensorPosition position;
  final PigeonSensorType type;
  final String? deviceId;

  PigeonSensor({
    this.position = PigeonSensorPosition.unknown,
    this.type = PigeonSensorType.unknown,
    this.deviceId,
  });
}

enum PigeonSensorPosition {
  back,
  front,
  unknown,
}

/// Video recording quality, from [sd] to [uhd], with [highest] and [lowest] to
/// let the device choose the best/worst quality available.
/// [highest] is the default quality.
///
/// Qualities are defined like this:
/// [sd] < [hd] < [fhd] < [uhd]
enum VideoRecordingQuality {
  lowest,
  sd,
  hd,
  fhd,
  uhd,
  highest,
}

/// If the specified [VideoRecordingQuality] is not available on the device,
/// the [VideoRecordingQuality] will fallback to [higher] or [lower] quality.
/// [higher] is the default fallback strategy.
enum QualityFallbackStrategy {
  higher,
  lower,
}

/// Video recording options. Some of them are specific to each platform.
class VideoOptions {
  /// Enable audio while video recording
  final bool enableAudio;

  /// The quality of the video recording, defaults to [VideoRecordingQuality.highest].
  final VideoRecordingQuality? quality;

  // TODO if there are properties common to all platform, move them here (iOS, Android and Web)
  final AndroidVideoOptions? android;
  final CupertinoVideoOptions? ios;

  VideoOptions({
    required this.android,
    required this.ios,
    required this.enableAudio,
    required this.quality,
  });
}

class AndroidVideoOptions {
  /// The bitrate of the video recording. Only set it if a custom bitrate is
  /// desired.
  final int? bitrate;

  final QualityFallbackStrategy? fallbackStrategy;

  AndroidVideoOptions({
    required this.bitrate,
    required this.fallbackStrategy,
  });
}

enum CupertinoFileType {
  quickTimeMovie,
  mpeg4,
  appleM4V,
  type3GPP,
  type3GPP2,
}

enum CupertinoCodecType {
  h264,
  hevc,
  hevcWithAlpha,
  jpeg,
  appleProRes4444,
  appleProRes422,
  appleProRes422HQ,
  appleProRes422LT,
  appleProRes422Proxy,
}

class CupertinoVideoOptions {
  /// Specify video file type, defaults to [AVFileTypeQuickTimeMovie].
  final CupertinoFileType? fileType;

  /// Specify video codec, defaults to [AVVideoCodecTypeH264].
  final CupertinoCodecType? codec;

  /// Specify video fps, defaults to [30].
  final int? fps;

  CupertinoVideoOptions({
    this.fileType,
    this.codec,
    this.fps,
  });
}

enum PigeonSensorType {
  /// A built-in wide-angle camera.
  ///
  /// The wide angle sensor is the default sensor for iOS
  wideAngle,

  /// A built-in camera with a shorter focal length than that of the wide-angle camera.
  ultraWideAngle,

  /// A built-in camera device with a longer focal length than the wide-angle camera.
  telephoto,

  /// A device that consists of two cameras, one Infrared and one YUV.
  ///
  /// iOS only
  trueDepth,
  unknown;

  // SensorType get defaultSensorType => SensorType.wideAngle;
  // SensorType defaultSensorType() => SensorType.wideAngle;
}

class PigeonSensorTypeDevice {
  final PigeonSensorType sensorType;

  /// A localized device name for display in the user interface.
  final String name;

  /// The current exposure ISO value.
  final double iso;

  /// A Boolean value that indicates whether the flash is currently available for use.
  final bool flashAvailable;

  /// An identifier that uniquely identifies the device.
  final String uid;

  PigeonSensorTypeDevice({
    required this.sensorType,
    required this.name,
    required this.iso,
    required this.flashAvailable,
    required this.uid,
  });
}

// TODO: instead of storing SensorTypeDevice values,
// this would be useful when CameraX will support multiple sensors.
// store them in a list of SensorTypeDevice.
// ex:
// List<SensorTypeDevice> wideAngle;
// List<SensorTypeDevice> ultraWideAngle;

class PigeonSensorDeviceData {
  /// A built-in wide-angle camera.
  ///
  /// The wide angle sensor is the default sensor for iOS
  PigeonSensorTypeDevice? wideAngle;

  /// A built-in camera with a shorter focal length than that of the wide-angle camera.
  PigeonSensorTypeDevice? ultraWideAngle;

  /// A built-in camera device with a longer focal length than the wide-angle camera.
  PigeonSensorTypeDevice? telephoto;

  /// A device that consists of two cameras, one Infrared and one YUV.
  ///
  /// iOS only
  PigeonSensorTypeDevice? trueDepth;

  PigeonSensorDeviceData({
    this.wideAngle,
    this.ultraWideAngle,
    this.telephoto,
    this.trueDepth,
  });

// int get availableBackSensors => [
//       wideAngle,
//       ultraWideAngle,
//       telephoto,
//     ].where((element) => element != null).length;

// int get availableFrontSensors => [
//       trueDepth,
//     ].where((element) => element != null).length;
}

enum CamerAwesomePermission {
  storage,
  camera,
  location,
  // ignore: constant_identifier_names
  record_audio,
}

class AndroidFocusSettings {
  /// The auto focus will be canceled after the given [autoCancelDurationInMillis].
  /// If [autoCancelDurationInMillis] is equals to 0 (or less), the auto focus
  /// will **not** be canceled. A manual `focusOnPoint` call will be needed to
  /// focus on an other point.
  /// Minimal duration of [autoCancelDurationInMillis] is 1000 ms. If set
  /// between 0 (exclusive) and 1000 (exclusive), it will be raised to 1000.
  int autoCancelDurationInMillis;

  AndroidFocusSettings({required this.autoCancelDurationInMillis});
}

class PlaneWrapper {
  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;
  final int? width;
  final int? height;

  PlaneWrapper({
    required this.bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
    this.width,
    this.height,
  });
}

enum AnalysisImageFormat { yuv_420, bgra8888, jpeg, nv21, unknown }

enum AnalysisRotation {
  rotation0deg,
  rotation90deg,
  rotation180deg,
  rotation270deg
}

class CropRectWrapper {
  final int left;
  final int top;
  final int width;
  final int height;

  CropRectWrapper({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

class AnalysisImageWrapper {
  final AnalysisImageFormat format;
  final Uint8List? bytes;
  final int width;
  final int height;
  final List<PlaneWrapper?>? planes;
  final CropRectWrapper? cropRect;
  final AnalysisRotation? rotation;

  AnalysisImageWrapper({
    required this.format,
    required this.bytes,
    required this.width,
    required this.height,
    required this.planes,
    required this.cropRect,
    required this.rotation,
  });
}

@HostApi()
abstract class AnalysisImageUtils {
  @async
  AnalysisImageWrapper nv21toJpeg(
    AnalysisImageWrapper nv21Image,
    int jpegQuality,
  );

  @async
  AnalysisImageWrapper yuv420toJpeg(
    AnalysisImageWrapper yuvImage,
    int jpegQuality,
  );

  @async
  AnalysisImageWrapper yuv420toNv21(AnalysisImageWrapper yuvImage);

  @async
  AnalysisImageWrapper bgra8888toJpeg(
    AnalysisImageWrapper bgra8888image,
    int jpegQuality,
  );
}

/// Exposure mode mirroring `AVCaptureDevice.ExposureMode`.
/// [custom] lets you set ISO and shutter speed manually through
/// [CameraInterface.setManualExposure].
///
/// iOS only for now.
enum PigeonExposureMode {
  locked,
  auto,
  continuousAuto,
  custom,
}

/// Focus mode mirroring `AVCaptureDevice.FocusMode`.
/// When [locked], use [CameraInterface.setLensPosition] to drive the lens
/// manually.
///
/// iOS only for now.
enum PigeonFocusMode {
  locked,
  auto,
  continuousAuto,
}

/// White balance mode mirroring `AVCaptureDevice.WhiteBalanceMode`.
/// When [locked], use [CameraInterface.setWhiteBalanceGains] or
/// [CameraInterface.setWhiteBalanceTemperatureTint] to set it manually.
///
/// iOS only for now.
enum PigeonWhiteBalanceMode {
  locked,
  auto,
  continuousAuto,
}

/// Torch (continuous light) mode mirroring `AVCaptureDevice.TorchMode`.
/// This is independent from the photo flash configured with
/// [CameraInterface.setFlashMode].
///
/// iOS only for now.
enum PigeonTorchMode {
  off,
  on,
  auto,
}

/// Auto focus range restriction mirroring
/// `AVCaptureDevice.AutoFocusRangeRestriction`.
///
/// iOS only for now.
enum PigeonFocusRangeRestriction {
  none,
  near,
  far,
}

/// Color space mirroring `AVCaptureColorSpace`.
///
/// iOS only for now.
enum PigeonColorSpace {
  sRGB,
  p3D65,
  hlgBT2020,
  appleLog,
}

/// Snapshot of the device exposure capabilities and current values.
/// Durations are expressed in seconds.
///
/// iOS only for now.
class PigeonExposureState {
  final double minIso;
  final double maxIso;
  final double currentIso;
  final double minExposureDurationSeconds;
  final double maxExposureDurationSeconds;
  final double currentExposureDurationSeconds;
  final double minExposureTargetBias;
  final double maxExposureTargetBias;
  final double currentExposureTargetBias;

  PigeonExposureState({
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
}

/// RGB white balance gains mirroring
/// `AVCaptureDevice.WhiteBalanceGains`.
///
/// iOS only for now.
class PigeonWhiteBalanceGains {
  final double red;
  final double green;
  final double blue;

  PigeonWhiteBalanceGains({
    required this.red,
    required this.green,
    required this.blue,
  });
}

/// A snapshot of the current device photo control values **and** their
/// supported ranges, read directly from `AVCaptureDevice`. Useful to
/// initialize a UI with the values that are actually applied.
///
/// iOS only for now.
class PigeonCameraSettings {
  // Exposure
  final PigeonExposureMode exposureMode;
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
  final PigeonFocusMode focusMode;
  final double lensPosition;

  // White balance
  final PigeonWhiteBalanceMode whiteBalanceMode;
  final double temperature;
  final double tint;

  // Lighting
  final PigeonTorchMode torchMode;
  final bool torchActive;
  final bool lowLightBoostEnabled;

  // Color
  final PigeonColorSpace colorSpace;
  final bool autoRedEyeReductionEnabled;

  // Zoom
  final double zoomRatio;
  final double minZoomRatio;
  final double maxZoomRatio;

  PigeonCameraSettings({
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
}

@HostApi()
abstract class CameraInterface {
  @async
  bool setupCamera(
    List<PigeonSensor> sensors,
    String aspectRatio,
    double zoom,
    bool mirrorFrontCamera,
    bool enablePhysicalButton,
    String flashMode,
    String captureMode,
    bool enableImageStream,
    ExifPreferences exifPreferences,
    VideoOptions? videoOptions,
  );

  List<String> checkPermissions(List<String> permissions);

  /// Returns given [CamerAwesomePermission] list (as String). Location permission might be
  /// refused but the app should still be able to run.
  @async
  List<String> requestPermissions(bool saveGpsLocation);

  int getPreviewTextureId(int cameraPosition);

  // TODO async with void return type seems to not work (channel-error)
  @async
  bool takePhoto(List<PigeonSensor> sensors, List<String?> paths);

  @async
  void recordVideo(List<PigeonSensor> sensors, List<String?> paths);

  void pauseVideoRecording();

  void resumeVideoRecording();

  void receivedImageFromStream();

  @async
  bool stopRecordingVideo();

  List<PigeonSensorTypeDevice> getFrontSensors();

  List<PigeonSensorTypeDevice> getBackSensors();

  bool start();

  bool stop();

  void setFlashMode(String mode);

  void handleAutoFocus();

  /// Starts auto focus on a point at ([x], [y]).
  ///
  /// On Android, you can control after how much time you want to switch back
  /// to passive focus mode with [androidFocusSettings].
  void focusOnPoint(
    PreviewSize previewSize,
    double x,
    double y,
    AndroidFocusSettings? androidFocusSettings,
  );

  void setZoom(double zoom);

  void setMirrorFrontCamera(bool mirror);

  // TODO: specify the position of the sensor
  void setSensor(List<PigeonSensor> sensors);

  void setCorrection(double brightness);

  double getMinZoom();

  double getMaxZoom();

  void setCaptureMode(String mode);

  @async
  bool setRecordingAudioMode(bool enableAudio);

  List<PreviewSize> availableSizes();

  void refresh();

  PreviewSize? getEffectivPreviewSize(int index);

  void setPhotoSize(PreviewSize size);

  void setPreviewSize(PreviewSize size);

  void setAspectRatio(String aspectRatio);

  void setupImageAnalysisStream(
    String format,
    int width,
    double? maxFramesPerSecond,
    bool autoStart,
  );

  @async
  bool setExifPreferences(ExifPreferences exifPreferences);

  void startAnalysis();

  void stopAnalysis();

  void setFilter(List<double> matrix);

  @async
  bool isVideoRecordingAndImageAnalysisSupported(PigeonSensorPosition sensor);

  bool isMultiCamSupported();

  // ---------------------------------------------------------------------------
  // AVFoundation photo controls (iOS only for now, Android throws unimplemented)
  // ---------------------------------------------------------------------------

  // --- Exposure ---

  /// Set the [AVCaptureExposureMode]. See [PigeonExposureMode].
  void setExposureMode(PigeonExposureMode mode);

  /// Set the exposure point of interest at ([x], [y]) expressed in the
  /// [previewSize] coordinate space.
  void setExposurePoint(double x, double y, PreviewSize previewSize);

  /// Set the absolute exposure target bias (EV), clamped to the device
  /// supported range. Unlike [setCorrection] this takes a raw EV value.
  void setExposureTargetBias(double bias);

  /// Switch to custom exposure with the given [iso] and shutter speed
  /// [exposureDurationSeconds] (in seconds), both clamped to the supported
  /// range of the active format.
  void setManualExposure(double iso, double exposureDurationSeconds);

  /// Returns the current exposure capabilities and values of the device.
  PigeonExposureState getExposureState();

  /// Returns a snapshot of all current photo control values and their
  /// supported ranges, read directly from the active device. Useful to
  /// initialize a UI with the values actually applied.
  PigeonCameraSettings getCameraSettings();

  // --- Focus ---

  /// Set the [AVCaptureFocusMode]. See [PigeonFocusMode].
  void setFocusMode(PigeonFocusMode mode);

  /// Lock the focus at the given [lensPosition] (0.0 nearest, 1.0 farthest).
  void setLensPosition(double lensPosition);

  /// Returns the current lens position (0.0 to 1.0).
  double getLensPosition();

  /// Set the [AVCaptureDevice.AutoFocusRangeRestriction].
  void setAutoFocusRangeRestriction(PigeonFocusRangeRestriction restriction);

  /// Enable or disable smooth autofocus.
  void setSmoothAutoFocusEnabled(bool enabled);

  // --- White balance ---

  /// Set the [AVCaptureWhiteBalanceMode]. See [PigeonWhiteBalanceMode].
  void setWhiteBalanceMode(PigeonWhiteBalanceMode mode);

  /// Lock the white balance using the given device RGB [gains].
  void setWhiteBalanceGains(PigeonWhiteBalanceGains gains);

  /// Lock the white balance using a [temperature] (Kelvin) and [tint].
  void setWhiteBalanceTemperatureTint(double temperature, double tint);

  /// Returns the current device white balance gains.
  PigeonWhiteBalanceGains getWhiteBalanceGains();

  /// Returns the maximum supported white balance gain for the active device.
  double getMaxWhiteBalanceGain();

  /// Lock the white balance using the gray world estimate of the current scene.
  void setGrayWorldWhiteBalance();

  // --- Lighting (torch + low light boost) ---

  /// Set the [AVCaptureTorchMode]. See [PigeonTorchMode]. Independent of the
  /// photo flash configured through [setFlashMode].
  void setTorchMode(PigeonTorchMode mode);

  /// Turn on the torch at the given [level] (0.0 to 1.0).
  void setTorchLevel(double level);

  /// Returns whether the torch is currently active.
  bool isTorchActive();

  /// Enable or disable automatic low light boost when available.
  void setLowLightBoostEnabled(bool enabled);

  /// Returns whether low light boost is supported by the active device.
  bool isLowLightBoostSupported();

  // --- Color ---

  /// Set the active [AVCaptureColorSpace]. See [PigeonColorSpace].
  void setColorSpace(PigeonColorSpace colorSpace);

  /// Returns the color spaces supported by the active format (as names of
  /// [PigeonColorSpace]).
  List<String> getAvailableColorSpaces();

  /// Enable or disable automatic red eye reduction on the photo output.
  void setAutoRedEyeReductionEnabled(bool enabled);

  // --- Zoom (ratio based, complementing the normalized [setZoom]) ---

  /// Set the absolute zoom factor (videoZoomFactor), clamped to the supported
  /// range.
  void setZoomRatio(double ratio);

  /// Returns the minimum available zoom factor.
  double getMinZoomRatio();

  /// Returns the maximum available zoom factor.
  double getMaxZoomRatio();

  /// Smoothly ramp the zoom to [ratio] at the given [rate].
  void rampToZoomRatio(double ratio, double rate);
}
