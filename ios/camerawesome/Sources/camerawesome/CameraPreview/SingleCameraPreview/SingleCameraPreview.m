//
//  CameraPreview.m
//  camerawesome
//
//  Created by Dimitri Dessus on 23/07/2020.
//

#import "SingleCameraPreview.h"

@implementation SingleCameraPreview {
  dispatch_queue_t _dispatchQueue;
  BOOL _autoRedEyeReductionEnabled;
}

- (instancetype)initWithCameraSensor:(PigeonSensorPosition)sensor
                        videoOptions:(nullable CupertinoVideoOptions *)videoOptions
                    recordingQuality:(VideoRecordingQuality)recordingQuality
                        streamImages:(BOOL)streamImages
                   mirrorFrontCamera:(BOOL)mirrorFrontCamera
                enablePhysicalButton:(BOOL)enablePhysicalButton
                     aspectRatioMode:(AspectRatio)aspectRatioMode
                         captureMode:(CaptureModes)captureMode
                          completion:(nonnull void (^)(NSNumber * _Nullable, FlutterError * _Nullable))completion
                       dispatchQueue:(dispatch_queue_t)dispatchQueue {
  self = [super init];
  
  _completion = completion;
  _dispatchQueue = dispatchQueue;
  
  _previewTexture = [[CameraPreviewTexture alloc] init];
  
  _cameraSensorPosition = sensor;
  _aspectRatio = aspectRatioMode;
  _mirrorFrontCamera = mirrorFrontCamera;
  _videoOptions = videoOptions;
  _recordingQuality = recordingQuality;
  
  // Creating capture session
  _captureSession = [[AVCaptureSession alloc] init];
  _captureVideoOutput = [AVCaptureVideoDataOutput new];
  _captureVideoOutput.videoSettings = @{(NSString*)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
  [_captureVideoOutput setAlwaysDiscardsLateVideoFrames:YES];
  [_captureVideoOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
  [_captureSession addOutputWithNoConnections:_captureVideoOutput];
  
  [self initCameraPreview:sensor];
  
  [_captureConnection setAutomaticallyAdjustsVideoMirroring:NO];
  if (mirrorFrontCamera && [_captureConnection isVideoMirroringSupported]) {
    [_captureConnection setVideoMirrored:mirrorFrontCamera];
  }
  
  _captureMode = captureMode;
  
  // By default enable auto flash mode
  _flashMode = AVCaptureFlashModeOff;
  _torchMode = AVCaptureTorchModeOff;
  
  _previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:_captureSession];
  _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
  
  // Controllers init
  _videoController = [[VideoController alloc] init];
  _imageStreamController = [[ImageStreamController alloc] initWithStreamImages:streamImages];
  _motionController = [[MotionController alloc] init];
  _locationController = [[LocationController alloc] init];
  _physicalButtonController = [[PhysicalButtonController alloc] init];
  
  [_motionController startMotionDetection];
  
  if (enablePhysicalButton) {
    [_physicalButtonController startListening];
  }
  
  [self setBestPreviewQuality];
  
  return self;
}

- (void)setAspectRatio:(AspectRatio)ratio {
  _aspectRatio = ratio;
}

/// Set image stream Flutter sink
- (void)setImageStreamEvent:(FlutterEventSink)imageStreamEventSink {
  if (_imageStreamController != nil) {
    [_imageStreamController setImageStreamEventSink:imageStreamEventSink];
  }
}

/// Set orientation stream Flutter sink
- (void)setOrientationEventSink:(FlutterEventSink)orientationEventSink {
  if (_motionController != nil) {
    [_motionController setOrientationEventSink:orientationEventSink];
  }
}

/// Set physical button Flutter sink
- (void)setPhysicalButtonEventSink:(FlutterEventSink)physicalButtonEventSink {
  if (_physicalButtonController != nil) {
    [_physicalButtonController setPhysicalButtonEventSink:physicalButtonEventSink];
  }
}

// TODO: move this to a QualityController
/// Assign the default preview qualities
- (void)setBestPreviewQuality {
  NSArray *qualities = [CameraQualities captureFormatsForDevice:_captureDevice];
  PreviewSize *firstPreviewSize = [qualities count] > 0 ? qualities.lastObject : [PreviewSize makeWithWidth:@3840 height:@2160];
  
  CGSize firstSize = CGSizeMake([firstPreviewSize.width floatValue], [firstPreviewSize.height floatValue]);
  [self setCameraPreset:firstSize];
}

/// Save exif preferences when taking picture
- (void)setExifPreferencesGPSLocation:(bool)gpsLocation completion:(void(^)(NSNumber *_Nullable, FlutterError *_Nullable))completion {
  _saveGPSLocation = gpsLocation;
  
  if (_saveGPSLocation) {
    [_locationController requestWhenInUseAuthorizationOnGranted:^{
      completion(@(YES), nil);
    } declined:^{
      completion(@(NO), nil);
    }];
  } else {
    completion(@(YES), nil);
  }
}

/// Init camera preview with Front or Rear sensor
- (void)initCameraPreview:(PigeonSensorPosition)sensor {
  // Here we set a preset which wont crash the device before switching to front or back
  [_captureSession setSessionPreset:AVCaptureSessionPresetPhoto];
  
  NSError *error;
  _captureDevice = [AVCaptureDevice deviceWithUniqueID:[self selectAvailableCamera:sensor]];
  _captureVideoInput = [AVCaptureDeviceInput deviceInputWithDevice:_captureDevice error:&error];
  
  if (error != nil) {
    _completion(nil, [FlutterError errorWithCode:@"CANNOT_OPEN_CAMERA" message:@"can't attach device to input" details:[error localizedDescription]]);
    return;
  }
  
  // Create connection
  _captureConnection = [AVCaptureConnection connectionWithInputPorts:_captureVideoInput.ports
                                                              output:_captureVideoOutput];
  
  // TODO: works but deprecated...
  //  if ([_captureConnection isVideoMinFrameDurationSupported] && [_captureConnection isVideoMaxFrameDurationSupported]) {
  //    CMTime frameDuration = CMTimeMake(1, 12);
  //    [_captureConnection setVideoMinFrameDuration:frameDuration];
  //    [_captureConnection setVideoMaxFrameDuration:frameDuration];
  //  } else {
  //    NSLog(@"Failed to set frame duration");
  //  }
  
  // Attaching to session
  [_captureSession addInputWithNoConnections:_captureVideoInput];
  [_captureSession addConnection:_captureConnection];
  
  // Creating photo output
  _capturePhotoOutput = [AVCapturePhotoOutput new];
  [_capturePhotoOutput setHighResolutionCaptureEnabled:YES];
  [_captureSession addOutput:_capturePhotoOutput];
  
  // Mirror the preview only on portrait mode
  [_captureConnection setAutomaticallyAdjustsVideoMirroring:NO];
  [_captureConnection setVideoMirrored:(_cameraSensorPosition == PigeonSensorPositionFront)];
  [_captureConnection setVideoOrientation:AVCaptureVideoOrientationPortrait];
}

- (void)dealloc {
  [self.motionController startMotionDetection];
}

/// Set camera preview size
- (void)setCameraPreset:(CGSize)currentPreviewSize {
  CGSize targetSize = currentPreviewSize;

  // Determine the target size based on the current mode and settings
  if (_captureMode == Video || _videoController.isRecording) {
      // If recording video, prioritize the recording quality setting
      // TODO: Need a way to get the CGSize from the _recordingQuality enum or _videoOptions
      // For now, let's assume a helper function or default high quality if direct mapping isn't obvious.
      // Placeholder: If video options exist, try to use them, otherwise fall back.
      // If no direct mapping, maybe use the highest available preset suitable for video?
      // Or just pass CGSizeZero to let selectVideoCapturePreset pick the best for video?
      // For now, let's pass CGSizeZero to select the best default for video capture.
      if (_videoOptions != nil) {
         // Hypothetical: Get size from VideoOptions quality. Needs actual implementation.
         // targetSize = [CameraQualities sizeFromQuality:_recordingQuality];
         // If no direct mapping, maybe use the highest available preset suitable for video?
         // Or just pass CGSizeZero to let selectVideoCapturePreset pick the best for video?
         // For now, let's pass CGSizeZero to select the best default for video capture.
         targetSize = CGSizeZero; 
      } else if (!CGSizeEqualToSize(currentPreviewSize, CGSizeZero)){
         // Use provided size if valid and no video options
         targetSize = currentPreviewSize;
      } else {
         // Fallback to best quality if no specific size or options given
         targetSize = CGSizeZero;
      }
  } else if (_imageStreamController.streamImages) {
      // If only streaming (not recording), force 720p for potential stability (based on commit history)
      targetSize = CGSizeMake(720, 1280);
  } else if (CGSizeEqualToSize(currentPreviewSize, CGSizeZero)) {
      // If neither recording nor streaming, and no size provided, use best quality
      targetSize = CGSizeZero;
  } 
  // else: Use the non-zero currentPreviewSize passed in.

  NSString *presetSelected;
  if (!CGSizeEqualToSize(CGSizeZero, targetSize)) {
    // Try to get the quality requested based on the determined target size
    presetSelected = [CameraQualities selectVideoCapturePreset:targetSize session:_captureSession device:_captureDevice];
  } else {
    // Compute the best quality supported by the camera device if targetSize is Zero
    presetSelected = [CameraQualities selectVideoCapturePreset:_captureSession device:_captureDevice];
  }

  // Check if the preset needs to be changed
  if (![_captureSession.sessionPreset isEqualToString:presetSelected]) {
      [_captureSession setSessionPreset:presetSelected];
      _currentPreset = presetSelected;
  } else {
      _currentPreset = _captureSession.sessionPreset;
  }

  // Use the corrected method name
  _currentPreviewSize = [CameraQualities getSizeForPreset:_currentPreset];

  [_videoController setPreviewSize:_currentPreviewSize];
}

/// Get current video prewiew size
- (CGSize)getEffectivPreviewSize {
  return _currentPreviewSize;
}

// Get max zoom level
- (CGFloat)getMaxZoom {
  CGFloat maxZoom = _captureDevice.activeFormat.videoMaxZoomFactor;
  // Not sure why on iPhone 14 Pro, zoom at 90 not working, so let's block to 50 which is very high
  return maxZoom > 50.0 ? 50.0 : maxZoom;
}

/// Dispose camera inputs & outputs
- (void)dispose {
  [self stop];
  [self.physicalButtonController stopListening];
  
  for (AVCaptureInput *input in [_captureSession inputs]) {
    [_captureSession removeInput:input];
  }
  for (AVCaptureOutput *output in [_captureSession outputs]) {
    [_captureSession removeOutput:output];
  }
}

/// Set preview size resolution
- (void)setPreviewSize:(CGSize)previewSize error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (_videoController.isRecording) {
    *error = [FlutterError errorWithCode:@"PREVIEW_SIZE" message:@"impossible to change preview size, video already recording" details:@""];
    return;
  }
  BOOL sessionIsRunning = _captureSession.isRunning;
  if (sessionIsRunning) {
      [_captureSession stopRunning];
  }
  [self setCameraPreset:previewSize];
  if (sessionIsRunning) {
    dispatch_async(_dispatchQueue, ^{
      [self->_captureSession startRunning];
    });
  }
}

/// Start camera preview
- (void)start {
  dispatch_async(_dispatchQueue, ^{
    [self->_captureSession startRunning];
  });
}

/// Stop camera preview
- (void)stop {
  [_captureSession stopRunning];
}

/// Set sensor between Front & Rear camera
- (void)setSensor:(PigeonSensor *)sensor {
  // Check if the session is running before changing the preset
  BOOL sessionIsRunning = _captureSession.isRunning;
  if (sessionIsRunning) {
      [_captureSession stopRunning];
  }
  // First remove all input & output
  [_captureSession beginConfiguration];
  
  // Only remove camera channel but keep audio
  for (AVCaptureInput *input in [_captureSession inputs]) {
    for (AVCaptureInputPort *port in input.ports) {
      if ([[port mediaType] isEqual:AVMediaTypeVideo]) {
        [_captureSession removeInput:input];
        break;
      }
    }
  }
  // FIX: Changed from setAudioIsDisconnected to setVideoIsDisconnected.
  // VIDEO is what's being switched (brief gap while new camera initializes),
  // not audio. Setting the wrong flag caused audio timestamps to be offset
  // while video timestamps weren't compensated for the gap, causing desync.
  // The videoIsDisconnected flag triggers proper timestamp gap compensation
  // in VideoController.m's captureOutput method.
  [_videoController setVideoIsDisconnected:YES];

  [_captureSession removeOutput:_capturePhotoOutput];
  [_captureSession removeConnection:_captureConnection];
  
  _cameraSensorPosition = sensor.position;
  _captureDeviceId = sensor.deviceId;
  
  // Init the camera preview with the selected sensor
  [self initCameraPreview:sensor.position];

  // Update VideoController with new capture device to re-apply custom FPS if recording
  // This fixes audio/video desync when switching cameras during recording with custom FPS
  [_videoController updateCaptureDevice:_captureDevice];

  [self setBestPreviewQuality];
  
  [_captureSession commitConfiguration];
  if (sessionIsRunning) {
    dispatch_async(_dispatchQueue, ^{
      [self->_captureSession startRunning];
    });
  }
}

/// Set zoom level
- (void)setZoom:(float)value error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  CGFloat maxZoom = [self getMaxZoom];
  CGFloat scaledZoom = value * (maxZoom - 1.0f) + 1.0f;
  
  NSError *zoomError;
  if ([_captureDevice lockForConfiguration:&zoomError]) {
    _captureDevice.videoZoomFactor = scaledZoom;
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"ZOOM_NOT_SET" message:@"can't set the zoom value" details:[zoomError localizedDescription]];
  }
}

- (void)setBrightness:(NSNumber *)brightness error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  NSError *brightnessError = nil;
  if ([_captureDevice lockForConfiguration:&brightnessError]) {
    AVCaptureExposureMode exposureMode = AVCaptureExposureModeContinuousAutoExposure;
    if ([_captureDevice isExposureModeSupported:exposureMode]) {
      [_captureDevice setExposureMode:exposureMode];
    }
    
    CGFloat minExposureTargetBias = _captureDevice.minExposureTargetBias;
    CGFloat maxExposureTargetBias = _captureDevice.maxExposureTargetBias;
    
    CGFloat exposureTargetBias = minExposureTargetBias + (maxExposureTargetBias - minExposureTargetBias) * [brightness floatValue];
    exposureTargetBias = MAX(minExposureTargetBias, MIN(maxExposureTargetBias, exposureTargetBias));
    
    [_captureDevice setExposureTargetBias:exposureTargetBias completionHandler:nil];
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"BRIGHTNESS_NOT_SET" message:@"can't set the brightness value" details:[brightnessError localizedDescription]];
  }
}

- (void)setMirrorFrontCamera:(bool)value error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  _mirrorFrontCamera = value;
  
  if ([_captureConnection isVideoMirroringSupported]) {
      [_captureConnection setVideoMirrored:value];
  }
}

/// Set flash mode
- (void)setFlashMode:(CameraFlashMode)flashMode error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (![_captureDevice hasFlash]) {
    *error = [FlutterError errorWithCode:@"FLASH_UNSUPPORTED" message:@"flash is not supported on this device" details:@""];
    return;
  }
  
  if (_cameraSensorPosition == PigeonSensorPositionFront) {
    *error = [FlutterError errorWithCode:@"FLASH_UNSUPPORTED" message:@"can't set flash for portrait mode" details:@""];
    return;
  }
  
  NSError *lockError;
  [_captureDevice lockForConfiguration:&lockError];
  if (lockError != nil) {
    *error = [FlutterError errorWithCode:@"FLASH_ERROR" message:@"impossible to change configuration" details:@""];
    return;
  }
  
  switch (flashMode) {
    case None:
      _torchMode = AVCaptureTorchModeOff;
      _flashMode = AVCaptureFlashModeOff;
      break;
    case On:
      _torchMode = AVCaptureTorchModeOff;
      _flashMode = AVCaptureFlashModeOn;
      break;
    case Auto:
      _torchMode = AVCaptureTorchModeAuto;
      _flashMode = AVCaptureFlashModeAuto;
      break;
    case Always:
      _torchMode = AVCaptureTorchModeOn;
      _flashMode = AVCaptureFlashModeOn;
      break;
    default:
      _torchMode = AVCaptureTorchModeAuto;
      _flashMode = AVCaptureFlashModeAuto;
      break;
  }
  [_captureDevice setTorchMode:_torchMode];
  [_captureDevice unlockForConfiguration];
}

/// Trigger focus on device at the specific point of the preview
- (void)focusOnPoint:(CGPoint)position preview:(CGSize)preview error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  NSError *lockError;
  if ([_captureDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus] && [_captureDevice isFocusPointOfInterestSupported]) {
    if ([_captureDevice lockForConfiguration:&lockError]) {
      if (lockError != nil) {
        *error = [FlutterError errorWithCode:@"FOCUS_ERROR" message:@"impossible to set focus point" details:@""];
        return;
      }
      
      [_captureDevice setFocusPointOfInterest:position];
      [_captureDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
      
      [_captureDevice unlockForConfiguration];
    }
  }
}

- (void)receivedImageFromStream {
  [self.imageStreamController receivedImageFromStream];
}

/// Get the first available camera on device (front or rear)
- (NSString *)selectAvailableCamera:(PigeonSensorPosition)sensor {
  if (_captureDeviceId != nil) {
    return _captureDeviceId;
  }
  
  // TODO: add dual & triple camera
  NSArray<AVCaptureDevice *> *devices = [[NSArray alloc] init];
  AVCaptureDeviceDiscoverySession *discoverySession = [AVCaptureDeviceDiscoverySession
                                                       discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeBuiltInWideAngleCamera, ]
                                                       mediaType:AVMediaTypeVideo
                                                       position:AVCaptureDevicePositionUnspecified];
  devices = discoverySession.devices;
  
  NSInteger cameraType = (sensor == PigeonSensorPositionFront) ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
  for (AVCaptureDevice *device in devices) {
    if ([device position] == cameraType) {
      return [device uniqueID];
    }
  }
  return nil;
}

/// Set capture mode between Photo & Video mode
- (void)setCaptureMode:(CaptureModes)captureMode error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (_videoController.isRecording) {
    *error = [FlutterError errorWithCode:@"CAPTURE_MODE" message:@"impossible to change capture mode, video already recording" details:@""];
    return;
  }
  
  _captureMode = captureMode;
  
  if (captureMode == Video) {
    [self setUpCaptureSessionForAudioError:^(NSError *audioError) {
      *error = [FlutterError errorWithCode:@"VIDEO_ERROR" message:@"error when trying to setup audio" details:[audioError localizedDescription]];
    }];
  }
}

- (void)refresh {
  if ([_captureSession isRunning]) {
    [self stop];
  }
  [self start];
}

# pragma mark - Camera picture

/// Take the picture into the given path
- (void)takePictureAtPath:(NSString *)path completion:(nonnull void (^)(NSNumber * _Nullable, FlutterError * _Nullable))completion {
  // Instanciate camera picture obj
  CameraPictureController *cameraPicture = [[CameraPictureController alloc] initWithPath:path
                                                                             orientation:_motionController.deviceOrientation
                                                                          sensorPosition:_cameraSensorPosition
                                                                         saveGPSLocation:_saveGPSLocation
                                                                       mirrorFrontCamera:_mirrorFrontCamera
                                                                             aspectRatio:_aspectRatio
                                                                              completion:completion
                                                                                callback:^{
    // If flash mode is always on, restore it back after photo is taken
    if (self->_torchMode == AVCaptureTorchModeOn) {
      [self->_captureDevice lockForConfiguration:nil];
      [self->_captureDevice setTorchMode:AVCaptureTorchModeOn];
      [self->_captureDevice unlockForConfiguration];
    }
    
    completion(@(YES), nil);
  }];
  
  // Create settings instance
  AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettings];
  [settings setFlashMode:_flashMode];
  [settings setHighResolutionPhotoEnabled:YES];
  if (_capturePhotoOutput.isAutoRedEyeReductionSupported) {
    [settings setAutoRedEyeReductionEnabled:_autoRedEyeReductionEnabled];
  }
  
  [_capturePhotoOutput capturePhotoWithSettings:settings
                                       delegate:cameraPicture];
  
}

# pragma mark - Camera video
/// Record video into the given path
- (void)recordVideoAtPath:(NSString *)path completion:(nonnull void (^)(FlutterError * _Nullable))completion {
  if (!_videoController.isRecording) {
    [_videoController recordVideoAtPath:path captureDevice:_captureDevice orientation:_motionController.deviceOrientation audioSetupCallback:^{
      [self setUpCaptureSessionForAudioError:^(NSError *error) {
        completion([FlutterError errorWithCode:@"VIDEO_ERROR" message:@"error when trying to setup audio" details:[error localizedDescription]]);
      }];
    } videoWriterCallback:^{
      if (self->_videoController.isAudioEnabled) {
        [self->_audioOutput setSampleBufferDelegate:self queue:self->_dispatchQueue];
      }
      [self->_captureVideoOutput setSampleBufferDelegate:self queue:self->_dispatchQueue];
      
      completion(nil);
    } options:_videoOptions quality: _recordingQuality completion:completion];
  } else {
    completion([FlutterError errorWithCode:@"VIDEO_ERROR" message:@"already recording video" details:@""]);
  }
}

/// Pause video recording
- (void)pauseVideoRecording {
  [_videoController pauseVideoRecording];
}

/// Resume video recording after being paused
- (void)resumeVideoRecording {
  [_videoController resumeVideoRecording];
}

/// Stop recording video
- (void)stopRecordingVideo:(nonnull void (^)(NSNumber * _Nullable, FlutterError * _Nullable))completion {
  if (_videoController.isRecording) {
    [_videoController stopRecordingVideo:completion];
  } else {
    completion(@(NO), [FlutterError errorWithCode:@"VIDEO_ERROR" message:@"video is not recording" details:@""]);
  }
}

/// Set audio recording mode
- (void)setRecordingAudioMode:(bool)isAudioEnabled completion:(void(^)(NSNumber *_Nullable, FlutterError *_Nullable))completion {
  if (_videoController.isRecording) {
    completion(@(NO), [FlutterError errorWithCode:@"CHANGE_AUDIO_MODE" message:@"impossible to change audio mode, video already recording" details:@""]);
    return;
  }
  
  [_captureSession beginConfiguration];
  [_videoController setIsAudioEnabled:isAudioEnabled];
  [_videoController setIsAudioSetup:NO];
  [_videoController setAudioIsDisconnected:YES];
  
  // Only remove audio channel input but keep video
  for (AVCaptureInput *input in [_captureSession inputs]) {
    for (AVCaptureInputPort *port in input.ports) {
      if ([[port mediaType] isEqual:AVMediaTypeAudio]) {
        [_captureSession removeInput:input];
        break;
      }
    }
  }
  // Only remove audio channel output but keep video
  [_captureSession removeOutput:_audioOutput];
  
  if (_videoController.isRecording) {
    [self setUpCaptureSessionForAudioError:^(NSError *error) {
      completion(@(NO), [FlutterError errorWithCode:@"VIDEO_ERROR" message:@"error when trying to setup audio" details:[error localizedDescription]]);
    }];
  }
  
  [_captureSession commitConfiguration];
  completion(@(YES), nil);
}

# pragma mark - Audio
/// Setup audio channel to record audio
- (void)setUpCaptureSessionForAudioError:(nonnull void (^)(NSError *))error {
  NSError *audioError = nil;
  // Create a device input with the device and add it to the session.
  // Setup the audio input.
  AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
  AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice
                                                                           error:&audioError];
  if (audioError) {
    error(audioError);
  }
  
  // Setup the audio output.
  _audioOutput = [[AVCaptureAudioDataOutput alloc] init];
  
  if ([_captureSession canAddInput:audioInput]) {
    [_captureSession addInput:audioInput];
    
    if ([_captureSession canAddOutput:_audioOutput]) {
      [_captureSession addOutput:_audioOutput];
      [_videoController setIsAudioSetup:YES];
    } else {
      [_videoController setIsAudioSetup:NO];
    }
  }
}

# pragma mark - Camera Delegates

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
  if (output == _captureVideoOutput) {
    [self.previewTexture updateBuffer:sampleBuffer];
    if (_onPreviewFrameAvailable) {
      _onPreviewFrameAvailable();
    }

    // Send to image stream controller if enabled
    if (_imageStreamController.streamImages) {
        [_imageStreamController captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection orientation:_motionController.deviceOrientation];
    }

    // Send to video recording controller if recording
    if (_videoController.isRecording) {
      // Ensure VideoController's captureOutput can handle being called multiple times for the same timestamp (once for video, once for audio)
      // or ensure it only processes the video buffer here.
      // Assuming it can differentiate based on 'output' or buffer type.
      [_videoController captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection captureVideoOutput:_captureVideoOutput];
    }
  } else if (output == _audioOutput) {
    // Send audio buffers only to video recording controller if recording & audio enabled
    if (_videoController.isRecording && _videoController.isAudioEnabled) {
      [_videoController captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection captureVideoOutput:nil]; // Pass nil for video output for audio
    }
  }
}

# pragma mark - AVFoundation photo controls

/// Convert a point expressed in the [preview] pixel coordinate space into a
/// normalized (0...1) point of interest expected by AVFoundation.
- (CGPoint)normalizedPointFromPoint:(CGPoint)point preview:(CGSize)preview {
  CGFloat x = preview.width > 0 ? point.x / preview.width : 0.5;
  CGFloat y = preview.height > 0 ? point.y / preview.height : 0.5;
  x = MAX(0.0, MIN(1.0, x));
  y = MAX(0.0, MIN(1.0, y));
  return CGPointMake(x, y);
}

// MARK: Exposure

- (void)setExposureMode:(AVCaptureExposureMode)mode error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (![_captureDevice isExposureModeSupported:mode]) {
    *error = [FlutterError errorWithCode:@"EXPOSURE_MODE_UNSUPPORTED" message:@"exposure mode not supported on this device" details:@""];
    return;
  }
  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    [_captureDevice setExposureMode:mode];
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"EXPOSURE_MODE_ERROR" message:@"can't set exposure mode" details:[lockError localizedDescription]];
  }
}

- (void)setExposurePoint:(CGPoint)point preview:(CGSize)preview error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (![_captureDevice isExposurePointOfInterestSupported]) {
    *error = [FlutterError errorWithCode:@"EXPOSURE_POINT_UNSUPPORTED" message:@"exposure point of interest is not supported" details:@""];
    return;
  }
  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    [_captureDevice setExposurePointOfInterest:[self normalizedPointFromPoint:point preview:preview]];
    if ([_captureDevice isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
      [_captureDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
    }
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"EXPOSURE_POINT_ERROR" message:@"can't set exposure point" details:[lockError localizedDescription]];
  }
}

- (void)setExposureTargetBias:(float)bias error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    float clamped = MAX(_captureDevice.minExposureTargetBias, MIN(_captureDevice.maxExposureTargetBias, bias));
    [_captureDevice setExposureTargetBias:clamped completionHandler:nil];
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"EXPOSURE_BIAS_ERROR" message:@"can't set exposure target bias" details:[lockError localizedDescription]];
  }
}

- (void)setManualExposureWithISO:(float)iso durationSeconds:(double)durationSeconds error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (![_captureDevice isExposureModeSupported:AVCaptureExposureModeCustom]) {
    *error = [FlutterError errorWithCode:@"EXPOSURE_CUSTOM_UNSUPPORTED" message:@"custom exposure is not supported on this device" details:@""];
    return;
  }
  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    AVCaptureDeviceFormat *format = _captureDevice.activeFormat;
    float clampedISO = MAX(format.minISO, MIN(format.maxISO, iso));

    CMTime duration = CMTimeMakeWithSeconds(durationSeconds, 1000000);
    CMTime minDuration = format.minExposureDuration;
    CMTime maxDuration = format.maxExposureDuration;
    if (CMTimeCompare(duration, minDuration) < 0) {
      duration = minDuration;
    } else if (CMTimeCompare(duration, maxDuration) > 0) {
      duration = maxDuration;
    }

    [_captureDevice setExposureModeCustomWithDuration:duration ISO:clampedISO completionHandler:nil];
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"EXPOSURE_CUSTOM_ERROR" message:@"can't set manual exposure" details:[lockError localizedDescription]];
  }
}

- (nullable PigeonExposureState *)getExposureStateWithError:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  AVCaptureDeviceFormat *format = _captureDevice.activeFormat;
  return [PigeonExposureState makeWithMinIso:@(format.minISO)
                                      maxIso:@(format.maxISO)
                                  currentIso:@(_captureDevice.ISO)
                  minExposureDurationSeconds:@(CMTimeGetSeconds(format.minExposureDuration))
                  maxExposureDurationSeconds:@(CMTimeGetSeconds(format.maxExposureDuration))
              currentExposureDurationSeconds:@(CMTimeGetSeconds(_captureDevice.exposureDuration))
                       minExposureTargetBias:@(_captureDevice.minExposureTargetBias)
                       maxExposureTargetBias:@(_captureDevice.maxExposureTargetBias)
                   currentExposureTargetBias:@(_captureDevice.exposureTargetBias)];
}

- (nullable PigeonCameraSettings *)getCameraSettingsWithError:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  AVCaptureDeviceFormat *format = _captureDevice.activeFormat;

  // Convert the current device white balance gains to temperature & tint.
  AVCaptureWhiteBalanceTemperatureAndTintValues tempAndTint =
      [_captureDevice temperatureAndTintValuesForDeviceWhiteBalanceGains:_captureDevice.deviceWhiteBalanceGains];

  // The Pigeon*Mode enums are intentionally ordered to match the matching
  // AVFoundation enums, so a direct cast is safe.
  return [PigeonCameraSettings makeWithExposureMode:(PigeonExposureMode)_captureDevice.exposureMode
                                 exposureTargetBias:@(_captureDevice.exposureTargetBias)
                              minExposureTargetBias:@(_captureDevice.minExposureTargetBias)
                              maxExposureTargetBias:@(_captureDevice.maxExposureTargetBias)
                                                iso:@(_captureDevice.ISO)
                                             minIso:@(format.minISO)
                                             maxIso:@(format.maxISO)
                            exposureDurationSeconds:@(CMTimeGetSeconds(_captureDevice.exposureDuration))
                         minExposureDurationSeconds:@(CMTimeGetSeconds(format.minExposureDuration))
                         maxExposureDurationSeconds:@(CMTimeGetSeconds(format.maxExposureDuration))
                                          focusMode:(PigeonFocusMode)_captureDevice.focusMode
                                       lensPosition:@(_captureDevice.lensPosition)
                                   whiteBalanceMode:(PigeonWhiteBalanceMode)_captureDevice.whiteBalanceMode
                                        temperature:@(tempAndTint.temperature)
                                               tint:@(tempAndTint.tint)
                                          torchMode:(PigeonTorchMode)_captureDevice.torchMode
                                        torchActive:@(_captureDevice.isTorchActive)
                               lowLightBoostEnabled:@(_captureDevice.automaticallyEnablesLowLightBoostWhenAvailable)
                                         colorSpace:(PigeonColorSpace)_captureDevice.activeColorSpace
                         autoRedEyeReductionEnabled:@(_autoRedEyeReductionEnabled)
                                          zoomRatio:@(_captureDevice.videoZoomFactor)
                                       minZoomRatio:@([self getMinZoomRatio])
                                       maxZoomRatio:@([self getMaxZoomRatio])];
}

// MARK: Focus

- (void)setFocusMode:(AVCaptureFocusMode)mode error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (![_captureDevice isFocusModeSupported:mode]) {
    *error = [FlutterError errorWithCode:@"FOCUS_MODE_UNSUPPORTED" message:@"focus mode not supported on this device" details:@""];
    return;
  }
  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    [_captureDevice setFocusMode:mode];
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"FOCUS_MODE_ERROR" message:@"can't set focus mode" details:[lockError localizedDescription]];
  }
}

- (void)setLensPosition:(float)lensPosition error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (![_captureDevice isLockingFocusWithCustomLensPositionSupported]) {
    *error = [FlutterError errorWithCode:@"LENS_POSITION_UNSUPPORTED" message:@"locking focus with custom lens position is not supported" details:@""];
    return;
  }
  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    float clamped = MAX(0.0, MIN(1.0, lensPosition));
    [_captureDevice setFocusModeLockedWithLensPosition:clamped completionHandler:nil];
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"LENS_POSITION_ERROR" message:@"can't set lens position" details:[lockError localizedDescription]];
  }
}

- (CGFloat)getLensPosition {
  return _captureDevice.lensPosition;
}

- (void)setAutoFocusRangeRestriction:(AVCaptureAutoFocusRangeRestriction)restriction error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (![_captureDevice isAutoFocusRangeRestrictionSupported]) {
    *error = [FlutterError errorWithCode:@"FOCUS_RANGE_UNSUPPORTED" message:@"auto focus range restriction is not supported" details:@""];
    return;
  }
  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    [_captureDevice setAutoFocusRangeRestriction:restriction];
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"FOCUS_RANGE_ERROR" message:@"can't set auto focus range restriction" details:[lockError localizedDescription]];
  }
}

- (void)setSmoothAutoFocusEnabled:(BOOL)enabled error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (![_captureDevice isSmoothAutoFocusSupported]) {
    *error = [FlutterError errorWithCode:@"SMOOTH_FOCUS_UNSUPPORTED" message:@"smooth auto focus is not supported" details:@""];
    return;
  }
  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    [_captureDevice setSmoothAutoFocusEnabled:enabled];
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"SMOOTH_FOCUS_ERROR" message:@"can't set smooth auto focus" details:[lockError localizedDescription]];
  }
}

// MARK: White balance

/// Clamp each component of the given gains to the [1.0, maxWhiteBalanceGain] range.
- (AVCaptureWhiteBalanceGains)clampedWhiteBalanceGains:(AVCaptureWhiteBalanceGains)gains {
  CGFloat maxGain = _captureDevice.maxWhiteBalanceGain;
  gains.redGain = MAX(1.0, MIN(maxGain, gains.redGain));
  gains.greenGain = MAX(1.0, MIN(maxGain, gains.greenGain));
  gains.blueGain = MAX(1.0, MIN(maxGain, gains.blueGain));
  return gains;
}

- (void)setWhiteBalanceMode:(AVCaptureWhiteBalanceMode)mode error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (![_captureDevice isWhiteBalanceModeSupported:mode]) {
    *error = [FlutterError errorWithCode:@"WB_MODE_UNSUPPORTED" message:@"white balance mode not supported on this device" details:@""];
    return;
  }
  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    [_captureDevice setWhiteBalanceMode:mode];
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"WB_MODE_ERROR" message:@"can't set white balance mode" details:[lockError localizedDescription]];
  }
}

- (void)setWhiteBalanceGainsRed:(float)red green:(float)green blue:(float)blue error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (![_captureDevice isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeLocked]) {
    *error = [FlutterError errorWithCode:@"WB_GAINS_UNSUPPORTED" message:@"locked white balance is not supported" details:@""];
    return;
  }
  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    AVCaptureWhiteBalanceGains gains;
    gains.redGain = red;
    gains.greenGain = green;
    gains.blueGain = blue;
    [_captureDevice setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:[self clampedWhiteBalanceGains:gains] completionHandler:nil];
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"WB_GAINS_ERROR" message:@"can't set white balance gains" details:[lockError localizedDescription]];
  }
}

- (void)setWhiteBalanceTemperature:(float)temperature tint:(float)tint error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (![_captureDevice isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeLocked]) {
    *error = [FlutterError errorWithCode:@"WB_TEMP_UNSUPPORTED" message:@"locked white balance is not supported" details:@""];
    return;
  }
  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    AVCaptureWhiteBalanceTemperatureAndTintValues values;
    values.temperature = temperature;
    values.tint = tint;
    AVCaptureWhiteBalanceGains gains = [_captureDevice deviceWhiteBalanceGainsForTemperatureAndTintValues:values];
    [_captureDevice setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:[self clampedWhiteBalanceGains:gains] completionHandler:nil];
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"WB_TEMP_ERROR" message:@"can't set white balance temperature" details:[lockError localizedDescription]];
  }
}

- (nullable PigeonWhiteBalanceGains *)getWhiteBalanceGainsWithError:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  AVCaptureWhiteBalanceGains gains = _captureDevice.deviceWhiteBalanceGains;
  return [PigeonWhiteBalanceGains makeWithRed:@(gains.redGain) green:@(gains.greenGain) blue:@(gains.blueGain)];
}

- (CGFloat)getMaxWhiteBalanceGain {
  return _captureDevice.maxWhiteBalanceGain;
}

- (void)setGrayWorldWhiteBalanceWithError:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (![_captureDevice isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeLocked]) {
    *error = [FlutterError errorWithCode:@"WB_GRAY_UNSUPPORTED" message:@"locked white balance is not supported" details:@""];
    return;
  }
  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    AVCaptureWhiteBalanceGains gains = _captureDevice.grayWorldDeviceWhiteBalanceGains;
    [_captureDevice setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:[self clampedWhiteBalanceGains:gains] completionHandler:nil];
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"WB_GRAY_ERROR" message:@"can't set gray world white balance" details:[lockError localizedDescription]];
  }
}

// MARK: Lighting

- (void)setTorchModeValue:(AVCaptureTorchMode)mode error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (![_captureDevice hasTorch] || ![_captureDevice isTorchModeSupported:mode]) {
    *error = [FlutterError errorWithCode:@"TORCH_UNSUPPORTED" message:@"torch mode not supported on this device" details:@""];
    return;
  }
  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    [_captureDevice setTorchMode:mode];
    _torchMode = mode;
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"TORCH_ERROR" message:@"can't set torch mode" details:[lockError localizedDescription]];
  }
}

- (void)setTorchLevel:(float)level error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (![_captureDevice hasTorch]) {
    *error = [FlutterError errorWithCode:@"TORCH_UNSUPPORTED" message:@"torch is not available on this device" details:@""];
    return;
  }
  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    if (level <= 0.0) {
      [_captureDevice setTorchMode:AVCaptureTorchModeOff];
      _torchMode = AVCaptureTorchModeOff;
    } else {
      float clamped = MIN(level, AVCaptureMaxAvailableTorchLevel);
      NSError *torchError;
      if (![_captureDevice setTorchModeOnWithLevel:clamped error:&torchError]) {
        *error = [FlutterError errorWithCode:@"TORCH_LEVEL_ERROR" message:@"can't set torch level" details:[torchError localizedDescription]];
      } else {
        _torchMode = AVCaptureTorchModeOn;
      }
    }
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"TORCH_LEVEL_ERROR" message:@"can't set torch level" details:[lockError localizedDescription]];
  }
}

- (BOOL)isTorchActive {
  return _captureDevice.isTorchActive;
}

- (void)setLowLightBoostEnabled:(BOOL)enabled error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (![_captureDevice isLowLightBoostSupported]) {
    *error = [FlutterError errorWithCode:@"LOW_LIGHT_UNSUPPORTED" message:@"low light boost is not supported" details:@""];
    return;
  }
  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    [_captureDevice setAutomaticallyEnablesLowLightBoostWhenAvailable:enabled];
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"LOW_LIGHT_ERROR" message:@"can't set low light boost" details:[lockError localizedDescription]];
  }
}

- (BOOL)isLowLightBoostSupported {
  return _captureDevice.isLowLightBoostSupported;
}

// MARK: Color

- (void)setColorSpace:(AVCaptureColorSpace)colorSpace error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (![_captureDevice.activeFormat.supportedColorSpaces containsObject:@(colorSpace)]) {
    *error = [FlutterError errorWithCode:@"COLOR_SPACE_UNSUPPORTED" message:@"color space not supported by the active format" details:@""];
    return;
  }
  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    _captureDevice.activeColorSpace = colorSpace;
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"COLOR_SPACE_ERROR" message:@"can't set color space" details:[lockError localizedDescription]];
  }
}

- (NSArray<NSString *> *)getAvailableColorSpaces {
  NSMutableArray<NSString *> *result = [NSMutableArray array];
  for (NSNumber *colorSpace in _captureDevice.activeFormat.supportedColorSpaces) {
    switch ([colorSpace integerValue]) {
      case 0:
        [result addObject:@"sRGB"];
        break;
      case 1:
        [result addObject:@"p3D65"];
        break;
      case 2:
        [result addObject:@"hlgBT2020"];
        break;
      case 3:
        [result addObject:@"appleLog"];
        break;
      default:
        break;
    }
  }
  return result;
}

- (void)setAutoRedEyeReductionEnabled:(BOOL)enabled {
  _autoRedEyeReductionEnabled = enabled;
}

// MARK: Zoom (ratio based)

- (void)setZoomRatio:(float)ratio error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  CGFloat clamped = MAX([self getMinZoomRatio], MIN([self getMaxZoomRatio], ratio));
  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    _captureDevice.videoZoomFactor = clamped;
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"ZOOM_RATIO_ERROR" message:@"can't set zoom ratio" details:[lockError localizedDescription]];
  }
}

- (CGFloat)getMinZoomRatio {
  return _captureDevice.minAvailableVideoZoomFactor;
}

- (CGFloat)getMaxZoomRatio {
  CGFloat deviceMax = _captureDevice.maxAvailableVideoZoomFactor;
  // Mirror the cap applied in getMaxZoom to avoid unstable very high factors.
  return deviceMax > 50.0 ? 50.0 : deviceMax;
}

- (void)rampToZoomRatio:(float)ratio rate:(float)rate error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  CGFloat clamped = MAX([self getMinZoomRatio], MIN([self getMaxZoomRatio], ratio));
  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    [_captureDevice rampToVideoZoomFactor:clamped withRate:rate];
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"ZOOM_RAMP_ERROR" message:@"can't ramp zoom" details:[lockError localizedDescription]];
  }
}

@end
