#import "RLVBaseCameraViewController.h"
#import "RLVAssetStore.h"
#import "RLVDeviceCapabilities.h"
#import "RLVLibraryTabBarController.h"
#import "RLVLayout.h"
#import "RLVShutterButton.h"
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

static NSString * const RLVAspectRatioDefaultsKey = @"RLVCameraAspectRatio";

@implementation RLVFocusPreviewView

- (BOOL)accessibilityActivate
{
    if (!self.focusDelegate) return NO;
    return [self.focusDelegate focusPreviewViewDidRequestCenterFocus:self];
}

@synthesize focusDelegate = _focusDelegate;

@end

@interface RLVBaseCameraViewController ()
@property (nonatomic, strong) RLVCaptureController *captureController;
@property (nonatomic, strong) RLVCameraOrientationCoordinator *orientationCoordinator;
@property (nonatomic, strong, readwrite) RLVDeviceCapabilities *capabilities;
@property (nonatomic, strong) UIView *shutterOverlay;
@property (nonatomic, strong) UIView *liveCaptureIndicator;
@property (nonatomic, strong) UIView *focusOverlayView;
@property (nonatomic, strong) UIView *focusReticleView;
@property (nonatomic, assign, getter=isViewVisible) BOOL viewVisible;
@property (nonatomic, assign) NSUInteger focusRequestGeneration;
@property (nonatomic, copy) NSString *thumbnailRequestAssetId;
@property (nonatomic, assign) NSUInteger thumbnailRequestGeneration;
@property (nonatomic, copy) NSString *activeAspectRatio;
@property (nonatomic, assign, getter=isSavingAsset) BOOL savingAsset;
@property (nonatomic, strong) UITapGestureRecognizer *focusTapGestureRecognizer;
- (void)attachPreviewLayerIfNeeded;
- (void)updatePreviewFrame;
- (void)configureCameraActions;
- (BOOL)isCameraInteractionAvailable;
- (void)updateCameraControls;
- (void)configureFocusReticle;
- (void)requestFocusAtPreviewPoint:(CGPoint)point;
- (void)showFocusReticleAtPreviewPoint:(CGPoint)point;
- (void)hideFocusReticle;
- (void)updateThumbnail;
- (void)loadThumbnailForAsset:(RLVAsset *)asset generation:(NSUInteger)generation retry:(BOOL)retry;
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
    NSString *savedAspectRatio = [[NSUserDefaults standardUserDefaults] stringForKey:RLVAspectRatioDefaultsKey];
    if (![@[@"4:3", @"1:1", @"16:9"] containsObject:savedAspectRatio]) savedAspectRatio = @"4:3";
    self.activeAspectRatio = savedAspectRatio;
    [self configureCameraActions];
    [self updateCameraControls];

    self.shutterOverlay = [[UIView alloc] initWithFrame:self.previewView.bounds];
    self.shutterOverlay.backgroundColor = [UIColor blackColor];
    self.shutterOverlay.alpha = 0.0;
    self.shutterOverlay.userInteractionEnabled = NO;
    [self.previewView addSubview:self.shutterOverlay];
    RLVPinViewToEdges(self.shutterOverlay, self.previewView);
    [self configureFocusReticle];
    [self configureLiveCaptureIndicator];

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
    self.focusRequestGeneration += 1;
    [self hideFocusReticle];
    [self.captureController stopRunning];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    (void)notification;
    self.focusRequestGeneration += 1;
    [self hideFocusReticle];
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
    [self updatePreviewFrame];
}

- (void)updatePreviewFrame
{
    CGRect bounds = self.previewView.bounds;
    if (CGRectIsEmpty(bounds)) return;
    CGFloat landscapeRatio = 4.0 / 3.0;
    if ([self.activeAspectRatio isEqualToString:@"1:1"]) landscapeRatio = 1.0;
    else if ([self.activeAspectRatio isEqualToString:@"16:9"]) landscapeRatio = 16.0 / 9.0;
    CGFloat portraitRatio = 1.0 / landscapeRatio;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = width / portraitRatio;
    if (height > CGRectGetHeight(bounds)) {
        height = CGRectGetHeight(bounds);
        width = height * portraitRatio;
    }
    CGRect previewFrame = CGRectIntegral(CGRectMake(
        CGRectGetMidX(bounds) - width * 0.5, CGRectGetMidY(bounds) - height * 0.5, width, height));
    self.captureController.previewLayer.frame = previewFrame;
    self.focusOverlayView.frame = previewFrame;
}

- (void)attachPreviewLayerIfNeeded
{
    AVCaptureVideoPreviewLayer *previewLayer = self.captureController.previewLayer;
    if (!previewLayer || previewLayer.superlayer == self.previewView.layer) return;
    [self.previewView.layer insertSublayer:previewLayer atIndex:0];
    AVCaptureConnection *previewConnection = previewLayer.connection;
    if ([previewConnection isVideoOrientationSupported]) {
        // The camera UI stays portrait-locked. Device orientation belongs to
        // captured media and rotating controls, not to the preview surface.
        previewConnection.videoOrientation = AVCaptureVideoOrientationPortrait;
    }
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
    [self.livePhotoButton addTarget:self action:@selector(livePhotoTogglePressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.cameraSwitchButton addTarget:self action:@selector(cameraSwitchPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.flashButton addTarget:self action:@selector(flashPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.aspectRatioButton addTarget:self action:@selector(aspectRatioPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.cameraSwitchButton setTitle:nil forState:UIControlStateNormal];
    [self.cameraSwitchButton setImage:[UIImage imageNamed:@"InterfaceIcons/RLVSwitchCamera"]
                             forState:UIControlStateNormal];
    self.cameraSwitchButton.accessibilityLabel = NSLocalizedString(@"camera.switch", nil);
    self.cameraSwitchButton.hidden = !self.capabilities.supportsFrontCamera;
    self.flashButton.hidden = !self.capabilities.supportsFlash;
    [self updateFlashButton];
    [self updateLivePhotoButton];
    [self updateAspectRatioButton];
    self.focusTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(previewTapped:)];
    [self.previewView addGestureRecognizer:self.focusTapGestureRecognizer];
    self.previewView.isAccessibilityElement = YES;
    self.previewView.accessibilityTraits = UIAccessibilityTraitButton;
    self.previewView.accessibilityLabel = NSLocalizedString(@"camera.preview", nil);
    self.previewView.accessibilityHint = NSLocalizedString(@"camera.focus.hint", nil);
    if ([self.previewView isKindOfClass:[RLVFocusPreviewView class]]) {
        [(RLVFocusPreviewView *)self.previewView setFocusDelegate:self];
    }
}

- (BOOL)isCameraInteractionAvailable
{
    return self.captureController.state == RLVCaptureStateRunning && !self.isSavingAsset;
}

- (void)updateCameraControls
{
    BOOL available = [self isCameraInteractionAvailable];
    self.shutterButton.enabled = available;
    self.thumbnailButton.enabled = available &&
        [self.thumbnailButton imageForState:UIControlStateNormal] != nil;
    self.livePhotoButton.enabled = available;
    self.cameraSwitchButton.enabled = available;
    self.flashButton.enabled = available;
    self.aspectRatioButton.enabled = available;
    self.focusTapGestureRecognizer.enabled = available;
    self.previewView.accessibilityTraits = UIAccessibilityTraitButton |
        (available ? 0 : UIAccessibilityTraitNotEnabled);
}

- (void)configureFocusReticle
{
    self.focusOverlayView = [[UIView alloc] initWithFrame:self.captureController.previewLayer.frame];
    self.focusOverlayView.backgroundColor = [UIColor clearColor];
    self.focusOverlayView.clipsToBounds = YES;
    self.focusOverlayView.userInteractionEnabled = NO;
    self.focusOverlayView.isAccessibilityElement = NO;

    self.focusReticleView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 72.0, 72.0)];
    self.focusReticleView.backgroundColor = [UIColor clearColor];
    self.focusReticleView.layer.borderColor = [UIColor colorWithRed:1.0 green:0.80 blue:0.0 alpha:1.0].CGColor;
    self.focusReticleView.layer.borderWidth = 1.0;
    self.focusReticleView.layer.cornerRadius = 1.0;
    self.focusReticleView.userInteractionEnabled = NO;
    self.focusReticleView.hidden = YES;
    [self.focusOverlayView addSubview:self.focusReticleView];
    [self.previewView insertSubview:self.focusOverlayView belowSubview:self.shutterOverlay];
}

- (void)configureLiveCaptureIndicator
{
    self.liveCaptureIndicator = [[UIView alloc] initWithFrame:CGRectZero];
    self.liveCaptureIndicator.backgroundColor = [UIColor colorWithRed:1.0 green:0.80 blue:0.0 alpha:0.96];
    self.liveCaptureIndicator.layer.cornerRadius = 14.0;
    self.liveCaptureIndicator.hidden = YES;
    self.liveCaptureIndicator.isAccessibilityElement = YES;
    self.liveCaptureIndicator.accessibilityLabel = NSLocalizedString(@"camera.live.capturing", nil);

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.backgroundColor = [UIColor clearColor];
    label.text = NSLocalizedString(@"asset.live.badge.live", nil);
    label.textColor = [UIColor colorWithWhite:0.10 alpha:1.0];
    label.font = [UIFont boldSystemFontOfSize:13.0];
    label.textAlignment = NSTextAlignmentCenter;
    label.isAccessibilityElement = NO;
    [self.liveCaptureIndicator addSubview:label];
    [self.previewView addSubview:self.liveCaptureIndicator];

    RLVPrepareViewsForAutoLayout(@[self.liveCaptureIndicator, label]);
    RLVAddVisualConstraints(self.liveCaptureIndicator, @{@"label": label},
        @[@"H:|-6-[label]-6-|", @"V:|[label]|"]);
    CGFloat indicatorWidth = ceil(RLVTextSizeWithFont(label.text, label.font).width + 12.0);
    RLVAddVisualConstraints(self.previewView, @{@"live": self.liveCaptureIndicator},
        @[[NSString stringWithFormat:@"H:[live(%.0f)]", indicatorWidth], @"V:|-12-[live(28)]"]);
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
    if (![self isCameraInteractionAvailable]) return;
    [self.captureController capturePhotoWithOrientation:self.orientationCoordinator.captureOrientation
                                      videoOrientation:self.orientationCoordinator.videoOrientation
                                            aspectRatio:self.activeAspectRatio];
}

- (void)aspectRatioPressed:(id)sender
{
    (void)sender;
    if (![self isCameraInteractionAvailable]) return;
    NSArray *aspectRatios = @[@"4:3", @"1:1", @"16:9"];
    NSUInteger currentIndex = [aspectRatios indexOfObject:self.activeAspectRatio];
    NSUInteger nextIndex = currentIndex == NSNotFound ? 0 : (currentIndex + 1) % [aspectRatios count];
    self.activeAspectRatio = [aspectRatios objectAtIndex:nextIndex];
    [[NSUserDefaults standardUserDefaults] setObject:self.activeAspectRatio forKey:RLVAspectRatioDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    self.focusRequestGeneration += 1;
    [self hideFocusReticle];
    [self updateAspectRatioButton];
    [self updatePreviewFrame];
}

- (void)updateAspectRatioButton
{
    [self.aspectRatioButton setTitle:self.activeAspectRatio forState:UIControlStateNormal];
    self.aspectRatioButton.accessibilityLabel = [NSString stringWithFormat:
        NSLocalizedString(@"camera.aspect.value", nil), self.activeAspectRatio];
}

- (void)thumbnailPressed:(id)sender
{
    (void)sender;
    if (![self isCameraInteractionAvailable]) return;
    self.thumbnailButton.enabled = NO;
    __weak RLVBaseCameraViewController *controller = self;
    [[RLVAssetStore sharedStore] loadAssetsWithCompletion:^(NSArray *assets, NSError *error) {
        (void)error;
        if (!controller) return;
        [controller updateCameraControls];
        if ([assets count] == 0 || ![controller isCameraInteractionAvailable] ||
            controller.presentedViewController || !controller.view.window) return;
        RLVLibraryTabBarController *library = [[RLVLibraryTabBarController alloc]
            initWithAssets:assets selectedIndex:0];
        library.modalPresentationStyle = UIModalPresentationFullScreen;
        [controller presentViewController:library animated:YES completion:nil];
    }];
}

- (void)livePhotoTogglePressed:(id)sender
{
    (void)sender;
    if (![self isCameraInteractionAvailable]) return;
    self.captureController.motionCaptureEnabled = !self.captureController.isMotionCaptureEnabled;
    [self updateLivePhotoButton];
}

- (void)updateLivePhotoButton
{
    BOOL active = self.captureController.isMotionCaptureEnabled;
    UIColor *color = active ? [UIColor colorWithRed:1.0 green:0.78 blue:0.0 alpha:1.0]
                            : [UIColor colorWithWhite:0.72 alpha:1.0];
    UIImage *image = RLVTintedInterfaceImage([UIImage imageNamed:@"InterfaceIcons/RLVLiveEffect"], color);
    [self.livePhotoButton setTitle:nil forState:UIControlStateNormal];
    [self.livePhotoButton setBackgroundImage:nil forState:UIControlStateNormal];
    [self.livePhotoButton setImage:image forState:UIControlStateNormal];
    self.livePhotoButton.contentEdgeInsets = UIEdgeInsetsZero;
    self.livePhotoButton.alpha = active ? 1.0 : 0.72;
    self.livePhotoButton.accessibilityLabel = NSLocalizedString(@"camera.live.toggle", nil);
    self.livePhotoButton.accessibilityValue = active ? NSLocalizedString(@"camera.live.on", nil)
                                                     : NSLocalizedString(@"camera.live.off", nil);
}

- (void)cameraSwitchPressed:(id)sender
{
    (void)sender;
    if (![self isCameraInteractionAvailable]) return;
    self.focusRequestGeneration += 1;
    [self hideFocusReticle];
    [self.captureController switchCamera];
}

- (void)flashPressed:(id)sender
{
    (void)sender;
    if (![self isCameraInteractionAvailable]) return;
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
    [self requestFocusAtPreviewPoint:[recognizer locationInView:self.previewView]];
}

- (BOOL)focusPreviewViewDidRequestCenterFocus:(RLVFocusPreviewView *)previewView
{
    (void)previewView;
    if (![self isCameraInteractionAvailable]) return NO;
    [self requestFocusAtPreviewPoint:CGPointMake(
        CGRectGetMidX(self.captureController.previewLayer.frame),
        CGRectGetMidY(self.captureController.previewLayer.frame))];
    return YES;
}

- (void)requestFocusAtPreviewPoint:(CGPoint)point
{
    AVCaptureVideoPreviewLayer *previewLayer = self.captureController.previewLayer;
    if (![self isCameraInteractionAvailable] || !previewLayer ||
        previewLayer.superlayer != self.previewView.layer ||
        !CGRectContainsPoint(previewLayer.frame, point)) return;

    CGPoint layerPoint = [self.previewView.layer convertPoint:point toLayer:previewLayer];
    CGPoint devicePoint = [previewLayer captureDevicePointOfInterestForPoint:layerPoint];
    if (!isfinite(devicePoint.x) || !isfinite(devicePoint.y) ||
        devicePoint.x < 0.0 || devicePoint.x > 1.0 ||
        devicePoint.y < 0.0 || devicePoint.y > 1.0) return;

    NSUInteger requestGeneration = ++self.focusRequestGeneration;
    __weak RLVBaseCameraViewController *controller = self;
    [self.captureController focusAndExposeAtDevicePoint:devicePoint
                                             completion:^(RLVPointOfInterestResult result) {
        if (!controller || requestGeneration != controller.focusRequestGeneration ||
            result == RLVPointOfInterestResultNone || !controller.isViewVisible) return;
        [controller showFocusReticleAtPreviewPoint:point];
    }];
}

- (void)showFocusReticleAtPreviewPoint:(CGPoint)point
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideFocusReticle) object:nil];
    [self.focusReticleView.layer removeAllAnimations];
    CGPoint localPoint = CGPointMake(point.x - CGRectGetMinX(self.focusOverlayView.frame),
                                     point.y - CGRectGetMinY(self.focusOverlayView.frame));
    self.focusReticleView.center = localPoint;
    self.focusReticleView.hidden = NO;
    self.focusReticleView.alpha = 1.0;
    self.focusReticleView.transform = CGAffineTransformMakeScale(1.35, 1.35);
    [UIView animateWithDuration:0.16 delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ self.focusReticleView.transform = CGAffineTransformIdentity; }
                     completion:nil];
    [self performSelector:@selector(hideFocusReticle) withObject:nil afterDelay:0.85];
}

- (void)hideFocusReticle
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideFocusReticle) object:nil];
    if (self.focusReticleView.hidden) return;
    [UIView animateWithDuration:0.22 delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ self.focusReticleView.alpha = 0.0; }
                     completion:^(BOOL finished) {
        if (finished) {
            self.focusReticleView.hidden = YES;
            self.focusReticleView.transform = CGAffineTransformIdentity;
        }
    }];
}

- (void)captureController:(RLVCaptureController *)controller didChangeState:(RLVCaptureState)state
{
    self.shutterButton.capturing = state == RLVCaptureStateCapturing;
    [self updateCameraControls];
    if (state != RLVCaptureStateRunning) {
        self.focusRequestGeneration += 1;
        [self hideFocusReticle];
    }
    if (state == RLVCaptureStateCapturing) {
        if (controller.isMotionCaptureEnabled && controller.isRecordingMotion) [self showLiveCaptureIndicator];
        self.shutterOverlay.alpha = 0.72;
        [UIView animateWithDuration:0.16 animations:^{ self.shutterOverlay.alpha = 0.0; }];
    } else {
        [self hideLiveCaptureIndicator];
    }
}

- (void)captureController:(RLVCaptureController *)controller didCapturePhotoData:(NSData *)photoData motionURL:(NSURL *)motionURL event:(RLVCaptureEvent *)event
{
    (void)controller;
    self.savingAsset = YES;
    self.focusRequestGeneration += 1;
    [self hideFocusReticle];
    [self updateCameraControls];
    __weak RLVBaseCameraViewController *cameraController = self;
    [[RLVAssetStore sharedStore] createAssetWithPhotoData:photoData motionURL:motionURL event:event capabilities:self.capabilities
                                              completion:^(RLVAsset *asset, NSError *error) {
        if (motionURL) [[NSFileManager defaultManager] removeItemAtURL:motionURL error:NULL];
        if (!cameraController) return;
        cameraController.savingAsset = NO;
        if (asset) [cameraController updateThumbnail];
        [cameraController updateCameraControls];
        if (error) [cameraController showError:error];
    }];
}

- (void)captureController:(RLVCaptureController *)controller didFailWithError:(NSError *)error
{
    (void)controller;
    [self showError:error];
}

- (void)orientationCoordinator:(RLVCameraOrientationCoordinator *)coordinator didUpdateControlTransform:(CGAffineTransform)transform
{
    self.focusRequestGeneration += 1;
    [self hideFocusReticle];
    [self.captureController updateVideoOrientation:coordinator.videoOrientation];
    [UIView animateWithDuration:0.22 animations:^{
        for (UIView *control in self.rotatingControls) {
            if ([control isKindOfClass:[UIButton class]]) {
                UIButton *button = (UIButton *)control;
                button.imageView.transform = transform;
                button.titleLabel.transform = transform;
            } else {
                control.transform = transform;
            }
        }
    }];
}

- (void)updateThumbnail
{
    NSUInteger generation = ++self.thumbnailRequestGeneration;
    __weak RLVBaseCameraViewController *controller = self;
    [[RLVAssetStore sharedStore] loadAssetsWithCompletion:^(NSArray *assets, NSError *error) {
        (void)error;
        if (!controller || generation != controller.thumbnailRequestGeneration) return;
        RLVAsset *asset = [assets count] > 0 ? [assets objectAtIndex:0] : nil;
        controller.thumbnailRequestAssetId = asset.assetId;
        if (!asset) {
            [controller.thumbnailButton setImage:nil forState:UIControlStateNormal];
            [controller updateCameraControls];
            return;
        }
        [controller updateCameraControls];
        [controller loadThumbnailForAsset:asset generation:generation retry:NO];
    }];
}

- (void)loadThumbnailForAsset:(RLVAsset *)asset generation:(NSUInteger)generation retry:(BOOL)retry
{
    NSString *assetId = [asset.assetId copy];
    NSURL *thumbnailURL = asset.thumbnailURL;
    NSURL *photoURL = asset.photoURL;
    __weak RLVBaseCameraViewController *controller = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImage *image = thumbnailURL ? [controller thumbnailAtURL:thumbnailURL maximumSize:120.0] : nil;
        if (!image) image = [controller thumbnailAtURL:photoURL maximumSize:120.0];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!controller || generation != controller.thumbnailRequestGeneration ||
                ![controller.thumbnailRequestAssetId isEqualToString:assetId]) return;
            if (!image && !retry) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    if (generation == controller.thumbnailRequestGeneration) {
                        [controller loadThumbnailForAsset:asset generation:generation retry:YES];
                    }
                });
                return;
            }
            if (image) {
                [controller.thumbnailButton setImage:image forState:UIControlStateNormal];
                controller.thumbnailButton.imageView.contentMode = UIViewContentModeScaleAspectFill;
                controller.thumbnailButton.clipsToBounds = YES;
            }
            [controller updateCameraControls];
        });
    });
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
@synthesize livePhotoButton = _livePhotoButton;
@synthesize cameraSwitchButton = _cameraSwitchButton;
@synthesize aspectRatioButton = _aspectRatioButton;
@synthesize rotatingControls = _rotatingControls;
@synthesize capabilities = _capabilities;
@synthesize captureController = _captureController;
@synthesize orientationCoordinator = _orientationCoordinator;
@synthesize shutterOverlay = _shutterOverlay;
@synthesize liveCaptureIndicator = _liveCaptureIndicator;
@synthesize viewVisible = _viewVisible;
@synthesize thumbnailRequestAssetId = _thumbnailRequestAssetId;
@synthesize thumbnailRequestGeneration = _thumbnailRequestGeneration;
@synthesize activeAspectRatio = _activeAspectRatio;
@synthesize savingAsset = _savingAsset;
@synthesize focusTapGestureRecognizer = _focusTapGestureRecognizer;

@end
