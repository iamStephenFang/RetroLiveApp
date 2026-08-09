#import "RLVAssetDetailViewController.h"
#import "RLVLayout.h"
#import <AVFoundation/AVFoundation.h>

typedef NS_ENUM(NSInteger, RLVLivePlaybackMode) {
    RLVLivePlaybackModeLive = 0,
    RLVLivePlaybackModeLoop,
    RLVLivePlaybackModeBounce,
    RLVLivePlaybackModeStill
};

@interface RLVAssetDetailViewController () <UIActionSheetDelegate>
@property (nonatomic, strong) RLVAsset *asset;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *metadataLabel;
@property (nonatomic, strong) UIButton *liveBadge;
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
    self = [super init];
    if (self) {
        _asset = asset;
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
    self.imageView.image = [self framedImage:[UIImage imageWithContentsOfFile:[self.asset.photoURL path]]];
    self.imageView.userInteractionEnabled = YES;
    [root addSubview:self.imageView];
    self.metadataLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.metadataLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.82];
    self.metadataLabel.textColor = [UIColor whiteColor];
    self.metadataLabel.font = [UIFont systemFontOfSize:12.0];
    self.metadataLabel.numberOfLines = 3;
    self.metadataLabel.textAlignment = NSTextAlignmentCenter;
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterMediumStyle;
    self.metadataLabel.text = [NSString stringWithFormat:@"%@\n%lu × %lu\n%@",
        [formatter stringFromDate:self.asset.captureTimestamp], (unsigned long)self.asset.width,
        (unsigned long)self.asset.height, self.asset.captureDevice ?: NSLocalizedString(@"asset.unknown_device", nil)];
    [root addSubview:self.metadataLabel];

    self.liveBadge = [UIButton buttonWithType:UIButtonTypeCustom];
    self.liveBadge.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.58];
    self.liveBadge.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
    self.liveBadge.contentEdgeInsets = UIEdgeInsetsMake(0.0, 10.0, 0.0, 10.0);
    self.liveBadge.layer.cornerRadius = 14.0;
    self.liveBadge.hidden = ![self.asset hasMotion];
    [self.liveBadge addTarget:self action:@selector(showPlaybackModes:) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:self.liveBadge];

    RLVPrepareViewsForAutoLayout(@[self.metadataLabel, self.liveBadge]);
    RLVAddVisualConstraints(root, @{ @"metadata": self.metadataLabel },
        @[@"H:|[metadata]|", @"V:[metadata(82)]|"]);
    [root addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(12)-[live]"
        options:0 metrics:nil views:@{ @"live": self.liveBadge }]];
    [root addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(12)-[live(28)]"
        options:0 metrics:nil views:@{ @"live": self.liveBadge }]];
    self.view = root;

    if ([self.asset hasMotion]) {
        [self preparePlayer];
        UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self
            action:@selector(livePhotoPressed:)];
        press.minimumPressDuration = 0.12;
        [self.imageView addGestureRecognizer:press];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithImage:[UIImage imageNamed:@"InterfaceIcons/RLVLiveEffect"]
            style:UIBarButtonItemStylePlain target:self action:@selector(showPlaybackModes:)];
        self.navigationItem.rightBarButtonItem.accessibilityLabel = NSLocalizedString(@"asset.live.effect", nil);
    }
    [self updatePlaybackModeUI];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (![self.asset hasMotion]) return;
    if (self.playbackMode == RLVLivePlaybackModeLoop || self.playbackMode == RLVLivePlaybackModeBounce) {
        [self startPlayback];
    } else if (self.playbackMode == RLVLivePlaybackModeLive && !self.didAutoPlay) {
        self.didAutoPlay = YES;
        [self startPlayback];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self returnToStillPhoto];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGSize imageSize = self.imageView.image.size;
    CGFloat ratio = imageSize.height > 0 ? imageSize.width / imageSize.height : 1.0;
    CGRect bounds = self.view.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = width / ratio;
    if (height > CGRectGetHeight(bounds)) {
        height = CGRectGetHeight(bounds);
        width = height * ratio;
    }
    self.imageView.frame = CGRectIntegral(CGRectMake(CGRectGetMidX(bounds) - width * 0.5,
        CGRectGetMidY(bounds) - height * 0.5, width, height));
    self.playerLayer.frame = self.imageView.bounds;
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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive:)
        name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:)
        name:UIApplicationDidBecomeActiveNotification object:nil];

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
    if (!self.view.window) return;
    if (self.playbackMode == RLVLivePlaybackModeLoop || self.playbackMode == RLVLivePlaybackModeBounce) {
        [self startPlayback];
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
}

- (void)setBadgeActive:(BOOL)active
{
    self.liveBadge.backgroundColor = active ? [UIColor colorWithWhite:1.0 alpha:0.92] : [UIColor colorWithWhite:0.0 alpha:0.58];
    [self.liveBadge setTitleColor:active ? [UIColor blackColor] : [UIColor whiteColor] forState:UIControlStateNormal];
}

- (RLVLivePlaybackMode)savedPlaybackMode
{
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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.playbackTimeObserver) [self.player removeTimeObserver:self.playbackTimeObserver];
}

@synthesize asset = _asset;
@synthesize imageView = _imageView;
@synthesize metadataLabel = _metadataLabel;
@synthesize liveBadge = _liveBadge;
@synthesize player = _player;
@synthesize playerLayer = _playerLayer;
@synthesize playbackTimeObserver = _playbackTimeObserver;
@synthesize playbackMode = _playbackMode;
@synthesize playingBackward = _playingBackward;
@synthesize didAutoPlay = _didAutoPlay;

@end
