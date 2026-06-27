#import "CamerawesomePlugin.h"
#import "Pigeon.h"
#import "Permissions.h"
#import "SensorsController.h"
#import "SingleCameraPreview.h"
#import "MultiCameraController.h"
#import "AspectRatioUtils.h"
#import "CaptureModeUtils.h"
#import "FlashModeUtils.h"
#import "AnalysisController.h"

FlutterEventSink orientationEventSink;
FlutterEventSink videoRecordingEventSink;
FlutterEventSink imageStreamEventSink;
FlutterEventSink physicalButtonEventSink;

@interface CamerawesomePlugin () <CameraInterface, AnalysisImageUtils>
@property(readonly, nonatomic) NSObject<FlutterTextureRegistry> *textureRegistry;
@property NSMutableArray<NSNumber *> *texturesIds;
@property SingleCameraPreview *camera;
@property MultiCameraPreview *multiCamera;
- (instancetype)init:(NSObject<FlutterPluginRegistrar>*)registrar;
/// Returns the single camera to apply AVFoundation photo controls on, or sets
/// [error] when the camera is not initialized or running in multi camera mode
/// (these controls are iOS single-camera only for now).
- (nullable SingleCameraPreview *)singleCameraForPhotoControlsWithError:(FlutterError * _Nullable __autoreleasing * _Nonnull)error;
@end

// TODO: create a protocol to uniformize multi camera & single camera
// TODO: for multi camera, specify sensor position
// TODO: save all controllers here

@implementation CamerawesomePlugin {
  dispatch_queue_t _dispatchQueue;
  dispatch_queue_t _dispatchQueueAnalysis;
}

- (instancetype)init:(NSObject<FlutterPluginRegistrar>*)registrar {
  self = [super init];
  
  _textureRegistry = registrar.textures;
  
  if (_dispatchQueue == nil) {
    _dispatchQueue = dispatch_queue_create("camerawesome.dispatchqueue", NULL);
  }
  
  if (_dispatchQueueAnalysis == nil) {
    _dispatchQueueAnalysis = dispatch_queue_create("camerawesome.dispatchqueue.analysis", NULL);
  }
  
  return self;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  CamerawesomePlugin *instance = [[CamerawesomePlugin alloc] init:registrar];
  FlutterEventChannel *orientationChannel = [FlutterEventChannel eventChannelWithName:@"camerawesome/orientation"
                                                                      binaryMessenger:[registrar messenger]];
  FlutterEventChannel *imageStreamChannel = [FlutterEventChannel eventChannelWithName:@"camerawesome/images"
                                                                      binaryMessenger:[registrar messenger]];
  FlutterEventChannel *physicalButtonChannel = [FlutterEventChannel eventChannelWithName:@"camerawesome/physical_button"
                                                                         binaryMessenger:[registrar messenger]];
  [orientationChannel setStreamHandler:instance];
  [imageStreamChannel setStreamHandler:instance];
  [physicalButtonChannel setStreamHandler:instance];
  
  CameraInterfaceSetup(registrar.messenger, instance);
  AnalysisImageUtilsSetup(registrar.messenger, instance);
}

#pragma mark - Camera engine methods

- (void)setupCameraSensors:(nonnull NSArray<PigeonSensor *> *)sensors aspectRatio:(nonnull NSString *)aspectRatio zoom:(nonnull NSNumber *)zoom mirrorFrontCamera:(nonnull NSNumber *)mirrorFrontCamera enablePhysicalButton:(nonnull NSNumber *)enablePhysicalButton flashMode:(nonnull NSString *)flashMode captureMode:(nonnull NSString *)captureMode enableImageStream:(nonnull NSNumber *)enableImageStream exifPreferences:(nonnull ExifPreferences *)exifPreferences videoOptions:(nullable VideoOptions *)videoOptions completion:(nonnull void (^)(NSNumber * _Nullable, FlutterError * _Nullable))completion {
  
  CaptureModes captureModeType = [CaptureModeUtils captureModeFromCaptureModeType:captureMode];
  if (![CameraPermissionsController checkAndRequestPermission]) {
    completion(nil, [FlutterError errorWithCode:@"MISSING_PERMISSION" message:@"you got to accept all permissions" details:nil]);
    return;
  }
  
  if (sensors == nil || [sensors count] <= 0) {
    completion(nil, [FlutterError errorWithCode:@"SENSOR_ERROR" message:@"empty sensors provided, please provide at least 1 sensor" details:nil]);
    return;
  }
  
  // If camera preview exist, dispose it
  if (self.camera != nil) {
    [self.camera dispose];
    self.camera = nil;
  }
  if (self.multiCamera != nil) {
    [self.multiCamera dispose];
    self.multiCamera = nil;
  }
  
  _texturesIds = [NSMutableArray new];
  
  AspectRatio aspectRatioMode = [AspectRatioUtils convertAspectRatio:aspectRatio];
  
  bool multiSensors = [sensors count] > 1;
  if (multiSensors) {
    if (![MultiCameraController isMultiCamSupported]) {
      completion(nil, [FlutterError errorWithCode:@"MULTI_CAM_NOT_SUPPORTED" message:@"multi camera feature is not supported" details:nil]);
      return;
    }
    
    self.multiCamera = [[MultiCameraPreview alloc] initWithSensors:sensors
                                                 mirrorFrontCamera:[mirrorFrontCamera boolValue]
                                              enablePhysicalButton:[enablePhysicalButton boolValue]
                                                   aspectRatioMode:aspectRatioMode
                                                       captureMode:captureModeType
                                                     dispatchQueue:dispatch_queue_create("camerawesome.multi_preview.dispatchqueue", NULL)];
    
    for (int i = 0; i < [sensors count]; i++) {
      int64_t textureId = [self->_textureRegistry registerTexture:self.multiCamera.textures[i]];
      [_texturesIds addObject:[NSNumber numberWithLongLong:textureId]];
    }
    
    __weak typeof(self) weakSelf = self;
    self.multiCamera.onPreviewFrameAvailable = ^(NSNumber * _Nullable i) {
      if (i == nil) {
        return;
      }
      
      NSNumber *textureNumber = weakSelf.texturesIds[[i intValue]];
      [weakSelf.textureRegistry textureFrameAvailable:[textureNumber longLongValue]];
    };
  } else {
    PigeonSensor *firstSensor = sensors.firstObject;
    self.camera = [[SingleCameraPreview alloc] initWithCameraSensor:firstSensor.position
                                                       videoOptions:videoOptions != nil ? videoOptions.ios : nil
                                                   recordingQuality:videoOptions != nil ? videoOptions.quality : VideoRecordingQualityHighest
                                                       streamImages:[enableImageStream boolValue]
                                                  mirrorFrontCamera:[mirrorFrontCamera boolValue]
                                               enablePhysicalButton:[enablePhysicalButton boolValue]
                                                    aspectRatioMode:aspectRatioMode
                                                        captureMode:captureModeType
                                                         completion:completion
                                                      dispatchQueue:dispatch_queue_create("camerawesome.single_preview.dispatchqueue", NULL)];
    
    int64_t textureId = [self->_textureRegistry registerTexture:self.camera.previewTexture];
    
    __weak typeof(self) weakSelf = self;
    self.camera.onPreviewFrameAvailable = ^{
      [weakSelf.textureRegistry textureFrameAvailable:textureId];
    };
    
    [self->_textureRegistry textureFrameAvailable:textureId];
    
    [self.texturesIds addObject:[NSNumber numberWithLongLong:textureId]];
  }
  
  completion(@(YES), nil);
}

- (nullable NSNumber *)startWithError:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return @(NO);
  }
  
  dispatch_async(_dispatchQueue, ^{
    if (self.multiCamera != nil) {
      [self->_multiCamera start];
    } else {
      [self->_camera start];
    }
  });
  
  return @(YES);
}

- (nullable NSNumber *)stopWithError:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return @(NO);
  }
  
  for (NSNumber *textureId in self->_texturesIds) {
    [self->_textureRegistry unregisterTexture:[textureId longLongValue]];
    dispatch_async(_dispatchQueue, ^{
      if (self.multiCamera != nil) {
        [self->_multiCamera stop];
      } else {
        [self->_camera stop];
      }
    });
  }
  
  return @(YES);
}

- (void)refreshWithError:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return;
  }
  
  if (self.multiCamera != nil) {
    [self.multiCamera refresh];
  } else {
    [self.camera refresh];
  }
}

- (nullable NSNumber *)getPreviewTextureIdCameraPosition:(nonnull NSNumber *)cameraPosition error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  int cameraIndex = [cameraPosition intValue];
  
  if (_texturesIds != nil && [_texturesIds count] >= cameraIndex) {
    return [_texturesIds objectAtIndex:cameraIndex];
  }
  
  return nil;
}

#pragma mark - Event sink methods

- (FlutterError *)onListenWithArguments:(NSString *)arguments eventSink:(FlutterEventSink)eventSink {
  if ([arguments  isEqual: @"orientationChannel"]) {
    orientationEventSink = eventSink;
    
    if (self.camera != nil) {
      [self.camera setOrientationEventSink:orientationEventSink];
    }
    
  } else if ([arguments  isEqual: @"imagesChannel"]) {
    imageStreamEventSink = eventSink;
    
    if (self.camera != nil) {
      [self.camera setImageStreamEvent:imageStreamEventSink];
    }
  } else if ([arguments  isEqual: @"physicalButtonChannel"]) {
    physicalButtonEventSink = eventSink;
    
    if (self.camera != nil) {
      [self.camera setPhysicalButtonEventSink:physicalButtonEventSink];
    }
  }
  
  return nil;
}

- (FlutterError *)onCancelWithArguments:(NSString *)arguments {
  if ([arguments  isEqual: @"orientationChannel"]) {
    orientationEventSink = nil;
    
    if (self.camera != nil && self.camera.motionController != nil) {
      [self.camera setOrientationEventSink:orientationEventSink];
    }
  } else if ([arguments  isEqual: @"imagesChannel"]) {
    imageStreamEventSink = nil;
    
    if (self.camera != nil) {
      [self.camera setImageStreamEvent:imageStreamEventSink];
    }
  } else if ([arguments  isEqual: @"physicalButtonChannel"]) {
    physicalButtonEventSink = nil;
    
    if (self.camera != nil) {
      [self.camera setPhysicalButtonEventSink:physicalButtonEventSink];
    }
  }
  return nil;
}

#pragma mark - Permissions methods

- (void)requestPermissionsSaveGpsLocation:(nonnull NSNumber *)saveGpsLocation completion:(nonnull void (^)(NSArray<NSString *> * _Nullable, FlutterError * _Nullable))completion {
  NSMutableArray *permissions = [NSMutableArray new];
  
  const BOOL cameraGranted = [CameraPermissionsController checkAndRequestPermission];
  if (cameraGranted) {
    [permissions addObject:@"camera"];
  }
  
  bool needToSaveGPSLocation = [saveGpsLocation boolValue];
  if (needToSaveGPSLocation) {
    // TODO: move this to permissions object
    [self.camera.locationController requestWhenInUseAuthorizationOnGranted:^{
      [permissions addObject:@"location"];
      
      completion(permissions, nil);
    } declined:^{
      completion(permissions, nil);
    }];
  }
}

- (nullable NSArray<NSString *> *)checkPermissionsPermissions:(nonnull NSArray<NSString *> *)permissions error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  bool isMicrophonePermissionRequired = [permissions containsObject:@"microphone"];
  bool isCameraPermissionRequired = [permissions containsObject:@"camera"];
  
  bool cameraPermission = isCameraPermissionRequired ? [CameraPermissionsController checkPermission] : NO;
  bool microphonePermission = isMicrophonePermissionRequired ? [MicrophonePermissionsController checkPermission] : NO;
  
  NSMutableArray *grantedPermissions = [NSMutableArray new];
  if (cameraPermission) {
    [grantedPermissions addObject:@"camera"];
  }
  
  if (microphonePermission) {
    [grantedPermissions addObject:@"record_audio"];
  }
  
  return grantedPermissions;
}

- (nullable NSArray<NSString *> *)requestPermissionsWithError:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  return @[];
}

#pragma mark - Focus methods

- (void)focusOnPointPreviewSize:(nonnull PreviewSize *)previewSize x:(nonnull NSNumber *)x y:(nonnull NSNumber *)y androidFocusSettings:(nullable AndroidFocusSettings *)androidFocusSettings error:(FlutterError *_Nullable __autoreleasing *_Nonnull)error {
  if (previewSize.width <= 0 || previewSize.height <= 0) {
    *error = [FlutterError errorWithCode:@"INVALID_PREVIEW" message:@"preview size width and height must be set" details:nil];
    return;
  }
  
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return;
  }
  
  if (self.multiCamera != nil) {
    [self.multiCamera focusOnPoint:CGPointMake([x floatValue], [y floatValue]) preview:CGSizeMake([previewSize.width floatValue], [previewSize.height floatValue]) error:error];
  } else {
    [self.camera focusOnPoint:CGPointMake([x floatValue], [y floatValue]) preview:CGSizeMake([previewSize.width floatValue], [previewSize.height floatValue]) error:error];
  }
}

- (void)handleAutoFocusWithError:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  // TODO: to remove ?
}

#pragma mark - Video recording methods

- (void)pauseVideoRecordingWithError:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return;
  }
  
  if (self.camera == nil) {
    *error = [FlutterError errorWithCode:@"MULTI_CAMERA_UNSUPPORTED" message:@"this feature is currently not supported with multi camera feature" details:nil];
    return;
  }
  
  [self.camera pauseVideoRecording];
}

- (void)recordVideoSensors:(nonnull NSArray<PigeonSensor *> *)sensors paths:(nonnull NSArray<NSString *> *)paths completion:(nonnull void (^)(FlutterError * _Nullable))completion {
  if (self.camera == nil && self.multiCamera == nil) {
    completion([FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil]);
    return;
  }
  
  if (self.camera == nil) {
    completion([FlutterError errorWithCode:@"MULTI_CAMERA_UNSUPPORTED" message:@"this feature is currently not supported with multi camera feature" details:nil]);
    return;
  }
  
  if (sensors == nil || [sensors count] <= 0 || paths == nil || [paths count] <= 0) {
    completion([FlutterError errorWithCode:@"PATH_NOT_SET" message:@"at least one path must be set" details:nil]);
    return;
  }
  
  if ([sensors count] != [paths count]) {
    completion([FlutterError errorWithCode:@"PATH_INVALID" message:@"sensors & paths list seems to be different" details:nil]);
    return;
  }
  
  [self.camera recordVideoAtPath:[paths firstObject] completion:completion];
}

- (void)resumeVideoRecordingWithError:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return;
  }
  
  if (self.camera == nil) {
    *error = [FlutterError errorWithCode:@"MULTI_CAMERA_UNSUPPORTED" message:@"this feature is currently not supported with multi camera feature" details:nil];
    return;
  }
  
  [self.camera resumeVideoRecording];
}

- (void)setRecordingAudioModeEnableAudio:(NSNumber *)enableAudio completion:(void(^)(NSNumber *_Nullable, FlutterError *_Nullable))completion {
  if (self.camera == nil && self.multiCamera == nil) {
    completion(nil, [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil]);
    return;
  }
  
  if (self.camera == nil) {
    completion(nil, [FlutterError errorWithCode:@"MULTI_CAMERA_UNSUPPORTED" message:@"this feature is currently not supported with multi camera feature" details:nil]);
    return;
  }
  
  [self.camera setRecordingAudioMode:[enableAudio boolValue] completion:completion];
}

- (void)stopRecordingVideoWithCompletion:(nonnull void (^)(NSNumber * _Nullable, FlutterError * _Nullable))completion {
  if (self.camera == nil && self.multiCamera == nil) {
    completion(nil, [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil]);
    return;
  }
  
  if (self.camera == nil) {
    completion(nil, [FlutterError errorWithCode:@"MULTI_CAMERA_UNSUPPORTED" message:@"this feature is currently not supported with multi camera feature" details:nil]);
    return;
  }
  
  dispatch_async(_dispatchQueue, ^{
    [self->_camera stopRecordingVideo:completion];
  });
}

#pragma mark - General methods

- (void)takePhotoSensors:(nonnull NSArray<PigeonSensor *> *)sensors paths:(nonnull NSArray<NSString *> *)paths completion:(nonnull void (^)(NSNumber * _Nullable, FlutterError * _Nullable))completion {
  if (self.camera == nil && self.multiCamera == nil) {
    completion(nil, [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil]);
    return;
  }
  
  if (sensors == nil || [sensors count] <= 0 || paths == nil || [paths count] <= 0) {
    completion(0, [FlutterError errorWithCode:@"PATH_NOT_SET" message:@"at least one path must be set" details:nil]);
    return;
  }
  
  if ([sensors count] != [paths count]) {
    completion(0, [FlutterError errorWithCode:@"PATH_INVALID" message:@"sensors & paths list seems to be different" details:nil]);
    return;
  }
  
  dispatch_async(_dispatchQueue, ^{
    if (self.multiCamera != nil) {
      [self->_multiCamera takePhotoSensors:sensors paths:paths completion:completion];
    } else {
      [self->_camera takePictureAtPath:[paths firstObject] completion:completion];
    }
  });
}

- (void)setMirrorFrontCameraMirror:(nonnull NSNumber *)mirror error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return;
  }
  
  BOOL mirrorFrontCamera = [mirror boolValue];
  if (self.multiCamera != nil) {
    [self.multiCamera setMirrorFrontCamera:mirrorFrontCamera error:error];
  } else {
    [self.camera setMirrorFrontCamera:mirrorFrontCamera error:error];
  }
}

- (void)setCaptureModeMode:(nonnull NSString *)mode error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return;
  }
  
  CaptureModes captureMode = [CaptureModeUtils captureModeFromCaptureModeType:mode];
  if (self.multiCamera != nil) {
    if (captureMode == Video) {
      *error = [FlutterError errorWithCode:@"MULTI_CAMERA_UNSUPPORTED" message:@"impossible to set video mode when multi camera" details:nil];
      return;
    }
    
    [self.camera setCaptureMode:captureMode error:error];
  } else {
    [self.camera setCaptureMode:captureMode error:error];
  }
}

- (void)setCorrectionBrightness:(nonnull NSNumber *)brightness error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return;
  }
  if (self.multiCamera != nil) {
    [self.multiCamera setBrightness:brightness error:error];
  } else {
    [self.camera setBrightness:brightness error:error];
  }
}

- (void)setExifPreferencesExifPreferences:(ExifPreferences *)exifPreferences completion:(void(^)(NSNumber *_Nullable, FlutterError *_Nullable))completion {
  if (self.camera == nil && self.multiCamera == nil) {
    completion(nil, [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil]);
    return;
  }
  
  if (self.multiCamera != nil) {
    [self.multiCamera setExifPreferencesGPSLocation: exifPreferences.saveGPSLocation completion:completion];
  } else {
    [self.camera setExifPreferencesGPSLocation: exifPreferences.saveGPSLocation completion:completion];
  }
}

- (void)setFlashModeMode:(nonnull NSString *)mode error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (mode == nil || mode.length <= 0) {
    *error = [FlutterError errorWithCode:@"FLASH_MODE_ERROR" message:@"a flash mode NONE, AUTO, ALWAYS must be provided" details:nil];
    return;
  }
  
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return;
  }
  
  CameraFlashMode flash = [FlashModeUtils flashFromString:mode];
  if (self.multiCamera != nil) {
    [self.multiCamera setFlashMode:flash error:error];
  } else {
    [self.camera setFlashMode:flash error:error];
  }
}

- (void)setPhotoSizeSize:(nonnull PreviewSize *)size error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (size.width <= 0 || size.height <= 0) {
    *error = [FlutterError errorWithCode:@"NO_SIZE_SET" message:@"width and height must be set" details:nil];
    return;
  }
  
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return;
  }
  
  if (self.camera == nil) {
    *error = [FlutterError errorWithCode:@"MULTI_CAMERA_UNSUPPORTED" message:@"this feature is currently not supported with multi camera feature" details:nil];
    return;
  }
  
  [self.camera setCameraPreset:CGSizeMake([size.width floatValue], [size.height floatValue])];
}

- (void)setAspectRatioAspectRatio:(nonnull NSString *)aspectRatio error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (aspectRatio == nil || aspectRatio.length <= 0) {
    *error = [FlutterError errorWithCode:@"RATIO_NOT_SET" message:@"a ratio must be set" details:nil];
    return;
  }
  
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return;
  }
  
  AspectRatio aspectRatioMode = [AspectRatioUtils convertAspectRatio:aspectRatio];
  if (self.multiCamera != nil) {
    [self.multiCamera setAspectRatio:aspectRatioMode];
  } else {
    [self.camera setAspectRatio:aspectRatioMode];
  }
}

#pragma mark - Preview methods

- (nullable NSArray<PreviewSize *> *)availableSizesWithError:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return @[];
  }
  
  if (self.multiCamera != nil) {
    return [CameraQualities captureFormatsForDevice:self.multiCamera.devices.firstObject.device];
  } else {
    return [CameraQualities captureFormatsForDevice:self.camera.captureDevice];
  }
}

- (void)setPreviewSizeSize:(nonnull PreviewSize *)size error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (size.width <= 0 || size.height <= 0) {
    *error = [FlutterError errorWithCode:@"NO_SIZE_SET" message:@"width and height must be set" details:nil];
    return;
  }
  
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return;
  }
  
  if (self.multiCamera != nil) {
    [self.multiCamera setPreviewSize:CGSizeMake([size.width floatValue], [size.height floatValue]) error:error];
  } else {
    [self.camera setPreviewSize:CGSizeMake([size.width floatValue], [size.height floatValue]) error:error];
  }
}

- (nullable PreviewSize *)getEffectivPreviewSizeIndex:(nonnull NSNumber *)index error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
  }
  
  CGSize previewSize;
  if (self.multiCamera != nil) {
    previewSize = [self.multiCamera getEffectivPreviewSize];
  } else {
    previewSize = [self.camera getEffectivPreviewSize];
  }
  
  // height & width are inverted, this is intentionnal, because camera is always on portrait mode
  return [PreviewSize makeWithWidth:@(previewSize.height) height:@(previewSize.width)];
}

#pragma mark - Zoom methods

- (nullable NSNumber *)getMaxZoomWithError:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
  }
  
  if (self.multiCamera != nil) {
    return @([self.multiCamera getMaxZoom]);
  } else {
    return @([self.camera getMaxZoom]);
  }
}

- (nullable NSNumber *)getMinZoomWithError:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  return @(0);
}

- (void)setZoomZoom:(nonnull NSNumber *)zoom error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return;
  }
  
  if (self.multiCamera != nil) {
    [self.multiCamera setZoom:[zoom floatValue] error:error];
  } else {
    [self.camera setZoom:[zoom floatValue] error:error];
  }
}

#pragma mark - AVFoundation photo controls

- (nullable SingleCameraPreview *)singleCameraForPhotoControlsWithError:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return nil;
  }
  if (self.camera == nil) {
    *error = [FlutterError errorWithCode:@"MULTI_CAMERA_UNSUPPORTED" message:@"this feature is currently not supported with multi camera feature" details:nil];
    return nil;
  }
  return self.camera;
}

// MARK: Exposure

- (void)setExposureModeMode:(PigeonExposureMode)mode error:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return;
  AVCaptureExposureMode avMode;
  switch (mode) {
    case PigeonExposureModeLocked: avMode = AVCaptureExposureModeLocked; break;
    case PigeonExposureModeAuto: avMode = AVCaptureExposureModeAutoExpose; break;
    case PigeonExposureModeContinuousAuto: avMode = AVCaptureExposureModeContinuousAutoExposure; break;
    case PigeonExposureModeCustom: avMode = AVCaptureExposureModeCustom; break;
    default: avMode = AVCaptureExposureModeContinuousAutoExposure; break;
  }
  [camera setExposureMode:avMode error:error];
}

- (void)setExposurePointX:(NSNumber *)x y:(NSNumber *)y previewSize:(PreviewSize *)previewSize error:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return;
  [camera setExposurePoint:CGPointMake([x floatValue], [y floatValue]) preview:CGSizeMake([previewSize.width floatValue], [previewSize.height floatValue]) error:error];
}

- (void)setExposureTargetBiasBias:(NSNumber *)bias error:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return;
  [camera setExposureTargetBias:[bias floatValue] error:error];
}

- (void)setManualExposureIso:(NSNumber *)iso exposureDurationSeconds:(NSNumber *)exposureDurationSeconds error:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return;
  [camera setManualExposureWithISO:[iso floatValue] durationSeconds:[exposureDurationSeconds doubleValue] error:error];
}

- (nullable PigeonExposureState *)getExposureStateWithError:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return nil;
  return [camera getExposureStateWithError:error];
}

- (nullable PigeonCameraSettings *)getCameraSettingsWithError:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return nil;
  return [camera getCameraSettingsWithError:error];
}

// MARK: Focus

- (void)setFocusModeMode:(PigeonFocusMode)mode error:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return;
  AVCaptureFocusMode avMode;
  switch (mode) {
    case PigeonFocusModeLocked: avMode = AVCaptureFocusModeLocked; break;
    case PigeonFocusModeAuto: avMode = AVCaptureFocusModeAutoFocus; break;
    case PigeonFocusModeContinuousAuto: avMode = AVCaptureFocusModeContinuousAutoFocus; break;
    default: avMode = AVCaptureFocusModeContinuousAutoFocus; break;
  }
  [camera setFocusMode:avMode error:error];
}

- (void)setLensPositionLensPosition:(NSNumber *)lensPosition error:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return;
  [camera setLensPosition:[lensPosition floatValue] error:error];
}

- (nullable NSNumber *)getLensPositionWithError:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return nil;
  return @([camera getLensPosition]);
}

- (void)setAutoFocusRangeRestrictionRestriction:(PigeonFocusRangeRestriction)restriction error:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return;
  AVCaptureAutoFocusRangeRestriction avRestriction;
  switch (restriction) {
    case PigeonFocusRangeRestrictionNone: avRestriction = AVCaptureAutoFocusRangeRestrictionNone; break;
    case PigeonFocusRangeRestrictionNear: avRestriction = AVCaptureAutoFocusRangeRestrictionNear; break;
    case PigeonFocusRangeRestrictionFar: avRestriction = AVCaptureAutoFocusRangeRestrictionFar; break;
    default: avRestriction = AVCaptureAutoFocusRangeRestrictionNone; break;
  }
  [camera setAutoFocusRangeRestriction:avRestriction error:error];
}

- (void)setSmoothAutoFocusEnabledEnabled:(NSNumber *)enabled error:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return;
  [camera setSmoothAutoFocusEnabled:[enabled boolValue] error:error];
}

// MARK: White balance

- (void)setWhiteBalanceModeMode:(PigeonWhiteBalanceMode)mode error:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return;
  AVCaptureWhiteBalanceMode avMode;
  switch (mode) {
    case PigeonWhiteBalanceModeLocked: avMode = AVCaptureWhiteBalanceModeLocked; break;
    case PigeonWhiteBalanceModeAuto: avMode = AVCaptureWhiteBalanceModeAutoWhiteBalance; break;
    case PigeonWhiteBalanceModeContinuousAuto: avMode = AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance; break;
    default: avMode = AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance; break;
  }
  [camera setWhiteBalanceMode:avMode error:error];
}

- (void)setWhiteBalanceGainsGains:(PigeonWhiteBalanceGains *)gains error:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return;
  [camera setWhiteBalanceGainsRed:[gains.red floatValue] green:[gains.green floatValue] blue:[gains.blue floatValue] error:error];
}

- (void)setWhiteBalanceTemperatureTintTemperature:(NSNumber *)temperature tint:(NSNumber *)tint error:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return;
  [camera setWhiteBalanceTemperature:[temperature floatValue] tint:[tint floatValue] error:error];
}

- (nullable PigeonWhiteBalanceGains *)getWhiteBalanceGainsWithError:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return nil;
  return [camera getWhiteBalanceGainsWithError:error];
}

- (nullable NSNumber *)getMaxWhiteBalanceGainWithError:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return nil;
  return @([camera getMaxWhiteBalanceGain]);
}

- (void)setGrayWorldWhiteBalanceWithError:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return;
  [camera setGrayWorldWhiteBalanceWithError:error];
}

// MARK: Lighting

- (void)setTorchModeMode:(PigeonTorchMode)mode error:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return;
  AVCaptureTorchMode avMode;
  switch (mode) {
    case PigeonTorchModeOff: avMode = AVCaptureTorchModeOff; break;
    case PigeonTorchModeOn: avMode = AVCaptureTorchModeOn; break;
    case PigeonTorchModeAuto: avMode = AVCaptureTorchModeAuto; break;
    default: avMode = AVCaptureTorchModeOff; break;
  }
  [camera setTorchModeValue:avMode error:error];
}

- (void)setTorchLevelLevel:(NSNumber *)level error:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return;
  [camera setTorchLevel:[level floatValue] error:error];
}

- (nullable NSNumber *)isTorchActiveWithError:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return nil;
  return @([camera isTorchActive]);
}

- (void)setLowLightBoostEnabledEnabled:(NSNumber *)enabled error:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return;
  [camera setLowLightBoostEnabled:[enabled boolValue] error:error];
}

- (nullable NSNumber *)isLowLightBoostSupportedWithError:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return nil;
  return @([camera isLowLightBoostSupported]);
}

// MARK: Color

- (void)setColorSpaceColorSpace:(PigeonColorSpace)colorSpace error:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return;
  // PigeonColorSpace is laid out to match AVCaptureColorSpace raw values
  // (sRGB=0, P3_D65=1, HLG_BT2020=2, appleLog=3).
  [camera setColorSpace:(AVCaptureColorSpace)colorSpace error:error];
}

- (nullable NSArray<NSString *> *)getAvailableColorSpacesWithError:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return nil;
  return [camera getAvailableColorSpaces];
}

- (void)setAutoRedEyeReductionEnabledEnabled:(NSNumber *)enabled error:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return;
  [camera setAutoRedEyeReductionEnabled:[enabled boolValue]];
}

// MARK: Zoom (ratio based)

- (void)setZoomRatioRatio:(NSNumber *)ratio error:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return;
  [camera setZoomRatio:[ratio floatValue] error:error];
}

- (nullable NSNumber *)getMinZoomRatioWithError:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return nil;
  return @([camera getMinZoomRatio]);
}

- (nullable NSNumber *)getMaxZoomRatioWithError:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return nil;
  return @([camera getMaxZoomRatio]);
}

- (void)rampToZoomRatioRatio:(NSNumber *)ratio rate:(NSNumber *)rate error:(FlutterError *_Nullable *_Nonnull)error {
  SingleCameraPreview *camera = [self singleCameraForPhotoControlsWithError:error];
  if (camera == nil) return;
  [camera rampToZoomRatio:[ratio floatValue] rate:[rate floatValue] error:error];
}

#pragma mark - Image stream methods

- (void)receivedImageFromStreamWithError:(FlutterError *_Nullable *_Nonnull)error {
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return;
  }
  
  if (self.camera == nil) {
    *error = [FlutterError errorWithCode:@"MULTI_CAMERA_UNSUPPORTED" message:@"this feature is currently not supported with multi camera feature" details:nil];
    return;
  }
  
  [self.camera receivedImageFromStream];
}

- (void)setupImageAnalysisStreamFormat:(nonnull NSString *)format width:(nonnull NSNumber *)width maxFramesPerSecond:(nullable NSNumber *)maxFramesPerSecond autoStart:(nonnull NSNumber *)autoStart error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return;
  }
  
  if (self.camera == nil) {
    *error = [FlutterError errorWithCode:@"MULTI_CAMERA_UNSUPPORTED" message:@"this feature is currently not supported with multi camera feature" details:nil];
    return;
  }
  
  [self.camera.imageStreamController setStreamImages:autoStart];
  
  // Force a frame rate to improve performance
  [self.camera.imageStreamController setMaxFramesPerSecond:[maxFramesPerSecond floatValue]];
}

- (void)startAnalysisWithError:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return;
  }
  
  if (self.camera == nil) {
    *error = [FlutterError errorWithCode:@"MULTI_CAMERA_UNSUPPORTED" message:@"this feature is currently not supported with multi camera feature" details:nil];
    return;
  }
  
  [self.camera.imageStreamController setStreamImages:true];
}

- (void)stopAnalysisWithError:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return;
  }
  
  if (self.camera == nil) {
    *error = [FlutterError errorWithCode:@"MULTI_CAMERA_UNSUPPORTED" message:@"this feature is currently not supported with multi camera feature" details:nil];
    return;
  }
  
  [self.camera.imageStreamController setStreamImages:false];
}

- (void)isVideoRecordingAndImageAnalysisSupportedSensor:(PigeonSensorPosition)sensor completion:(void (^)(NSNumber *_Nullable, FlutterError *_Nullable))completion {
  completion(@(YES), nil);
}

#pragma mark - Sensors methods

- (nullable NSArray<PigeonSensorTypeDevice *> *)getFrontSensorsWithError:(FlutterError *_Nullable *_Nonnull)error {
  return [SensorsController getSensors:AVCaptureDevicePositionFront];
}

- (nullable NSArray<PigeonSensorTypeDevice *> *)getBackSensorsWithError:(FlutterError *_Nullable *_Nonnull)error {
  return [SensorsController getSensors:AVCaptureDevicePositionBack];
}

- (void)setSensorSensors:(nonnull NSArray<PigeonSensor *> *)sensors error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (self.camera == nil && self.multiCamera == nil) {
    *error = [FlutterError errorWithCode:@"CAMERA_MUST_BE_INIT" message:@"init must be call before start" details:nil];
    return;
  }
  
  if (sensors != nil && [sensors count] > 1 && self.multiCamera != nil) {
    if ([self.multiCamera.sensors count] != [sensors count]) {
      *error = [FlutterError errorWithCode:@"SENSORS_COUNT_INVALID" message:@"sensors count seems to be different, you can only update current sensors, adding or deleting is impossible for now" details:nil];
      return;
    }
    
    [self.multiCamera setSensors:sensors];
  } else {
    [self.camera setSensor:sensors.firstObject];
  }
}

#pragma mark - Filter methods

- (void)setFilterMatrix:(NSArray<NSNumber *> *)matrix error:(FlutterError *_Nullable *_Nonnull)error {
  // TODO: try to use CIFilter when taking a picture
}

#pragma mark - Multi camera methods

- (nullable NSNumber *)isMultiCamSupportedWithError:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  return [NSNumber numberWithBool: [MultiCameraController isMultiCamSupported]];
}

- (void)bgra8888toJpegBgra8888image:(nonnull AnalysisImageWrapper *)bgra8888image jpegQuality:(nonnull NSNumber *)jpegQuality completion:(nonnull void (^)(AnalysisImageWrapper * _Nullable, FlutterError * _Nullable))completion {
  dispatch_async(_dispatchQueueAnalysis, ^{
    [AnalysisController bgra8888toJpegBgra8888image:bgra8888image jpegQuality:jpegQuality completion:completion];
  });
}

- (void)nv21toJpegNv21Image:(nonnull AnalysisImageWrapper *)nv21Image jpegQuality:(nonnull NSNumber *)jpegQuality completion:(nonnull void (^)(AnalysisImageWrapper * _Nullable, FlutterError * _Nullable))completion {
  [AnalysisController nv21toJpegNv21Image:nv21Image jpegQuality:jpegQuality completion:completion];
}

- (void)yuv420toJpegYuvImage:(nonnull AnalysisImageWrapper *)yuvImage jpegQuality:(nonnull NSNumber *)jpegQuality completion:(nonnull void (^)(AnalysisImageWrapper * _Nullable, FlutterError * _Nullable))completion {
  [AnalysisController yuv420toJpegYuvImage:yuvImage jpegQuality:jpegQuality completion:completion];
}

- (void)yuv420toNv21YuvImage:(nonnull AnalysisImageWrapper *)yuvImage completion:(nonnull void (^)(AnalysisImageWrapper * _Nullable, FlutterError * _Nullable))completion {
  [AnalysisController yuv420toNv21YuvImage:yuvImage completion:completion];
}

@end
