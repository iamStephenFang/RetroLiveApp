#import "RLVBaseCameraViewController.h"
#import "RLVAssetStore.h"
#import "RLVDeviceCapabilities.h"
#import "RLVLibraryViewController.h"
#import "RLVShutterButton.h"
#import <QuartzCore/QuartzCore.h>

@interface RLVBaseCameraViewController ()
@property (nonatomic, strong) RLVCaptureController *captureController;
@property (nonatomic, strong) RLVCameraOrientationCoordinator *orientationCoordinator;
@property (nonatomic, strong, readwrite) RLVDeviceCapabilities *capabilities;
@property (nonatomic, strong) UIView *shutterOverlay;
@end

@implementation RLVBaseCameraViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.capabilities = [RLVDeviceCapabilities currentCapabilities];
    self.captureController = [[RLVCaptureController alloc] init];
    self.captureController.delegate = self;
    self.orientationCoordinator = [[RLVCameraOrientationCoordinator alloc] init];
    self.orientationCoordinator.delegate = self;
    [self configureCameraActions];

    self.shutterOverlay = [[UIView alloc] initWithFrame:self.previewView.bounds];
    self.shutterOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.shutterOverlay.backgroundColor = [UIColor blackColor];
    self.shutterOverlay.alpha = 0.0;
    self.shutterOverlay.userInteractionEnabled = NO;
    [self.previewView addSubview:self.shutterOverlay];

    __block RLVBaseCameraViewController *controller = self;
    [self.captureController prepareWithCompletion:^(NSError *error) {
        if (!error) {
            [controller.previewView.layer insertSublayer:controller.captureController.previewLayer atIndex:0];
            [controller.view setNeedsLayout];
            [controller.captureController startRunning];
        }
    }];
    [self updateThumbnail];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [self.orientationCoordinator start];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];
    [self.captureController startRunning];
    [self updateThumbnail];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.orientationCoordinator stop];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    [self.captureController stopRunning];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    (void)notification;
    [self.captureController interrupt];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    (void)notification;
    [self.captureController resumeAfterInterruption];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    self.captureController.previewLayer.frame = self.previewView.bounds;
    self.shutterOverlay.frame = self.previewView.bounds;
}

- (BOOL)shouldAutorotate
{
    return NO;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
    return UIInterfaceOrientationPortrait;
}

- (void)configureCameraActions
{
    [self.shutterButton addTarget:self action:@selector(shutterPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.thumbnailButton addTarget:self action:@selector(thumbnailPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.cameraSwitchButton addTarget:self action:@selector(cameraSwitchPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.flashButton addTarget:self action:@selector(flashPressed:) forControlEvents:UIControlEventTouchUpInside];
    self.cameraSwitchButton.hidden = !self.capabilities.supportsFrontCamera;
    self.flashButton.hidden = !self.capabilities.supportsFlash;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(previewTapped:)];
    [self.previewView addGestureRecognizer:tap];
}

- (void)shutterPressed:(id)sender
{
    (void)sender;
    [self.captureController capturePhotoWithOrientation:self.orientationCoordinator.captureOrientation
                                      videoOrientation:self.orientationCoordinator.videoOrientation];
}

- (void)thumbnailPressed:(id)sender
{
    (void)sender;
    RLVLibraryViewController *library = [[RLVLibraryViewController alloc] init];
    [self.navigationController pushViewController:library animated:YES];
}

- (void)cameraSwitchPressed:(id)sender
{
    (void)sender;
    [self.captureController switchCamera];
}

- (void)flashPressed:(id)sender
{
    (void)sender;
    AVCaptureFlashMode next = AVCaptureFlashModeAuto;
    if (self.captureController.flashMode == AVCaptureFlashModeAuto) next = AVCaptureFlashModeOn;
    else if (self.captureController.flashMode == AVCaptureFlashModeOn) next = AVCaptureFlashModeOff;
    [self.captureController setFlashMode:next];
    NSString *title = next == AVCaptureFlashModeAuto ? @"Flash Auto" : (next == AVCaptureFlashModeOn ? @"Flash On" : @"Flash Off");
    [self.flashButton setTitle:title forState:UIControlStateNormal];
}

- (void)captureController:(RLVCaptureController *)controller didChangeCameraPosition:(AVCaptureDevicePosition)position
{
    (void)controller;
    self.flashButton.hidden = position != AVCaptureDevicePositionBack || !self.capabilities.supportsFlash;
    NSString *title = controller.flashMode == AVCaptureFlashModeAuto ? @"Flash Auto" :
        (controller.flashMode == AVCaptureFlashModeOn ? @"Flash On" : @"Flash Off");
    [self.flashButton setTitle:title forState:UIControlStateNormal];
}

- (void)previewTapped:(UITapGestureRecognizer *)recognizer
{
    CGPoint point = [recognizer locationInView:self.previewView];
    CGPoint devicePoint = [self.captureController.previewLayer captureDevicePointOfInterestForPoint:point];
    [self.captureController focusAtDevicePoint:devicePoint];
}

- (void)captureController:(RLVCaptureController *)controller didChangeState:(RLVCaptureState)state
{
    (void)controller;
    self.shutterButton.enabled = state == RLVCaptureStateRunning;
    self.shutterButton.capturing = state == RLVCaptureStateCapturing;
    if (state == RLVCaptureStateCapturing) {
        self.shutterOverlay.alpha = 0.72;
        [UIView animateWithDuration:0.16 animations:^{ self.shutterOverlay.alpha = 0.0; }];
    }
}

- (void)captureController:(RLVCaptureController *)controller didCapturePhotoData:(NSData *)photoData event:(RLVCaptureEvent *)event
{
    (void)controller;
    [[RLVAssetStore sharedStore] createAssetWithPhotoData:photoData event:event capabilities:self.capabilities
                                              completion:^(RLVAsset *asset, NSError *error) {
        if (asset) [self updateThumbnail];
        if (error) [self showError:error];
    }];
}

- (void)captureController:(RLVCaptureController *)controller didFailWithError:(NSError *)error
{
    (void)controller;
    [self showError:error];
}

- (void)orientationCoordinator:(RLVCameraOrientationCoordinator *)coordinator didUpdateControlTransform:(CGAffineTransform)transform
{
    AVCaptureConnection *previewConnection = self.captureController.previewLayer.connection;
    if ([previewConnection isVideoOrientationSupported]) {
        previewConnection.videoOrientation = coordinator.videoOrientation;
    }
    [UIView animateWithDuration:0.22 animations:^{
        for (UIView *control in self.rotatingControls) control.transform = transform;
    }];
}

- (void)updateThumbnail
{
    NSArray *assets = [[RLVAssetStore sharedStore] loadAssets:NULL];
    RLVAsset *asset = [assets count] > 0 ? [assets objectAtIndex:0] : nil;
    UIImage *image = asset ? [UIImage imageWithContentsOfFile:[asset.photoURL path]] : nil;
    [self.thumbnailButton setImage:image forState:UIControlStateNormal];
    self.thumbnailButton.layer.contentsGravity = kCAGravityResizeAspectFill;
    self.thumbnailButton.clipsToBounds = YES;
    self.thumbnailButton.enabled = asset != nil;
}

- (void)showError:(NSError *)error
{
    if (!error) return;
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Camera Error" message:[error localizedDescription]
                                                   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [alert show];
}

@synthesize previewView = _previewView;
@synthesize topChromeView = _topChromeView;
@synthesize bottomChromeView = _bottomChromeView;
@synthesize shutterButton = _shutterButton;
@synthesize thumbnailButton = _thumbnailButton;
@synthesize flashButton = _flashButton;
@synthesize cameraSwitchButton = _cameraSwitchButton;
@synthesize rotatingControls = _rotatingControls;
@synthesize capabilities = _capabilities;
@synthesize captureController = _captureController;
@synthesize orientationCoordinator = _orientationCoordinator;
@synthesize shutterOverlay = _shutterOverlay;

@end
