#import "RLVBaseCameraViewController.h"
#import "RLVAssetStore.h"
#import "RLVDeviceCapabilities.h"
#import "RLVLibraryViewController.h"
#import "RLVLayout.h"
#import "RLVShutterButton.h"
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>

@interface RLVBaseCameraViewController ()
@property (nonatomic, strong) RLVCaptureController *captureController;
@property (nonatomic, strong) RLVCameraOrientationCoordinator *orientationCoordinator;
@property (nonatomic, strong, readwrite) RLVDeviceCapabilities *capabilities;
@property (nonatomic, strong) UIView *shutterOverlay;
@property (nonatomic, strong) UIView *liveCaptureIndicator;
@property (nonatomic, assign, getter=isViewVisible) BOOL viewVisible;
@property (nonatomic, copy) NSString *thumbnailRequestAssetId;
- (void)attachPreviewLayerIfNeeded;
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
    [self configureLiveCaptureIndicator];

    self.shutterOverlay = [[UIView alloc] initWithFrame:self.previewView.bounds];
    self.shutterOverlay.backgroundColor = [UIColor blackColor];
    self.shutterOverlay.alpha = 0.0;
    self.shutterOverlay.userInteractionEnabled = NO;
    [self.previewView addSubview:self.shutterOverlay];
    RLVPinViewToEdges(self.shutterOverlay, self.previewView);

    __weak RLVBaseCameraViewController *controller = self;
    [self.captureController prepareWithCompletion:^(NSError *error) {
        if (!error && controller.isViewVisible &&
            [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) {
            [controller attachPreviewLayerIfNeeded];
            [controller.captureController startRunning];
        }
    }];
    [self updateThumbnail];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.viewVisible = YES;
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [self.orientationCoordinator start];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];
    [self attachPreviewLayerIfNeeded];
    if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) {
        [self.captureController startRunning];
    }
    [self updateThumbnail];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    self.viewVisible = NO;
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
    if (!self.isViewVisible) return;
    if (self.captureController.state == RLVCaptureStateInterrupted) {
        [self.captureController resumeAfterInterruption];
    } else {
        [self.captureController startRunning];
    }
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    self.captureController.previewLayer.frame = self.previewView.bounds;
}

- (void)attachPreviewLayerIfNeeded
{
    AVCaptureVideoPreviewLayer *previewLayer = self.captureController.previewLayer;
    if (!previewLayer || previewLayer.superlayer == self.previewView.layer) return;
    [self.previewView.layer insertSublayer:previewLayer atIndex:0];
    [self.view setNeedsLayout];
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
    [self.cameraSwitchButton setTitle:nil forState:UIControlStateNormal];
    [self.cameraSwitchButton setImage:[UIImage imageNamed:@"InterfaceIcons/RLVSwitchCamera"]
                             forState:UIControlStateNormal];
    self.cameraSwitchButton.accessibilityLabel = NSLocalizedString(@"camera.switch", nil);
    self.cameraSwitchButton.hidden = !self.capabilities.supportsFrontCamera;
    self.flashButton.hidden = !self.capabilities.supportsFlash;
    [self updateFlashButton];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(previewTapped:)];
    [self.previewView addGestureRecognizer:tap];
}

- (void)configureLiveCaptureIndicator
{
    self.liveCaptureIndicator = [[UIView alloc] initWithFrame:CGRectZero];
    self.liveCaptureIndicator.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.68];
    self.liveCaptureIndicator.layer.cornerRadius = 14.0;
    self.liveCaptureIndicator.hidden = YES;
    self.liveCaptureIndicator.isAccessibilityElement = YES;
    self.liveCaptureIndicator.accessibilityLabel = NSLocalizedString(@"camera.live.capturing", nil);

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"InterfaceIcons/RLVLiveEffect"]];
    icon.contentMode = UIViewContentModeCenter;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.backgroundColor = [UIColor clearColor];
    label.text = @"LIVE";
    label.textColor = [UIColor colorWithRed:1.0 green:0.78 blue:0.0 alpha:1.0];
    label.font = [UIFont boldSystemFontOfSize:11.0];
    label.textAlignment = NSTextAlignmentLeft;
    label.isAccessibilityElement = NO;
    [self.liveCaptureIndicator addSubview:icon];
    [self.liveCaptureIndicator addSubview:label];
    [self.previewView addSubview:self.liveCaptureIndicator];

    RLVPrepareViewsForAutoLayout(@[self.liveCaptureIndicator, icon, label]);
    RLVAddVisualConstraints(self.liveCaptureIndicator, @{@"icon": icon, @"label": label},
        @[@"H:|-8-[icon(20)]-4-[label]-8-|", @"V:|[icon]|", @"V:|[label]|"]);
    RLVAddVisualConstraints(self.previewView, @{@"live": self.liveCaptureIndicator},
        @[@"H:[live(76)]", @"V:|-56-[live(28)]"]);
    RLVAlignViews(self.previewView, self.liveCaptureIndicator, NSLayoutAttributeCenterX,
        self.previewView, NSLayoutAttributeCenterX);

    NSMutableArray *rotating = [NSMutableArray arrayWithArray:self.rotatingControls ?: [NSArray array]];
    [rotating addObject:self.liveCaptureIndicator];
    self.rotatingControls = rotating;
}

- (void)showLiveCaptureIndicator
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideLiveCaptureIndicator) object:nil];
    self.liveCaptureIndicator.hidden = NO;
    self.liveCaptureIndicator.alpha = 1.0;
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,
        NSLocalizedString(@"camera.live.capturing", nil));
    [self performSelector:@selector(hideLiveCaptureIndicator) withObject:nil afterDelay:1.7];
}

- (void)hideLiveCaptureIndicator
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideLiveCaptureIndicator) object:nil];
    if (self.liveCaptureIndicator.hidden) return;
    [UIView animateWithDuration:0.18 animations:^{
        self.liveCaptureIndicator.alpha = 0.0;
    } completion:^(BOOL finished) {
        if (finished) self.liveCaptureIndicator.hidden = YES;
    }];
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
    [self updateFlashButton];
}

- (void)captureController:(RLVCaptureController *)controller didChangeCameraPosition:(AVCaptureDevicePosition)position
{
    (void)controller;
    self.flashButton.hidden = position != AVCaptureDevicePositionBack || !self.capabilities.supportsFlash;
    [self updateFlashButton];
}

- (void)updateFlashButton
{
    AVCaptureFlashMode mode = self.captureController.flashMode;
    NSString *imageName = @"InterfaceIcons/RLVFlashAuto";
    NSString *label = NSLocalizedString(@"camera.flash.auto", nil);
    if (mode == AVCaptureFlashModeOn) {
        imageName = @"InterfaceIcons/RLVFlashOn";
        label = NSLocalizedString(@"camera.flash.on", nil);
    } else if (mode == AVCaptureFlashModeOff) {
        imageName = @"InterfaceIcons/RLVFlashOff";
        label = NSLocalizedString(@"camera.flash.off", nil);
    }
    [self.flashButton setTitle:nil forState:UIControlStateNormal];
    [self.flashButton setImage:[UIImage imageNamed:imageName] forState:UIControlStateNormal];
    self.flashButton.accessibilityLabel = label;
}

- (void)previewTapped:(UITapGestureRecognizer *)recognizer
{
    CGPoint point = [recognizer locationInView:self.previewView];
    CGPoint devicePoint = [self.captureController.previewLayer captureDevicePointOfInterestForPoint:point];
    [self.captureController focusAtDevicePoint:devicePoint];
}

- (void)captureController:(RLVCaptureController *)controller didChangeState:(RLVCaptureState)state
{
    self.shutterButton.enabled = state == RLVCaptureStateRunning;
    self.shutterButton.capturing = state == RLVCaptureStateCapturing;
    if (state == RLVCaptureStateCapturing) {
        if (controller.isRecordingMotion) [self showLiveCaptureIndicator];
        self.shutterOverlay.alpha = 0.72;
        [UIView animateWithDuration:0.16 animations:^{ self.shutterOverlay.alpha = 0.0; }];
    } else {
        [self hideLiveCaptureIndicator];
    }
}

- (void)captureController:(RLVCaptureController *)controller didCapturePhotoData:(NSData *)photoData motionURL:(NSURL *)motionURL event:(RLVCaptureEvent *)event
{
    (void)controller;
    [[RLVAssetStore sharedStore] createAssetWithPhotoData:photoData motionURL:motionURL event:event capabilities:self.capabilities
                                              completion:^(RLVAsset *asset, NSError *error) {
        if (motionURL) [[NSFileManager defaultManager] removeItemAtURL:motionURL error:NULL];
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
    [self.captureController updateVideoOrientation:coordinator.videoOrientation];
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
    __weak RLVBaseCameraViewController *controller = self;
    [[RLVAssetStore sharedStore] loadAssetsWithCompletion:^(NSArray *assets, NSError *error) {
        (void)error;
        RLVAsset *asset = [assets count] > 0 ? [assets objectAtIndex:0] : nil;
        controller.thumbnailRequestAssetId = asset.assetId;
        if (!asset) {
            [controller.thumbnailButton setImage:nil forState:UIControlStateNormal];
            controller.thumbnailButton.enabled = NO;
            return;
        }
        NSString *assetId = [asset.assetId copy];
        NSURL *photoURL = asset.photoURL;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            UIImage *image = [controller thumbnailAtURL:photoURL maximumSize:120.0];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![controller.thumbnailRequestAssetId isEqualToString:assetId]) return;
                [controller.thumbnailButton setImage:image forState:UIControlStateNormal];
                controller.thumbnailButton.layer.contentsGravity = kCAGravityResizeAspectFill;
                controller.thumbnailButton.clipsToBounds = YES;
                controller.thumbnailButton.enabled = image != nil;
            });
        });
    }];
}

- (UIImage *)thumbnailAtURL:(NSURL *)url maximumSize:(CGFloat)size
{
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return nil;
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
        (id)kCFBooleanTrue, (id)kCGImageSourceCreateThumbnailFromImageAlways,
        [NSNumber numberWithFloat:size], (id)kCGImageSourceThumbnailMaxPixelSize,
        (id)kCFBooleanTrue, (id)kCGImageSourceCreateThumbnailWithTransform, nil];
    CGImageRef imageRef = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    UIImage *image = imageRef ? [UIImage imageWithCGImage:imageRef] : nil;
    if (imageRef) CGImageRelease(imageRef);
    CFRelease(source);
    return image;
}

- (void)showError:(NSError *)error
{
    if (!error) return;
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"camera.error.title", nil)
        message:[error localizedDescription] delegate:nil cancelButtonTitle:NSLocalizedString(@"common.ok", nil)
        otherButtonTitles:nil];
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
@synthesize liveCaptureIndicator = _liveCaptureIndicator;
@synthesize viewVisible = _viewVisible;
@synthesize thumbnailRequestAssetId = _thumbnailRequestAssetId;

@end
