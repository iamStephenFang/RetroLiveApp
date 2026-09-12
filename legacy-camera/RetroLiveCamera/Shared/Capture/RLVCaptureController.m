#import "RLVCaptureController.h"
#import "RLVZoomMath.h"
#import <math.h>

NSString * const RLVCaptureControllerErrorDomain = @"com.retrolive.capture";

static const NSTimeInterval RLVTargetPreRollSeconds = 1.5;
static const NSTimeInterval RLVTargetPostRollSeconds = 1.5;
static const NSTimeInterval RLVMaximumRollingSegmentSeconds = 30.0;
static const CGFloat RLVMaximumUserZoomFactor = 3.0;

@interface RLVCaptureController () <AVCaptureFileOutputRecordingDelegate> {
    dispatch_queue_t _sessionQueue;
}
@property (nonatomic, assign, readwrite) RLVCaptureState state;
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDeviceInput *videoInput;
@property (nonatomic, strong) AVCaptureStillImageOutput *stillImageOutput;
@property (nonatomic, strong) AVCaptureMovieFileOutput *movieFileOutput;
@property (nonatomic, strong) AVCaptureDeviceInput *audioInput;
@property (nonatomic, strong, readwrite) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, assign, readwrite) AVCaptureDevicePosition cameraPosition;
@property (nonatomic, assign, readwrite, getter=isSwitchingCamera) BOOL switchingCamera;
@property (nonatomic, assign, readwrite) AVCaptureFlashMode flashMode;
@property (nonatomic, assign, readwrite) CGFloat zoomFactor;
@property (nonatomic, assign, readwrite) CGFloat requestedZoomFactor;
@property (nonatomic, assign, readwrite) CGFloat maximumZoomFactor;
@property (nonatomic, strong) NSURL *rollingURL;
@property (nonatomic, strong) NSDate *rollingStartedAt;
@property (nonatomic, strong) RLVCaptureEvent *pendingEvent;
@property (nonatomic, strong) NSData *pendingPhotoData;
@property (nonatomic, strong) NSURL *pendingMotionURL;
@property (nonatomic, assign) BOOL pendingMotionFinished;
@property (nonatomic, assign) BOOL pendingMotionRequested;
@property (nonatomic, assign) AVCaptureVideoOrientation rollingOrientation;
@property (nonatomic, assign) BOOL wantsSessionRunning;
@property (nonatomic, assign) NSUInteger sessionStartGeneration;
@property (nonatomic, assign) BOOL cameraSwitchPending;
@property (nonatomic, assign) BOOL orientationRestartPending;
@property (nonatomic, assign) CGFloat pendingZoomFactor;
@property (nonatomic, assign) NSUInteger pendingZoomRequestGeneration;
@property (nonatomic, assign) BOOL zoomUpdateScheduled;
@property (nonatomic, assign) NSUInteger zoomRequestGeneration;
@property (nonatomic, assign) NSUInteger cameraSwitchZoomRequestGeneration;
- (void)startSessionOnSessionQueueForGeneration:(NSUInteger)generation remainingRetries:(NSUInteger)remainingRetries;
- (void)resetFocusAndExposureForDevice:(AVCaptureDevice *)device;
- (void)subjectAreaDidChange:(NSNotification *)notification;
- (void)finishPointOfInterestRequest:(void (^)(RLVPointOfInterestResult result))completion
                              result:(RLVPointOfInterestResult)result;
- (void)removeAbandonedRollingFilesBeforeDate:(NSDate *)cutoffDate;
- (CGFloat)maximumZoomFactorForActiveCapturePipeline;
- (void)applyZoomFactorOnSessionQueue:(CGFloat)zoomFactor requestGeneration:(NSUInteger)requestGeneration;
- (NSUInteger)recordZoomTargetOnMainThread:(CGFloat)zoomFactor;
- (void)finishZoomRequestWithAppliedFactor:(CGFloat)zoomFactor
                             maximumFactor:(CGFloat)maximumFactor
                          requestGeneration:(NSUInteger)requestGeneration;
- (void)drainPendingZoomUpdates;
@end

@implementation RLVCaptureController

- (id)init
{
    self = [super init];
    if (self) {
        _state = RLVCaptureStateIdle;
        _cameraPosition = AVCaptureDevicePositionBack;
        _flashMode = AVCaptureFlashModeAuto;
        _zoomFactor = 1.0;
        _requestedZoomFactor = 1.0;
        _maximumZoomFactor = 1.0;
        _motionCaptureEnabled = YES;
        _rollingOrientation = AVCaptureVideoOrientationPortrait;
        _sessionQueue = dispatch_queue_create("com.retrolive.capture.session", DISPATCH_QUEUE_SERIAL);
        NSDate *cleanupCutoffDate = [NSDate date];
        __weak RLVCaptureController *controller = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            [controller removeAbandonedRollingFilesBeforeDate:cleanupCutoffDate];
        });
    }
    return self;
}

- (void)prepareWithCompletion:(void (^)(NSError *error))completion
{
    if (self.state != RLVCaptureStateIdle && self.state != RLVCaptureStateFailed) {
        if (completion) {
            completion(nil);
        }
        return;
    }
    [self updateState:RLVCaptureStatePreparing];
    dispatch_async(_sessionQueue, ^{
        NSError *error = nil;
        AVCaptureSession *session = [[AVCaptureSession alloc] init];
        // A continuously connected movie output is required for the rolling
        // pre-recording window. On older devices the Photo preset can leave
        // that output's video connection inactive even though canAddOutput:
        // succeeds, and starting it then raises NSInvalidArgumentException.
        if ([session canSetSessionPreset:AVCaptureSessionPresetHigh]) {
            session.sessionPreset = AVCaptureSessionPresetHigh;
        } else if ([session canSetSessionPreset:AVCaptureSessionPresetPhoto]) {
            session.sessionPreset = AVCaptureSessionPresetPhoto;
        }

        AVCaptureDevice *device = [self cameraWithPosition:AVCaptureDevicePositionBack];
        AVCaptureDeviceInput *input = device ? [AVCaptureDeviceInput deviceInputWithDevice:device error:&error] : nil;
        AVCaptureStillImageOutput *output = [[AVCaptureStillImageOutput alloc] init];
        output.outputSettings = [NSDictionary dictionaryWithObject:AVVideoCodecJPEG forKey:AVVideoCodecKey];
        AVCaptureMovieFileOutput *movieOutput = [[AVCaptureMovieFileOutput alloc] init];
        movieOutput.maxRecordedDuration = CMTimeMakeWithSeconds(RLVMaximumRollingSegmentSeconds, 600);
        AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
        AVCaptureDeviceInput *audioInput = audioDevice ? [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:NULL] : nil;
        BOOL motionCaptureAvailable = NO;

        [session beginConfiguration];
        if (input && [session canAddInput:input]) {
            [session addInput:input];
        } else if (error == nil) {
            error = [self errorWithCode:1 description:NSLocalizedString(@"capture.error.rear_camera", nil)];
        }
        if (error == nil && [session canAddOutput:output]) {
            [session addOutput:output];
        } else if (error == nil) {
            error = [self errorWithCode:2 description:NSLocalizedString(@"capture.error.still_output", nil)];
        }
        if (error == nil && [session canAddOutput:movieOutput]) {
            [session addOutput:movieOutput];
            motionCaptureAvailable = YES;
        }
        if (error == nil && audioInput && [session canAddInput:audioInput]) {
            [session addInput:audioInput];
        }
        [session commitConfiguration];

        if (error == nil) {
            self.session = session;
            self.videoInput = input;
            self.stillImageOutput = output;
            self.movieFileOutput = motionCaptureAvailable ? movieOutput : nil;
            self.audioInput = audioInput;
            _motionCaptureEnabled = motionCaptureAvailable;
            self.cameraPosition = [device position];
            self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:session];
            self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
            if ([device hasFlash] && [device isFlashModeSupported:AVCaptureFlashModeAuto] && [device lockForConfiguration:NULL]) {
                device.flashMode = AVCaptureFlashModeAuto;
                [device unlockForConfiguration];
            }
            [self resetFocusAndExposureForDevice:device];
            self.maximumZoomFactor = [self maximumZoomFactorForActiveCapturePipeline];
            [self applyZoomFactorOnSessionQueue:1.0 requestGeneration:0];
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionRuntimeError:)
                                                         name:AVCaptureSessionRuntimeErrorNotification object:session];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [self updateState:RLVCaptureStateFailed];
                [self notifyError:error];
            } else {
                [self updateState:RLVCaptureStateIdle];
                if (!motionCaptureAvailable &&
                    [self.delegate respondsToSelector:@selector(captureController:didChangeMotionCaptureEnabled:)]) {
                    [self.delegate captureController:self didChangeMotionCaptureEnabled:NO];
                }
            }
            if (completion) {
                completion(error);
            }
        });
    });
}

- (void)startRunning
{
    dispatch_async(_sessionQueue, ^{
        self.wantsSessionRunning = YES;
        NSUInteger generation = ++self.sessionStartGeneration;
        [self startSessionOnSessionQueueForGeneration:generation remainingRetries:1];
    });
}

- (void)startSessionOnSessionQueueForGeneration:(NSUInteger)generation remainingRetries:(NSUInteger)remainingRetries
{
    if (!self.wantsSessionRunning || generation != self.sessionStartGeneration) return;
    if (!self.session) return;

    BOOL wasRunning = [self.session isRunning];
    if (!wasRunning) [self.session startRunning];
    if ([self.session isRunning]) {
        AVCaptureConnection *previewConnection = self.previewLayer.connection;
        if (previewConnection && ![previewConnection isEnabled]) previewConnection.enabled = YES;
        if (!wasRunning) [self resetFocusAndExposureForDevice:self.videoInput.device];
        [self startRollingRecording];
        RLVCaptureState runningState = self.pendingEvent ? RLVCaptureStateCapturing : RLVCaptureStateRunning;
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateState:runningState]; });
        return;
    }

    if (remainingRetries > 0) {
        NSLog(@"RetroLive: capture session did not start; retrying once");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), _sessionQueue, ^{
            [self startSessionOnSessionQueueForGeneration:generation remainingRetries:remainingRetries - 1];
        });
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateState:RLVCaptureStateFailed];
        [self notifyError:[self errorWithCode:5 description:NSLocalizedString(@"capture.error.session_failed", nil)]];
    });
}

- (void)stopRunning
{
    NSUInteger zoomGeneration = [self recordZoomTargetOnMainThread:1.0];
    dispatch_async(_sessionQueue, ^{
        self.wantsSessionRunning = NO;
        self.sessionStartGeneration += 1;
        [self resetFocusAndExposureForDevice:self.videoInput.device];
        [self applyZoomFactorOnSessionQueue:1.0 requestGeneration:zoomGeneration];
        if ([self.movieFileOutput isRecording]) [self.movieFileOutput stopRecording];
        if ([self.session isRunning]) {
            [self.session stopRunning];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateState:RLVCaptureStateIdle]; });
    });
}

- (void)interrupt
{
    dispatch_async(_sessionQueue, ^{
        self.wantsSessionRunning = NO;
        self.sessionStartGeneration += 1;
        [self resetFocusAndExposureForDevice:self.videoInput.device];
        if ([self.movieFileOutput isRecording]) [self.movieFileOutput stopRecording];
        if ([self.session isRunning]) [self.session stopRunning];
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateState:RLVCaptureStateInterrupted]; });
    });
}

- (void)resumeAfterInterruption
{
    [self startRunning];
}

- (void)refreshPreviewLayer
{
    NSAssert([NSThread isMainThread], @"Preview layers must be refreshed on the main thread");
    AVCaptureSession *session = self.session;
    if (!session) return;
    AVCaptureVideoPreviewLayer *previousLayer = self.previewLayer;
    AVCaptureVideoPreviewLayer *replacementLayer = [AVCaptureVideoPreviewLayer layerWithSession:session];
    replacementLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.previewLayer = replacementLayer;
    [previousLayer removeFromSuperlayer];
    [self requestZoomFactor:self.requestedZoomFactor];
}

- (void)updateVideoOrientation:(AVCaptureVideoOrientation)videoOrientation
{
    dispatch_async(_sessionQueue, ^{
        if (self.rollingOrientation == videoOrientation) return;
        self.rollingOrientation = videoOrientation;
        if (self.pendingEvent) return;
        if ([self.movieFileOutput isRecording]) {
            self.orientationRestartPending = YES;
            [self.movieFileOutput stopRecording];
        } else if (self.wantsSessionRunning) {
            [self startRollingRecording];
        }
    });
}

- (void)setMotionCaptureEnabled:(BOOL)motionCaptureEnabled
{
    if (_motionCaptureEnabled == motionCaptureEnabled) return;
    _motionCaptureEnabled = motionCaptureEnabled;
    dispatch_async(_sessionQueue, ^{
        if (motionCaptureEnabled) {
            [self startRollingRecording];
        } else if ([self.movieFileOutput isRecording]) {
            [self.movieFileOutput stopRecording];
        } else {
            if (self.rollingURL) [[NSFileManager defaultManager] removeItemAtURL:self.rollingURL error:NULL];
            self.rollingURL = nil;
            self.rollingStartedAt = nil;
        }
    });
}

- (void)capturePhotoWithOrientation:(RLVCaptureOrientation)orientation
                   videoOrientation:(AVCaptureVideoOrientation)videoOrientation
                         aspectRatio:(NSString *)aspectRatio
{
    if (self.state != RLVCaptureStateRunning) {
        return;
    }

    RLVCaptureEvent *event = [[RLVCaptureEvent alloc] init];
    event.assetId = [[[NSUUID UUID] UUIDString] uppercaseString];
    event.shutterTimestamp = [NSDate date];
    event.orientation = orientation;
    event.cameraPosition = self.cameraPosition;
    event.mirrored = self.cameraPosition == AVCaptureDevicePositionFront;
    event.flashMode = [self stringForFlashMode:self.flashMode];
    event.aspectRatio = aspectRatio ?: @"4:3";
    self.pendingEvent = event;
    self.pendingPhotoData = nil;
    self.pendingMotionURL = nil;
    self.pendingMotionFinished = NO;
    self.pendingMotionRequested = self.isMotionCaptureEnabled && [self.movieFileOutput isRecording];
    [self updateState:RLVCaptureStateCapturing];

    dispatch_async(_sessionQueue, ^{
        AVCaptureConnection *connection = [self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo];
        if (connection == nil) {
            self.pendingEvent = nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateState:RLVCaptureStateRunning];
                [self notifyError:[self errorWithCode:6 description:NSLocalizedString(@"capture.error.still_connection", nil)]];
            });
            return;
        }
        if ([connection isVideoOrientationSupported]) {
            connection.videoOrientation = videoOrientation;
        }
        if ([connection isVideoMirroringSupported]) {
            connection.videoMirrored = event.isMirrored;
        }
        [self.stillImageOutput captureStillImageAsynchronouslyFromConnection:connection
                                                           completionHandler:^(CMSampleBufferRef buffer, NSError *error) {
            NSData *data = buffer ? [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:buffer] : nil;
            dispatch_async(self->_sessionQueue, ^{
                if (self.pendingEvent != event) return;
                if (!data) {
                    [self failPendingCapture:error ?: [self errorWithCode:3 description:NSLocalizedString(@"capture.error.no_jpeg", nil)]];
                    return;
                }
                self.pendingPhotoData = data;
                if (self.pendingMotionFinished) {
                    [self completePendingCaptureWithMotionURL:nil];
                }
            });
        }];
        if (self.pendingMotionRequested && [self.movieFileOutput isRecording]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(RLVTargetPostRollSeconds * NSEC_PER_SEC)), self->_sessionQueue, ^{
                if (self.pendingEvent == event && [self.movieFileOutput isRecording]) {
                    [self.movieFileOutput stopRecording];
                }
            });
        } else {
            self.pendingMotionFinished = YES;
        }
    });
}

- (BOOL)isRecordingMotion
{
    return [self.movieFileOutput isRecording];
}

- (void)switchCamera
{
    if (self.state != RLVCaptureStateRunning) {
        return;
    }
    self.switchingCamera = YES;
    self.cameraSwitchZoomRequestGeneration = [self recordZoomTargetOnMainThread:1.0];
    dispatch_async(_sessionQueue, ^{
        if ([self.movieFileOutput isRecording]) {
            self.cameraSwitchPending = YES;
            [self.movieFileOutput stopRecording];
            return;
        }
        [self performCameraSwitch];
    });
}

- (void)performCameraSwitch
{
        AVCaptureDevicePosition desired = self.cameraPosition == AVCaptureDevicePositionBack
            ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
        AVCaptureDevice *previousDevice = self.videoInput.device;
        AVCaptureDevice *device = [self cameraWithPosition:desired];
        NSError *error = nil;
        AVCaptureDeviceInput *input = device ? [AVCaptureDeviceInput deviceInputWithDevice:device error:&error] : nil;
        if (!input) {
            [self finishZoomRequestWithAppliedFactor:self.zoomFactor
                                       maximumFactor:self.maximumZoomFactor
                                    requestGeneration:self.cameraSwitchZoomRequestGeneration];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.switchingCamera = NO;
                [self notifyError:error ?: [self errorWithCode:4 description:NSLocalizedString(@"capture.error.unavailable", nil)]];
            });
            self.cameraSwitchPending = NO;
            return;
        }
        [self resetFocusAndExposureForDevice:previousDevice];
        [self.session beginConfiguration];
        [self.session removeInput:self.videoInput];
        if ([self.session canAddInput:input]) {
            [self.session addInput:input];
            self.videoInput = input;
            self.cameraPosition = desired;
            if (desired == AVCaptureDevicePositionFront) _flashMode = AVCaptureFlashModeOff;
        } else {
            [self.session addInput:self.videoInput];
        }
        [self.session commitConfiguration];
        if (self.cameraPosition == desired) {
            [self resetFocusAndExposureForDevice:device];
            self.maximumZoomFactor = [self maximumZoomFactorForActiveCapturePipeline];
            [self applyZoomFactorOnSessionQueue:1.0
                              requestGeneration:self.cameraSwitchZoomRequestGeneration];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.switchingCamera = NO;
                if ([self.delegate respondsToSelector:@selector(captureController:didChangeCameraPosition:)]) {
                    [self.delegate captureController:self didChangeCameraPosition:desired];
                }
            });
        } else {
            [self finishZoomRequestWithAppliedFactor:self.zoomFactor
                                       maximumFactor:self.maximumZoomFactor
                                    requestGeneration:self.cameraSwitchZoomRequestGeneration];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.switchingCamera = NO;
                [self updateState:self.state];
            });
        }
        self.cameraSwitchPending = NO;
}

- (void)startRollingRecording
{
    if (!self.isMotionCaptureEnabled || !self.wantsSessionRunning || ![self.session isRunning] ||
        self.pendingEvent || [self.movieFileOutput isRecording]) return;
    AVCaptureConnection *connection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
    if (connection == nil || ![connection isEnabled] || ![connection isActive]) {
        _motionCaptureEnabled = NO;
        NSLog(@"RetroLive: disabling motion capture because the movie output connection is unavailable");
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(captureController:didChangeMotionCaptureEnabled:)]) {
                [self.delegate captureController:self didChangeMotionCaptureEnabled:NO];
            }
        });
        return;
    }
    NSURL *url = [self uniqueRollingURLWithPrefix:@"segment"];
    if ([connection isVideoOrientationSupported]) connection.videoOrientation = self.rollingOrientation;
    if ([connection isVideoMirroringSupported]) connection.videoMirrored = self.cameraPosition == AVCaptureDevicePositionFront;
    self.rollingURL = url;
    self.rollingStartedAt = [NSDate date];
    [self.movieFileOutput startRecordingToOutputFileURL:url recordingDelegate:self];
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
didStartRecordingToOutputFileAtURL:(NSURL *)fileURL
      fromConnections:(NSArray *)connections
{
    (void)captureOutput;
    (void)connections;
    dispatch_async(_sessionQueue, ^{
        if ([fileURL isEqual:self.rollingURL]) self.rollingStartedAt = [NSDate date];
    });
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
      fromConnections:(NSArray *)connections
                error:(NSError *)error
{
    (void)captureOutput;
    (void)connections;
    dispatch_async(_sessionQueue, ^{
        if (self.pendingEvent && self.pendingMotionRequested) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:[outputFileURL path]]) {
                [self exportMotionFromRollingURL:outputFileURL startedAt:self.rollingStartedAt event:self.pendingEvent];
            } else {
                [self finishMotionWithError:error ?: [self errorWithCode:8 description:NSLocalizedString(@"capture.error.no_movie", nil)]];
            }
            return;
        }

        if (self.pendingEvent) {
            [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:NULL];
            self.rollingURL = nil;
            self.rollingStartedAt = nil;
            self.pendingMotionFinished = YES;
            [self completePendingCaptureWithMotionURL:nil];
            return;
        }

        [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:NULL];
        self.rollingURL = nil;
        self.rollingStartedAt = nil;
        if (self.cameraSwitchPending) [self performCameraSwitch];
        self.orientationRestartPending = NO;
        [self startRollingRecording];
    });
}

- (void)exportMotionFromRollingURL:(NSURL *)sourceURL startedAt:(NSDate *)startedAt event:(RLVCaptureEvent *)event
{
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:sourceURL options:nil];
    NSTimeInterval sourceDuration = CMTimeGetSeconds([asset duration]);
    NSTimeInterval shutterOffset = [event.shutterTimestamp timeIntervalSinceDate:startedAt];
    if (!isfinite(sourceDuration) || sourceDuration <= 0.0 || !isfinite(shutterOffset)) {
        [[NSFileManager defaultManager] removeItemAtURL:sourceURL error:NULL];
        [self finishMotionWithError:[self errorWithCode:9 description:NSLocalizedString(@"capture.error.invalid_timeline", nil)]];
        return;
    }
    shutterOffset = MAX(0.0, MIN(shutterOffset, sourceDuration));
    NSTimeInterval start = MAX(0.0, shutterOffset - RLVTargetPreRollSeconds);
    NSTimeInterval end = MIN(sourceDuration, shutterOffset + RLVTargetPostRollSeconds);
    if (end <= start) {
        [[NSFileManager defaultManager] removeItemAtURL:sourceURL error:NULL];
        [self finishMotionWithError:[self errorWithCode:10 description:NSLocalizedString(@"capture.error.empty_window", nil)]];
        return;
    }

    NSURL *outputURL = [self uniqueRollingURLWithPrefix:@"motion"];
    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetPassthrough];
    if (!exportSession) {
        [[NSFileManager defaultManager] removeItemAtURL:sourceURL error:NULL];
        [self finishMotionWithError:[self errorWithCode:11 description:NSLocalizedString(@"capture.error.trim_unsupported", nil)]];
        return;
    }
    exportSession.outputURL = outputURL;
    exportSession.outputFileType = AVFileTypeQuickTimeMovie;
    exportSession.timeRange = CMTimeRangeMake(CMTimeMakeWithSeconds(start, 600), CMTimeMakeWithSeconds(end - start, 600));
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(self->_sessionQueue, ^{
            [[NSFileManager defaultManager] removeItemAtURL:sourceURL error:NULL];
            if ([exportSession status] != AVAssetExportSessionStatusCompleted) {
                [[NSFileManager defaultManager] removeItemAtURL:outputURL error:NULL];
                [self finishMotionWithError:[exportSession error] ?: [self errorWithCode:11 description:NSLocalizedString(@"capture.error.trim_failed", nil)]];
                return;
            }
            [self populateMotionMetadataForEvent:event motionURL:outputURL];
            if (event.motionDurationSeconds <= 0.0 || event.motionWidth == 0 || event.motionHeight == 0 || event.motionFrameRate <= 0.0) {
                [[NSFileManager defaultManager] removeItemAtURL:outputURL error:NULL];
                [self finishMotionWithError:[self errorWithCode:12 description:NSLocalizedString(@"capture.error.invalid_metadata", nil)]];
                return;
            }
            event.stillImageTimeSeconds = shutterOffset - start;
            event.preRollSeconds = event.stillImageTimeSeconds;
            event.postRollSeconds = MAX(0.0, event.motionDurationSeconds - event.stillImageTimeSeconds);
            if (event.stillImageTimeSeconds < 0.0 || event.stillImageTimeSeconds >= event.motionDurationSeconds) {
                [[NSFileManager defaultManager] removeItemAtURL:outputURL error:NULL];
                [self finishMotionWithError:[self errorWithCode:13 description:NSLocalizedString(@"capture.error.frame_outside", nil)]];
                return;
            }
            [self completePendingCaptureWithMotionURL:outputURL];
        });
    }];
}

- (void)populateMotionMetadataForEvent:(RLVCaptureEvent *)event motionURL:(NSURL *)motionURL
{
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:motionURL options:nil];
    AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] lastObject];
    CGRect transformed = CGRectApplyAffineTransform(CGRectMake(0.0, 0.0, [videoTrack naturalSize].width, [videoTrack naturalSize].height), [videoTrack preferredTransform]);
    event.motionDurationSeconds = CMTimeGetSeconds([asset duration]);
    event.motionWidth = (NSUInteger)llround(fabs(transformed.size.width));
    event.motionHeight = (NSUInteger)llround(fabs(transformed.size.height));
    event.motionFrameRate = [videoTrack nominalFrameRate];
    event.motionHasAudio = [[asset tracksWithMediaType:AVMediaTypeAudio] count] > 0;
}

- (void)completePendingCaptureWithMotionURL:(NSURL *)motionURL
{
    if (!self.pendingEvent) return;
    self.pendingMotionFinished = YES;
    if (motionURL) self.pendingMotionURL = motionURL;
    if (!self.pendingPhotoData) return;

    RLVCaptureEvent *event = self.pendingEvent;
    NSData *photoData = self.pendingPhotoData;
    NSURL *completedMotionURL = self.pendingMotionURL;
    self.pendingEvent = nil;
    self.pendingPhotoData = nil;
    self.pendingMotionURL = nil;
    self.pendingMotionFinished = NO;
    self.pendingMotionRequested = NO;
    self.rollingURL = nil;
    self.rollingStartedAt = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.wantsSessionRunning) [self updateState:RLVCaptureStateRunning];
        if ([self.delegate respondsToSelector:@selector(captureController:didCapturePhotoData:motionURL:event:)]) {
            [self.delegate captureController:self didCapturePhotoData:photoData motionURL:completedMotionURL event:event];
        }
    });
    [self startRollingRecording];
}

- (void)finishMotionWithError:(NSError *)error
{
    if (error) {
        NSLog(@"RetroLive: saving capture without motion (%@/%ld): %@", [error domain],
              (long)[error code], [error localizedDescription]);
    }
    if (self.pendingEvent) {
        self.pendingEvent.stillImageTimeSeconds = 0.0;
        self.pendingEvent.preRollSeconds = 0.0;
        self.pendingEvent.postRollSeconds = 0.0;
        [self completePendingCaptureWithMotionURL:nil];
    }
}

- (void)failPendingCapture:(NSError *)error
{
    if (self.pendingMotionURL) [[NSFileManager defaultManager] removeItemAtURL:self.pendingMotionURL error:NULL];
    self.pendingEvent = nil;
    self.pendingPhotoData = nil;
    self.pendingMotionURL = nil;
    self.pendingMotionFinished = NO;
    self.pendingMotionRequested = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateState:RLVCaptureStateRunning];
        [self notifyError:error];
    });
    [self startRollingRecording];
}

- (NSURL *)rollingDirectoryURL
{
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"RetroLiveRolling"];
    NSURL *url = [NSURL fileURLWithPath:path isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:NULL];
    return url;
}

- (NSURL *)uniqueRollingURLWithPrefix:(NSString *)prefix
{
    NSString *filename = [NSString stringWithFormat:@"%@-%@.mov", prefix, [[NSUUID UUID] UUIDString]];
    return [[self rollingDirectoryURL] URLByAppendingPathComponent:filename];
}

- (void)removeAbandonedRollingFilesBeforeDate:(NSDate *)cutoffDate
{
    @autoreleasepool {
        NSURL *directory = [self rollingDirectoryURL];
        NSFileManager *manager = [NSFileManager defaultManager];
        NSArray *children = [manager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil options:0 error:NULL];
        for (NSURL *url in children) {
            NSDictionary *attributes = [manager attributesOfItemAtPath:[url path] error:NULL];
            NSDate *modifiedAt = [attributes objectForKey:NSFileModificationDate];
            if (modifiedAt && [modifiedAt compare:cutoffDate] == NSOrderedDescending) continue;
            [manager removeItemAtURL:url error:NULL];
        }
    }
}

- (void)setFlashMode:(AVCaptureFlashMode)flashMode
{
    AVCaptureDevice *device = self.videoInput.device;
    if (![device hasFlash] || ![device isFlashModeSupported:flashMode]) {
        return;
    }
    NSError *error = nil;
    if ([device lockForConfiguration:&error]) {
        device.flashMode = flashMode;
        [device unlockForConfiguration];
        _flashMode = flashMode;
    } else {
        NSLog(@"RetroLive: unable to change flash mode (%@/%ld): %@", [error domain],
              (long)[error code], [error localizedDescription]);
    }
}

- (NSUInteger)recordZoomTargetOnMainThread:(CGFloat)zoomFactor
{
    NSAssert([NSThread isMainThread], @"Zoom targets must be requested on the main thread");
    CGFloat clampedFactor = RLVClampZoomFactor(zoomFactor, self.maximumZoomFactor);
    self.requestedZoomFactor = clampedFactor;
    self.zoomRequestGeneration += 1;
    return self.zoomRequestGeneration;
}

- (NSUInteger)requestZoomFactor:(CGFloat)zoomFactor
{
    if (!isfinite(zoomFactor) || zoomFactor <= 0.0) return self.zoomRequestGeneration;
    NSUInteger requestGeneration = [self recordZoomTargetOnMainThread:zoomFactor];

    @synchronized (self) {
        self.pendingZoomFactor = self.requestedZoomFactor;
        self.pendingZoomRequestGeneration = requestGeneration;
        if (self.zoomUpdateScheduled) return requestGeneration;
        self.zoomUpdateScheduled = YES;
    }
    dispatch_async(_sessionQueue, ^{ [self drainPendingZoomUpdates]; });
    return requestGeneration;
}

- (void)drainPendingZoomUpdates
{
    while (YES) {
        CGFloat requestedFactor = 1.0;
        NSUInteger requestGeneration = 0;
        @synchronized (self) {
            requestedFactor = self.pendingZoomFactor;
            requestGeneration = self.pendingZoomRequestGeneration;
            self.pendingZoomFactor = 0.0;
            self.pendingZoomRequestGeneration = 0;
        }
        [self applyZoomFactorOnSessionQueue:requestedFactor requestGeneration:requestGeneration];

        @synchronized (self) {
            if (self.pendingZoomFactor > 0.0) continue;
            self.zoomUpdateScheduled = NO;
            break;
        }
    }
}

- (CGFloat)maximumZoomFactorForActiveCapturePipeline
{
    AVCaptureDevice *device = self.videoInput.device;
    if (!device) return 1.0;

    CGFloat maximum = 1.0;
    if ([device respondsToSelector:@selector(videoZoomFactor)]) {
        maximum = device.activeFormat.videoMaxZoomFactor;
    } else {
        NSArray *connections = @[
            self.previewLayer.connection ?: [NSNull null],
            [self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo] ?: [NSNull null],
            [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo] ?: [NSNull null]
        ];
        maximum = CGFLOAT_MAX;
        BOOL foundConnection = NO;
        for (id value in connections) {
            if (value == [NSNull null]) continue;
            AVCaptureConnection *connection = value;
            maximum = MIN(maximum, connection.videoMaxScaleAndCropFactor);
            foundConnection = YES;
        }
        if (!foundConnection || maximum == CGFLOAT_MAX) maximum = 1.0;
    }
    if (!isfinite(maximum)) maximum = 1.0;
    return MAX(1.0, MIN(maximum, RLVMaximumUserZoomFactor));
}

- (void)applyZoomFactorOnSessionQueue:(CGFloat)zoomFactor requestGeneration:(NSUInteger)requestGeneration
{
    CGFloat maximum = [self maximumZoomFactorForActiveCapturePipeline];
    CGFloat clampedFactor = RLVClampZoomFactor(zoomFactor, maximum);
    AVCaptureDevice *device = self.videoInput.device;
    if (!device) {
        [self finishZoomRequestWithAppliedFactor:self.zoomFactor maximumFactor:1.0
                               requestGeneration:requestGeneration];
        return;
    }

    if ([device respondsToSelector:@selector(videoZoomFactor)]) {
        NSError *error = nil;
        if (![device lockForConfiguration:&error]) {
            NSLog(@"RetroLive: unable to configure zoom: %@", [error localizedDescription]);
            [self finishZoomRequestWithAppliedFactor:self.zoomFactor maximumFactor:maximum
                                   requestGeneration:requestGeneration];
            return;
        }
        device.videoZoomFactor = clampedFactor;
        [device unlockForConfiguration];
    } else {
        NSArray *connections = @[
            self.previewLayer.connection ?: [NSNull null],
            [self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo] ?: [NSNull null],
            [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo] ?: [NSNull null]
        ];
        for (id value in connections) {
            if (value == [NSNull null]) continue;
            AVCaptureConnection *connection = value;
            connection.videoScaleAndCropFactor = MIN(clampedFactor, connection.videoMaxScaleAndCropFactor);
        }
    }
    self.maximumZoomFactor = maximum;
    self.zoomFactor = clampedFactor;
    [self finishZoomRequestWithAppliedFactor:clampedFactor maximumFactor:maximum
                           requestGeneration:requestGeneration];
}

- (void)finishZoomRequestWithAppliedFactor:(CGFloat)zoomFactor
                             maximumFactor:(CGFloat)maximumFactor
                          requestGeneration:(NSUInteger)requestGeneration
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!RLVZoomRequestGenerationIsCurrent(requestGeneration, self.zoomRequestGeneration)) return;
        self.requestedZoomFactor = zoomFactor;
        if ([self.delegate respondsToSelector:@selector(captureController:didChangeZoomFactor:maximumZoomFactor:requestGeneration:)]) {
            [self.delegate captureController:self didChangeZoomFactor:zoomFactor
                           maximumZoomFactor:maximumFactor
                            requestGeneration:requestGeneration];
        }
    });
}

- (void)focusAndExposeAtDevicePoint:(CGPoint)devicePoint
                         completion:(void (^)(RLVPointOfInterestResult result))completion
{
    if (!isfinite(devicePoint.x) || !isfinite(devicePoint.y) ||
        devicePoint.x < 0.0 || devicePoint.x > 1.0 ||
        devicePoint.y < 0.0 || devicePoint.y > 1.0) {
        [self finishPointOfInterestRequest:completion result:RLVPointOfInterestResultNone];
        return;
    }

    dispatch_async(_sessionQueue, ^{
        if (!self.wantsSessionRunning || ![self.session isRunning] ||
            self.cameraSwitchPending || self.pendingEvent) {
            [self finishPointOfInterestRequest:completion result:RLVPointOfInterestResultNone];
            return;
        }

        AVCaptureDevice *device = self.videoInput.device;
        BOOL canFocus = [device isFocusPointOfInterestSupported] &&
            [device isFocusModeSupported:AVCaptureFocusModeAutoFocus];
        BOOL canAutoExpose = [device isExposurePointOfInterestSupported] &&
            [device isExposureModeSupported:AVCaptureExposureModeAutoExpose];
        BOOL canContinuouslyExpose = [device isExposurePointOfInterestSupported] &&
            [device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure];
        if (!canFocus && !canAutoExpose && !canContinuouslyExpose) {
            [self finishPointOfInterestRequest:completion result:RLVPointOfInterestResultNone];
            return;
        }

        NSError *error = nil;
        if (![device lockForConfiguration:&error]) {
            NSLog(@"RetroLive: unable to configure focus/exposure: %@", [error localizedDescription]);
            [self finishPointOfInterestRequest:completion result:RLVPointOfInterestResultNone];
            return;
        }

        RLVPointOfInterestResult result = RLVPointOfInterestResultNone;
        if (canFocus) {
            device.focusPointOfInterest = devicePoint;
            device.focusMode = AVCaptureFocusModeAutoFocus;
            result |= RLVPointOfInterestResultFocus;
        }
        if (canAutoExpose || canContinuouslyExpose) {
            device.exposurePointOfInterest = devicePoint;
            device.exposureMode = canAutoExpose ? AVCaptureExposureModeAutoExpose
                                                : AVCaptureExposureModeContinuousAutoExposure;
            result |= RLVPointOfInterestResultExposure;
        }
        device.subjectAreaChangeMonitoringEnabled = YES;
        [device unlockForConfiguration];

        [[NSNotificationCenter defaultCenter] removeObserver:self
            name:AVCaptureDeviceSubjectAreaDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:)
            name:AVCaptureDeviceSubjectAreaDidChangeNotification object:device];
        [self finishPointOfInterestRequest:completion result:result];
    });
}

- (void)resetFocusAndExposureForDevice:(AVCaptureDevice *)device
{
    if (!device) return;

    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:AVCaptureDeviceSubjectAreaDidChangeNotification object:device];

    BOOL canFocus = [device isFocusPointOfInterestSupported] &&
        [device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus];
    BOOL canExpose = [device isExposurePointOfInterestSupported] &&
        [device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure];
    NSError *error = nil;
    if (![device lockForConfiguration:&error]) {
        if (error) NSLog(@"RetroLive: unable to reset focus/exposure: %@", [error localizedDescription]);
        return;
    }
    device.subjectAreaChangeMonitoringEnabled = NO;
    CGPoint centerPoint = CGPointMake(0.5, 0.5);
    if (canFocus) {
        device.focusPointOfInterest = centerPoint;
        device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
    }
    if (canExpose) {
        device.exposurePointOfInterest = centerPoint;
        device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
    }
    [device unlockForConfiguration];
}

- (void)subjectAreaDidChange:(NSNotification *)notification
{
    AVCaptureDevice *device = [notification object];
    dispatch_async(_sessionQueue, ^{
        if (device != self.videoInput.device) return;
        [self resetFocusAndExposureForDevice:device];
    });
}

- (void)finishPointOfInterestRequest:(void (^)(RLVPointOfInterestResult result))completion
                              result:(RLVPointOfInterestResult)result
{
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
}

- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position
{
    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if ([device position] == position) {
            return device;
        }
    }
    return nil;
}

- (void)sessionRuntimeError:(NSNotification *)notification
{
    NSError *error = [[notification userInfo] objectForKey:AVCaptureSessionErrorKey];
    NSLog(@"RetroLive: capture session runtime error (%@/%ld): %@", [error domain],
          (long)[error code], [error localizedDescription]);

    // Runtime errors are frequently transient while the app is moving between
    // foreground and background. They are not, by themselves, a failed user
    // operation. Keep them out of the modal error path and recover the session
    // when the camera still wants to be running.
    dispatch_async(_sessionQueue, ^{
        BOOL shouldRun = self.wantsSessionRunning;
        if (shouldRun && self.session && ![self.session isRunning]) {
            [self.session startRunning];
        }
        BOOL recovered = shouldRun && [self.session isRunning];
        if (recovered) [self startRollingRecording];
        RLVCaptureState recoveredState = self.pendingEvent ? RLVCaptureStateCapturing : RLVCaptureStateRunning;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (recovered) {
                [self updateState:recoveredState];
            } else if (shouldRun) {
                [self updateState:RLVCaptureStateFailed];
                [self notifyError:error ?: [self errorWithCode:5 description:NSLocalizedString(@"capture.error.session_failed", nil)]];
            } else {
                [self updateState:RLVCaptureStateInterrupted];
            }
        });
    });
}

- (void)updateState:(RLVCaptureState)state
{
    _state = state;
    if ([self.delegate respondsToSelector:@selector(captureController:didChangeState:)]) {
        [self.delegate captureController:self didChangeState:state];
    }
}

- (void)notifyError:(NSError *)error
{
    if (error && [self.delegate respondsToSelector:@selector(captureController:didFailWithError:)]) {
        [self.delegate captureController:self didFailWithError:error];
    }
}

- (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description
{
    return [NSError errorWithDomain:RLVCaptureControllerErrorDomain code:code
                           userInfo:[NSDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey]];
}

- (NSString *)stringForFlashMode:(AVCaptureFlashMode)mode
{
    if (mode == AVCaptureFlashModeOn) return @"on";
    if (mode == AVCaptureFlashModeAuto) return @"auto";
    return @"off";
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@synthesize delegate = _delegate;
@synthesize state = _state;
@synthesize session = _session;
@synthesize videoInput = _videoInput;
@synthesize stillImageOutput = _stillImageOutput;
@synthesize movieFileOutput = _movieFileOutput;
@synthesize audioInput = _audioInput;
@synthesize previewLayer = _previewLayer;
@synthesize cameraPosition = _cameraPosition;
@synthesize switchingCamera = _switchingCamera;
@synthesize flashMode = _flashMode;
@synthesize zoomFactor = _zoomFactor;
@synthesize requestedZoomFactor = _requestedZoomFactor;
@synthesize maximumZoomFactor = _maximumZoomFactor;
@synthesize rollingURL = _rollingURL;
@synthesize rollingStartedAt = _rollingStartedAt;
@synthesize pendingEvent = _pendingEvent;
@synthesize pendingPhotoData = _pendingPhotoData;
@synthesize pendingMotionURL = _pendingMotionURL;
@synthesize pendingMotionFinished = _pendingMotionFinished;
@synthesize rollingOrientation = _rollingOrientation;
@synthesize wantsSessionRunning = _wantsSessionRunning;
@synthesize cameraSwitchPending = _cameraSwitchPending;
@synthesize orientationRestartPending = _orientationRestartPending;
@synthesize motionCaptureEnabled = _motionCaptureEnabled;
@synthesize pendingMotionRequested = _pendingMotionRequested;
@synthesize pendingZoomFactor = _pendingZoomFactor;
@synthesize pendingZoomRequestGeneration = _pendingZoomRequestGeneration;
@synthesize zoomUpdateScheduled = _zoomUpdateScheduled;
@synthesize zoomRequestGeneration = _zoomRequestGeneration;
@synthesize cameraSwitchZoomRequestGeneration = _cameraSwitchZoomRequestGeneration;

@end
