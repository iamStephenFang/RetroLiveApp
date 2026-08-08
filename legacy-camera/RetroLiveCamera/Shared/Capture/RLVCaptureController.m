#import "RLVCaptureController.h"

NSString * const RLVCaptureControllerErrorDomain = @"com.retrolive.capture";

@interface RLVCaptureController () {
    dispatch_queue_t _sessionQueue;
}
@property (nonatomic, assign, readwrite) RLVCaptureState state;
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDeviceInput *videoInput;
@property (nonatomic, strong) AVCaptureStillImageOutput *stillImageOutput;
@property (nonatomic, strong, readwrite) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, assign, readwrite) AVCaptureDevicePosition cameraPosition;
@property (nonatomic, assign, readwrite) AVCaptureFlashMode flashMode;
@end

@implementation RLVCaptureController

- (id)init
{
    self = [super init];
    if (self) {
        _state = RLVCaptureStateIdle;
        _cameraPosition = AVCaptureDevicePositionBack;
        _flashMode = AVCaptureFlashModeAuto;
        _sessionQueue = dispatch_queue_create("com.retrolive.capture.session", DISPATCH_QUEUE_SERIAL);
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
        if ([session canSetSessionPreset:AVCaptureSessionPresetPhoto]) {
            session.sessionPreset = AVCaptureSessionPresetPhoto;
        }

        AVCaptureDevice *device = [self cameraWithPosition:AVCaptureDevicePositionBack];
        AVCaptureDeviceInput *input = device ? [AVCaptureDeviceInput deviceInputWithDevice:device error:&error] : nil;
        AVCaptureStillImageOutput *output = [[AVCaptureStillImageOutput alloc] init];
        output.outputSettings = [NSDictionary dictionaryWithObject:AVVideoCodecJPEG forKey:AVVideoCodecKey];

        [session beginConfiguration];
        if (input && [session canAddInput:input]) {
            [session addInput:input];
        } else if (error == nil) {
            error = [self errorWithCode:1 description:@"Rear camera is unavailable."];
        }
        if (error == nil && [session canAddOutput:output]) {
            [session addOutput:output];
        } else if (error == nil) {
            error = [self errorWithCode:2 description:@"Still image output is unavailable."];
        }
        [session commitConfiguration];

        if (error == nil) {
            self.session = session;
            self.videoInput = input;
            self.stillImageOutput = output;
            self.cameraPosition = [device position];
            self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:session];
            self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
            if ([device hasFlash] && [device isFlashModeSupported:AVCaptureFlashModeAuto] && [device lockForConfiguration:NULL]) {
                device.flashMode = AVCaptureFlashModeAuto;
                [device unlockForConfiguration];
            }
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionRuntimeError:)
                                                         name:AVCaptureSessionRuntimeErrorNotification object:session];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [self updateState:RLVCaptureStateFailed];
                [self notifyError:error];
            } else {
                [self updateState:RLVCaptureStateIdle];
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
        if (self.session && ![self.session isRunning]) {
            [self.session startRunning];
        }
        if ([self.session isRunning]) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self updateState:RLVCaptureStateRunning]; });
        }
    });
}

- (void)stopRunning
{
    dispatch_async(_sessionQueue, ^{
        if ([self.session isRunning]) {
            [self.session stopRunning];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateState:RLVCaptureStateIdle]; });
    });
}

- (void)interrupt
{
    dispatch_async(_sessionQueue, ^{
        if ([self.session isRunning]) [self.session stopRunning];
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateState:RLVCaptureStateInterrupted]; });
    });
}

- (void)resumeAfterInterruption
{
    if (self.state != RLVCaptureStateInterrupted) return;
    [self startRunning];
}

- (void)capturePhotoWithOrientation:(RLVCaptureOrientation)orientation
                   videoOrientation:(AVCaptureVideoOrientation)videoOrientation
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
    [self updateState:RLVCaptureStateCapturing];

    dispatch_async(_sessionQueue, ^{
        AVCaptureConnection *connection = [self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo];
        if (connection == nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateState:RLVCaptureStateRunning];
                [self notifyError:[self errorWithCode:6 description:@"Still image connection is unavailable."]];
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
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateState:RLVCaptureStateRunning];
                if (data) {
                    if ([self.delegate respondsToSelector:@selector(captureController:didCapturePhotoData:event:)]) {
                        [self.delegate captureController:self didCapturePhotoData:data event:event];
                    }
                } else {
                    [self notifyError:error ?: [self errorWithCode:3 description:@"The camera returned no JPEG data."]];
                }
            });
        }];
    });
}

- (void)switchCamera
{
    if (self.state != RLVCaptureStateRunning) {
        return;
    }
    dispatch_async(_sessionQueue, ^{
        AVCaptureDevicePosition desired = self.cameraPosition == AVCaptureDevicePositionBack
            ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
        AVCaptureDevice *device = [self cameraWithPosition:desired];
        NSError *error = nil;
        AVCaptureDeviceInput *input = device ? [AVCaptureDeviceInput deviceInputWithDevice:device error:&error] : nil;
        if (!input) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self notifyError:error ?: [self errorWithCode:4 description:@"Camera is unavailable."]]; });
            return;
        }
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
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(captureController:didChangeCameraPosition:)]) {
                    [self.delegate captureController:self didChangeCameraPosition:desired];
                }
            });
        }
    });
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
        [self notifyError:error];
    }
}

- (void)focusAtDevicePoint:(CGPoint)devicePoint
{
    AVCaptureDevice *device = self.videoInput.device;
    NSError *error = nil;
    if ([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:AVCaptureFocusModeAutoFocus] &&
        [device lockForConfiguration:&error]) {
        device.focusPointOfInterest = devicePoint;
        device.focusMode = AVCaptureFocusModeAutoFocus;
        if ([device isExposurePointOfInterestSupported] && [device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
            device.exposurePointOfInterest = devicePoint;
            device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
        }
        [device unlockForConfiguration];
    } else if (error) {
        [self notifyError:error];
    }
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
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateState:RLVCaptureStateFailed];
        [self notifyError:error ?: [self errorWithCode:5 description:@"Capture session failed."]];
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
@synthesize previewLayer = _previewLayer;
@synthesize cameraPosition = _cameraPosition;
@synthesize flashMode = _flashMode;

@end
