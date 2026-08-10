#import "RLVAssetDetailViewController.h"
#import "RLVAssetStore.h"
#import "RLVLibraryViewController.h"
#import "RLVLayout.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

typedef NS_ENUM(NSInteger, RLVLivePlaybackMode) {
    RLVLivePlaybackModeLive = 0,
    RLVLivePlaybackModeLoop,
    RLVLivePlaybackModeBounce,
    RLVLivePlaybackModeStill
};

static NSInteger const RLVDeleteConfirmationAlertTag = 918;

static UIImage *RLVInformationImage(void)
{
    CGSize size = CGSizeMake(22.0, 22.0);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(context, [UIColor whiteColor].CGColor);
    CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
    CGContextSetLineWidth(context, 1.5);
    CGContextStrokeEllipseInRect(context, CGRectMake(2.5, 2.5, 17.0, 17.0));
    CGContextFillEllipseInRect(context, CGRectMake(10.0, 6.0, 2.0, 2.0));
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineWidth(context, 2.0);
    CGContextMoveToPoint(context, 11.0, 10.0);
    CGContextAddLineToPoint(context, 11.0, 16.0);
    CGContextStrokePath(context);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@interface RLVAssetDetailViewController () <UIActionSheetDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) NSArray *assets;
@property (nonatomic, assign) NSUInteger selectedIndex;
@property (nonatomic, strong) RLVAsset *asset;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *metadataLabel;
@property (nonatomic, strong) UIButton *liveBadge;
@property (nonatomic, strong) UIToolbar *toolbar;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) id playbackTimeObserver;
@property (nonatomic, assign) RLVLivePlaybackMode playbackMode;
@property (nonatomic, assign) BOOL playingBackward;
@property (nonatomic, assign) BOOL didAutoPlay;
- (UIImage *)framedImage:(UIImage *)image;
@end

@implementation RLVAssetDetailViewController

- (id)initWithAsset:(RLVAsset *)asset
{
    return [self initWithAssets:asset ? [NSArray arrayWithObject:asset] : [NSArray array] selectedIndex:0];
}

- (id)initWithAssets:(NSArray *)assets selectedIndex:(NSUInteger)selectedIndex
{
    self = [super init];
    if (self) {
        _assets = [assets copy] ?: [NSArray array];
        _selectedIndex = [_assets count] == 0 ? NSNotFound : MIN(selectedIndex, [_assets count] - 1);
        _asset = _selectedIndex == NSNotFound ? nil : [_assets objectAtIndex:_selectedIndex];
        _playbackMode = [self savedPlaybackMode];
    }
    return self;
}

- (void)loadView
{
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    UIView *root = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    root.backgroundColor = [UIColor blackColor];

    self.imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.imageView.contentMode = UIViewContentModeScaleAspectFill;
    self.imageView.clipsToBounds = YES;
    self.imageView.userInteractionEnabled = YES;
    [root addSubview:self.imageView];

    UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(photoSwiped:)];
    swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    [self.imageView addGestureRecognizer:swipeLeft];
    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(photoSwiped:)];
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    [self.imageView addGestureRecognizer:swipeRight];

    self.metadataLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.metadataLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.82];
    self.metadataLabel.textColor = [UIColor whiteColor];
    self.metadataLabel.font = [UIFont systemFontOfSize:12.0];
    self.metadataLabel.numberOfLines = 3;
    self.metadataLabel.textAlignment = NSTextAlignmentCenter;
    self.metadataLabel.hidden = YES;
    self.metadataLabel.alpha = 0.0;
    [root addSubview:self.metadataLabel];

    self.liveBadge = [UIButton buttonWithType:UIButtonTypeCustom];
    self.liveBadge.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.58];
    self.liveBadge.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
    self.liveBadge.contentEdgeInsets = UIEdgeInsetsMake(0.0, 10.0, 0.0, 10.0);
    self.liveBadge.layer.cornerRadius = 14.0;
    [self.liveBadge addTarget:self action:@selector(showPlaybackModes:) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:self.liveBadge];

    self.toolbar = [[UIToolbar alloc] initWithFrame:CGRectZero];
    self.toolbar.barStyle = UIBarStyleBlack;
    UIBarButtonItem *share = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
        target:self action:@selector(sharePhoto:)];
    share.accessibilityLabel = NSLocalizedString(@"asset.share", nil);
    UIBarButtonItem *info = [[UIBarButtonItem alloc] initWithImage:RLVInformationImage()
        style:UIBarButtonItemStylePlain target:self action:@selector(toggleMetadata:)];
    info.accessibilityLabel = NSLocalizedString(@"asset.info", nil);
    UIBarButtonItem *trash = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
        target:self action:@selector(confirmDelete:)];
    trash.accessibilityLabel = NSLocalizedString(@"asset.delete", nil);
    UIBarButtonItem *space1 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *space2 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    self.toolbar.items = [NSArray arrayWithObjects:share, space1, info, space2, trash, nil];
    [root addSubview:self.toolbar];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(finishViewing:)];

    RLVPrepareViewsForAutoLayout(@[self.metadataLabel, self.liveBadge, self.toolbar]);
    RLVAddVisualConstraints(root, @{ @"metadata": self.metadataLabel, @"toolbar": self.toolbar },
        @[@"H:|[metadata]|", @"H:|[toolbar]|", @"V:[metadata(82)][toolbar(44)]|"]);
    RLVAddVisualConstraints(root, @{ @"live": self.liveBadge },
        @[@"H:|-(12)-[live]", @"V:|-(12)-[live(28)]"]);
    self.view = root;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive:)
        name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [self displaySelectedAssetWithDirection:0 animated:NO];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (self.navigationController.navigationBarHidden) {
        [self.navigationController setNavigationBarHidden:NO animated:animated];
    }
    if (!self.imageView.image) {
        [self displaySelectedAssetWithDirection:0 animated:NO];
    } else if ([self.asset hasMotion] && !self.player) {
        [self preparePlayer];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self startAutomaticPlaybackIfNeeded];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self tearDownPlayer];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGSize imageSize = self.imageView.image.size;
    CGFloat ratio = imageSize.height > 0 ? imageSize.width / imageSize.height : 1.0;
    CGRect bounds = self.view.bounds;
    bounds.size.height = MAX(0.0, CGRectGetHeight(bounds) - 44.0);
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = ratio > 0 ? width / ratio : CGRectGetHeight(bounds);
    if (height > CGRectGetHeight(bounds)) {
        height = CGRectGetHeight(bounds);
        width = height * ratio;
    }
    self.imageView.frame = CGRectIntegral(CGRectMake(CGRectGetMidX(bounds) - width * 0.5,
        CGRectGetMidY(bounds) - height * 0.5, width, height));
    self.playerLayer.frame = self.imageView.bounds;
}

- (void)selectAssetFromAssets:(NSArray *)assets atIndex:(NSUInteger)index
{
    if ([assets count] == 0 || index >= [assets count]) return;
    NSUInteger oldIndex = self.selectedIndex;
    self.assets = [assets copy];
    self.selectedIndex = index;
    if (self.navigationController.topViewController != self) {
        self.asset = [self.assets objectAtIndex:self.selectedIndex];
        self.imageView.image = nil;
        self.didAutoPlay = NO;
        return;
    }
    [self displaySelectedAssetWithDirection:index > oldIndex ? 1 : -1 animated:NO];
}

- (void)photoSwiped:(UISwipeGestureRecognizer *)recognizer
{
    if (recognizer.direction == UISwipeGestureRecognizerDirectionLeft) {
        if (self.selectedIndex == NSNotFound || self.selectedIndex + 1 >= [self.assets count]) return;
        self.selectedIndex++;
        [self displaySelectedAssetWithDirection:1 animated:YES];
    } else {
        if (self.selectedIndex == NSNotFound || self.selectedIndex == 0) return;
        self.selectedIndex--;
        [self displaySelectedAssetWithDirection:-1 animated:YES];
    }
}

- (void)displaySelectedAssetWithDirection:(NSInteger)direction animated:(BOOL)animated
{
    if (self.selectedIndex == NSNotFound || self.selectedIndex >= [self.assets count]) return;
    [self tearDownPlayer];
    self.asset = [self.assets objectAtIndex:self.selectedIndex];
    self.playbackMode = [self savedPlaybackMode];
    self.didAutoPlay = NO;

    UIImage *image = [self framedImage:[UIImage imageWithContentsOfFile:[self.asset.photoURL path]]];
    if (animated) {
        CATransition *transition = [CATransition animation];
        transition.duration = 0.24;
        transition.type = kCATransitionPush;
        transition.subtype = direction > 0 ? kCATransitionFromRight : kCATransitionFromLeft;
        transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.imageView.layer addAnimation:transition forKey:@"RLVPhotoPaging"];
    }
    self.imageView.image = image;
    [self updateMetadata];
    self.liveBadge.hidden = ![self.asset hasMotion];
    if ([self.asset hasMotion]) [self preparePlayer];
    [self updatePlaybackModeUI];
    [self.view setNeedsLayout];
    if (self.view.window && self.navigationController.topViewController == self) {
        [self startAutomaticPlaybackIfNeeded];
    }
}

- (void)updateMetadata
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterMediumStyle;
    NSUInteger displayWidth = self.asset.width;
    NSUInteger displayHeight = self.asset.height;
    // Manifest dimensions describe the encoded JPEG pixel matrix. EXIF
    // orientations 5 through 8 rotate that matrix for display.
    if (self.asset.orientation >= 5 && self.asset.orientation <= 8) {
        displayWidth = self.asset.height;
        displayHeight = self.asset.width;
    }
    self.metadataLabel.text = [NSString stringWithFormat:@"%@\n%lu × %lu\n%@",
        [formatter stringFromDate:self.asset.captureTimestamp], (unsigned long)displayWidth,
        (unsigned long)displayHeight, self.asset.captureDevice ?: NSLocalizedString(@"asset.unknown_device", nil)];
    self.metadataLabel.accessibilityLabel = self.metadataLabel.text;
}

- (void)finishViewing:(id)sender
{
    (void)sender;
    [self.navigationController popToRootViewControllerAnimated:YES];
}

- (void)sharePhoto:(id)sender
{
    (void)sender;
    if (!self.asset.photoURL) return;
    UIActivityViewController *activity = [[UIActivityViewController alloc]
        initWithActivityItems:[NSArray arrayWithObject:self.asset.photoURL] applicationActivities:nil];
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)toggleMetadata:(id)sender
{
    (void)sender;
    BOOL shouldShow = self.metadataLabel.hidden;
    if (shouldShow) {
        self.metadataLabel.hidden = NO;
        [UIView animateWithDuration:0.2 animations:^{ self.metadataLabel.alpha = 1.0; }];
    } else {
        [UIView animateWithDuration:0.2 animations:^{ self.metadataLabel.alpha = 0.0; }
            completion:^(BOOL finished) { if (finished) self.metadataLabel.hidden = YES; }];
    }
}

- (void)confirmDelete:(id)sender
{
    (void)sender;
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"asset.delete.title", nil)
        message:NSLocalizedString(@"asset.delete.message", nil) delegate:self
        cancelButtonTitle:NSLocalizedString(@"common.cancel", nil)
        otherButtonTitles:NSLocalizedString(@"asset.delete", nil), nil];
    alert.tag = RLVDeleteConfirmationAlertTag;
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (alertView.tag != RLVDeleteConfirmationAlertTag || buttonIndex == alertView.cancelButtonIndex) return;
    NSError *error = nil;
    if (![[RLVAssetStore sharedStore] deleteAsset:self.asset error:&error]) {
        UIAlertView *failure = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"asset.delete.failed", nil)
            message:[error localizedDescription] delegate:nil cancelButtonTitle:NSLocalizedString(@"common.ok", nil)
            otherButtonTitles:nil];
        [failure show];
        return;
    }

    NSMutableArray *remaining = [self.assets mutableCopy];
    [remaining removeObjectAtIndex:self.selectedIndex];
    self.assets = remaining;
    if ([self.assets count] == 0) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    if (self.selectedIndex >= [self.assets count]) self.selectedIndex = [self.assets count] - 1;
    [self displaySelectedAssetWithDirection:1 animated:YES];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    if ([self isViewLoaded] && !self.view.window) {
        [self tearDownPlayer];
        self.imageView.image = nil;
    }
}

- (UIImage *)framedImage:(UIImage *)image
{
    if (!image || [self.asset.aspectRatio isEqualToString:@"native"]) return image;
    CGFloat landscapeRatio = 4.0 / 3.0;
    if ([self.asset.aspectRatio isEqualToString:@"1:1"]) landscapeRatio = 1.0;
    else if ([self.asset.aspectRatio isEqualToString:@"16:9"]) landscapeRatio = 16.0 / 9.0;
    CGRect aperture = CGRectMake(0.0, 0.0, image.size.width, image.size.height);
    if (self.asset.motionWidth > 0 && self.asset.motionHeight > 0) {
        CGFloat motionRatio = (CGFloat)self.asset.motionWidth / (CGFloat)self.asset.motionHeight;
        CGFloat currentRatio = CGRectGetWidth(aperture) / CGRectGetHeight(aperture);
        if (currentRatio > motionRatio) {
            CGFloat width = CGRectGetHeight(aperture) * motionRatio;
            aperture.origin.x = CGRectGetMidX(aperture) - width * 0.5;
            aperture.size.width = width;
        } else {
            CGFloat height = CGRectGetWidth(aperture) / motionRatio;
            aperture.origin.y = CGRectGetMidY(aperture) - height * 0.5;
            aperture.size.height = height;
        }
    }
    CGFloat targetRatio = image.size.width >= image.size.height ? landscapeRatio : 1.0 / landscapeRatio;
    CGFloat apertureRatio = CGRectGetWidth(aperture) / CGRectGetHeight(aperture);
    CGRect crop = aperture;
    if (apertureRatio > targetRatio) {
        crop.size.width = CGRectGetHeight(aperture) * targetRatio;
        crop.origin.x = CGRectGetMidX(aperture) - crop.size.width * 0.5;
    } else {
        crop.size.height = CGRectGetWidth(aperture) / targetRatio;
        crop.origin.y = CGRectGetMidY(aperture) - crop.size.height * 0.5;
    }
    CGFloat outputScale = MIN(1.0, 1024.0 / MAX(CGRectGetWidth(crop), CGRectGetHeight(crop)));
    CGSize outputSize = CGSizeMake(MAX(1.0, floor(CGRectGetWidth(crop) * outputScale)),
        MAX(1.0, floor(CGRectGetHeight(crop) * outputScale)));
    UIGraphicsBeginImageContextWithOptions(outputSize, YES, 1.0);
    CGFloat drawScale = outputSize.width / CGRectGetWidth(crop);
    [image drawInRect:CGRectMake(-crop.origin.x * drawScale, -crop.origin.y * drawScale,
        image.size.width * drawScale, image.size.height * drawScale)];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result ?: image;
}

- (void)preparePlayer
{
    self.player = [AVPlayer playerWithURL:self.asset.motionURL];
    self.player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.playerLayer.hidden = YES;
    [self.imageView.layer addSublayer:self.playerLayer];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemDidReachEnd:)
        name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];

    __weak RLVAssetDetailViewController *controller = self;
    self.playbackTimeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 20)
        queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
            if (controller.playbackMode == RLVLivePlaybackModeBounce && controller.playingBackward &&
                CMTimeGetSeconds(time) <= 0.05) {
                controller.playingBackward = NO;
                [controller.player seekToTime:kCMTimeZero];
                [controller.player play];
            }
        }];
}

- (void)tearDownPlayer
{
    [self returnToStillPhoto];
    if (self.playbackTimeObserver) {
        [self.player removeTimeObserver:self.playbackTimeObserver];
        self.playbackTimeObserver = nil;
    }
    if (self.player.currentItem) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification
            object:self.player.currentItem];
    }
    [self.playerLayer removeFromSuperlayer];
    self.playerLayer = nil;
    self.player = nil;
}

- (void)startAutomaticPlaybackIfNeeded
{
    if (![self.asset hasMotion]) return;
    if (self.playbackMode == RLVLivePlaybackModeLoop || self.playbackMode == RLVLivePlaybackModeBounce) {
        [self startPlayback];
    } else if (self.playbackMode == RLVLivePlaybackModeLive && !self.didAutoPlay) {
        self.didAutoPlay = YES;
        [self startPlayback];
    }
}

- (void)startPlayback
{
    if (![self.asset hasMotion] || self.playbackMode == RLVLivePlaybackModeStill) return;
    self.playingBackward = NO;
    self.playerLayer.hidden = NO;
    [self.player seekToTime:kCMTimeZero];
    [self.player play];
    [self setBadgeActive:YES];
}

- (void)returnToStillPhoto
{
    [self.player pause];
    [self.player seekToTime:kCMTimeZero];
    self.playingBackward = NO;
    self.playerLayer.hidden = YES;
    [self setBadgeActive:NO];
}

- (void)livePhotoPressed:(UILongPressGestureRecognizer *)recognizer
{
    if (self.playbackMode != RLVLivePlaybackModeLive) return;
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        [self startPlayback];
    } else if (recognizer.state == UIGestureRecognizerStateEnded ||
        recognizer.state == UIGestureRecognizerStateCancelled ||
        recognizer.state == UIGestureRecognizerStateFailed) {
        [self returnToStillPhoto];
    }
}

- (void)playerItemDidReachEnd:(NSNotification *)notification
{
    (void)notification;
    if (self.playbackMode == RLVLivePlaybackModeLoop) {
        [self.player seekToTime:kCMTimeZero];
        [self.player play];
    } else if (self.playbackMode == RLVLivePlaybackModeBounce && self.player.currentItem.canPlayReverse) {
        self.playingBackward = YES;
        __weak RLVAssetDetailViewController *controller = self;
        [self.player seekToTime:self.player.currentItem.duration completionHandler:^(BOOL finished) {
            if (finished && controller.playbackMode == RLVLivePlaybackModeBounce && controller.playingBackward) {
                controller.player.rate = -1.0;
            }
        }];
    } else if (self.playbackMode == RLVLivePlaybackModeBounce) {
        self.playbackMode = RLVLivePlaybackModeLive;
        [self savePlaybackMode];
        [self updatePlaybackModeUI];
        [self returnToStillPhoto];
        [self showBounceUnsupported];
    } else {
        [self returnToStillPhoto];
    }
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    (void)notification;
    [self returnToStillPhoto];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    (void)notification;
    if (self.view.window && self.navigationController.topViewController == self) {
        [self startAutomaticPlaybackIfNeeded];
    }
}

- (void)showPlaybackModes:(id)sender
{
    (void)sender;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"asset.live.effect.title", nil)
        delegate:self cancelButtonTitle:NSLocalizedString(@"common.cancel", nil) destructiveButtonTitle:nil
        otherButtonTitles:NSLocalizedString(@"asset.live.mode.live", nil),
            NSLocalizedString(@"asset.live.mode.loop", nil),
            NSLocalizedString(@"asset.live.mode.bounce", nil),
            NSLocalizedString(@"asset.live.mode.still", nil), nil];
    [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    (void)actionSheet;
    if (buttonIndex < RLVLivePlaybackModeLive || buttonIndex > RLVLivePlaybackModeStill) return;
    if (buttonIndex == RLVLivePlaybackModeBounce && !self.player.currentItem.canPlayReverse) {
        [self showBounceUnsupported];
        return;
    }
    self.playbackMode = (RLVLivePlaybackMode)buttonIndex;
    [self savePlaybackMode];
    [self updatePlaybackModeUI];
    [self returnToStillPhoto];
    if (self.playbackMode != RLVLivePlaybackModeStill) [self startPlayback];
}

- (void)updatePlaybackModeUI
{
    NSString *title = nil;
    switch (self.playbackMode) {
        case RLVLivePlaybackModeLoop: title = NSLocalizedString(@"asset.live.badge.loop", nil); break;
        case RLVLivePlaybackModeBounce: title = NSLocalizedString(@"asset.live.badge.bounce", nil); break;
        case RLVLivePlaybackModeStill: title = NSLocalizedString(@"asset.live.badge.still", nil); break;
        default: title = NSLocalizedString(@"asset.live.badge.live", nil); break;
    }
    [self.liveBadge setTitle:title forState:UIControlStateNormal];
    self.liveBadge.accessibilityLabel = NSLocalizedString(@"asset.live.effect.title", nil);
    self.liveBadge.accessibilityValue = title;

    for (UIGestureRecognizer *recognizer in [self.imageView.gestureRecognizers copy]) {
        if ([recognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
            [self.imageView removeGestureRecognizer:recognizer];
        }
    }
    if ([self.asset hasMotion]) {
        UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self
            action:@selector(livePhotoPressed:)];
        press.minimumPressDuration = 0.12;
        [self.imageView addGestureRecognizer:press];
    }
}

- (void)setBadgeActive:(BOOL)active
{
    self.liveBadge.backgroundColor = active ? [UIColor colorWithWhite:1.0 alpha:0.92] : [UIColor colorWithWhite:0.0 alpha:0.58];
    [self.liveBadge setTitleColor:active ? [UIColor blackColor] : [UIColor whiteColor] forState:UIControlStateNormal];
}

- (RLVLivePlaybackMode)savedPlaybackMode
{
    if (!self.asset) return RLVLivePlaybackModeLive;
    NSInteger mode = [[NSUserDefaults standardUserDefaults] integerForKey:[self playbackModeDefaultsKey]];
    return mode >= RLVLivePlaybackModeLive && mode <= RLVLivePlaybackModeStill ? (RLVLivePlaybackMode)mode : RLVLivePlaybackModeLive;
}

- (NSString *)playbackModeDefaultsKey
{
    return [NSString stringWithFormat:@"RLVLivePlaybackMode.%@", self.asset.assetId ?: @"unknown"];
}

- (void)savePlaybackMode
{
    [[NSUserDefaults standardUserDefaults] setInteger:self.playbackMode forKey:[self playbackModeDefaultsKey]];
}

- (void)showBounceUnsupported
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"asset.live.bounce.unsupported.title", nil)
        message:NSLocalizedString(@"asset.live.bounce.unsupported.message", nil) delegate:nil
        cancelButtonTitle:NSLocalizedString(@"common.ok", nil) otherButtonTitles:nil];
    [alert show];
}

- (void)dealloc
{
    [self tearDownPlayer];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@synthesize assets = _assets;
@synthesize selectedIndex = _selectedIndex;
@synthesize asset = _asset;
@synthesize imageView = _imageView;
@synthesize metadataLabel = _metadataLabel;
@synthesize liveBadge = _liveBadge;
@synthesize toolbar = _toolbar;
@synthesize player = _player;
@synthesize playerLayer = _playerLayer;
@synthesize playbackTimeObserver = _playbackTimeObserver;
@synthesize playbackMode = _playbackMode;
@synthesize playingBackward = _playingBackward;
@synthesize didAutoPlay = _didAutoPlay;

@end
