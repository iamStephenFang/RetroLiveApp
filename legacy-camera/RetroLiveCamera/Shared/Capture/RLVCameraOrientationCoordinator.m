#import "RLVCameraOrientationCoordinator.h"

@interface RLVCameraOrientationCoordinator ()
@property (nonatomic, assign, readwrite) RLVCaptureOrientation captureOrientation;
@property (nonatomic, assign, readwrite) AVCaptureVideoOrientation videoOrientation;
@property (nonatomic, assign, readwrite) CGAffineTransform controlTransform;
@end

@implementation RLVCameraOrientationCoordinator

- (id)init
{
    self = [super init];
    if (self) {
        _captureOrientation = RLVCaptureOrientationPortrait;
        _videoOrientation = AVCaptureVideoOrientationPortrait;
        _controlTransform = CGAffineTransformIdentity;
    }
    return self;
}

- (void)start
{
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceOrientationChanged:)
                                                 name:UIDeviceOrientationDidChangeNotification object:nil];
    [self updateForDeviceOrientation:[[UIDevice currentDevice] orientation]];
}

- (void)stop
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
}

- (void)dealloc
{
    [self stop];
}

- (void)deviceOrientationChanged:(NSNotification *)notification
{
    (void)notification;
    [self updateForDeviceOrientation:[[UIDevice currentDevice] orientation]];
}

- (void)updateForDeviceOrientation:(UIDeviceOrientation)orientation
{
    CGAffineTransform transform = self.controlTransform;
    switch (orientation) {
        case UIDeviceOrientationPortrait:
            self.captureOrientation = RLVCaptureOrientationPortrait;
            self.videoOrientation = AVCaptureVideoOrientationPortrait;
            transform = CGAffineTransformIdentity;
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            self.captureOrientation = RLVCaptureOrientationPortraitUpsideDown;
            self.videoOrientation = AVCaptureVideoOrientationPortraitUpsideDown;
            transform = CGAffineTransformMakeRotation((CGFloat)M_PI);
            break;
        case UIDeviceOrientationLandscapeLeft:
            self.captureOrientation = RLVCaptureOrientationLandscapeLeft;
            self.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
            transform = CGAffineTransformMakeRotation((CGFloat)M_PI_2);
            break;
        case UIDeviceOrientationLandscapeRight:
            self.captureOrientation = RLVCaptureOrientationLandscapeRight;
            self.videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
            transform = CGAffineTransformMakeRotation((CGFloat)-M_PI_2);
            break;
        default:
            return;
    }
    self.controlTransform = transform;
    if ([self.delegate respondsToSelector:@selector(orientationCoordinator:didUpdateControlTransform:)]) {
        [self.delegate orientationCoordinator:self didUpdateControlTransform:transform];
    }
}

@synthesize delegate = _delegate;
@synthesize captureOrientation = _captureOrientation;
@synthesize videoOrientation = _videoOrientation;
@synthesize controlTransform = _controlTransform;

@end
