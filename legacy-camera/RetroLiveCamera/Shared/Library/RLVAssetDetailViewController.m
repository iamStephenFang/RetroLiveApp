#import "RLVAssetDetailViewController.h"
#import "RLVAsset.h"
#import "RLVAssetStore.h"
#import "RLVLayout.h"
#import "RLVSettingsViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>

typedef NS_ENUM(NSInteger, RLVLivePlaybackMode) {
    RLVLivePlaybackModeLive = 0,
    RLVLivePlaybackModeLoop,
    RLVLivePlaybackModeBounce,
    RLVLivePlaybackModeStill
};

typedef NS_ENUM(NSInteger, RLVPlaybackIntent) {
    RLVPlaybackIntentNone = 0,
    RLVPlaybackIntentFromBeginning,
    RLVPlaybackIntentResume
};

static NSInteger const RLVDeleteConfirmationAlertTag = 918;
static CGFloat const RLVMaximumPhotoZoomScale = 4.0;
static void *RLVPlayerLayerReadyContext = &RLVPlayerLayerReadyContext;
static void *RLVPlayerItemStatusContext = &RLVPlayerItemStatusContext;

@class RLVZoomingImagePage;

@protocol RLVZoomingImagePageDelegate <NSObject>
- (void)zoomingImagePageDidBeginInteraction:(RLVZoomingImagePage *)page;
- (void)zoomingImagePageDidEndInteraction:(RLVZoomingImagePage *)page;
- (void)zoomingImagePageDidChangeZoom:(RLVZoomingImagePage *)page;
- (void)zoomingImagePageDidLayout:(RLVZoomingImagePage *)page;
@end

@interface RLVZoomingImagePage : UIView <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UITapGestureRecognizer *doubleTapGestureRecognizer;
@property (nonatomic, copy) NSString *representedAssetId;
@property (nonatomic, weak) id<RLVZoomingImagePageDelegate> delegate;
- (void)setImage:(UIImage *)image preservingGeometry:(BOOL)preservingGeometry;
- (void)resetZoom;
- (BOOL)isZoomed;
@end

@implementation RLVZoomingImagePage

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _scrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
        _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _scrollView.delegate = self;
        _scrollView.minimumZoomScale = 1.0;
        _scrollView.maximumZoomScale = RLVMaximumPhotoZoomScale;
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.showsVerticalScrollIndicator = NO;
        _scrollView.directionalLockEnabled = YES;
        _scrollView.panGestureRecognizer.enabled = NO;
        [self addSubview:_scrollView];

        _imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _imageView.contentMode = UIViewContentModeScaleAspectFit;
        _imageView.clipsToBounds = YES;
        _imageView.userInteractionEnabled = YES;
        [_scrollView addSubview:_imageView];

        _doubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self
            action:@selector(imageDoubleTapped:)];
        _doubleTapGestureRecognizer.numberOfTapsRequired = 2;
        [_imageView addGestureRecognizer:_doubleTapGestureRecognizer];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    if (![self isZoomed]) [self layoutImageAtMinimumZoom];
    else [self centerZoomedImage];
    [self.delegate zoomingImagePageDidLayout:self];
}

- (void)layoutImageAtMinimumZoom
{
    CGSize boundsSize = self.scrollView.bounds.size;
    CGSize imageSize = self.imageView.image.size;
    CGFloat width = boundsSize.width;
    CGFloat height = boundsSize.height;
    if (imageSize.width > 0.0 && imageSize.height > 0.0) {
        CGFloat ratio = imageSize.width / imageSize.height;
        height = ratio > 0.0 ? width / ratio : boundsSize.height;
        if (height > boundsSize.height) {
            height = boundsSize.height;
            width = height * ratio;
        }
    }
    self.imageView.transform = CGAffineTransformIdentity;
    self.imageView.frame = CGRectIntegral(CGRectMake((boundsSize.width - width) * 0.5,
        (boundsSize.height - height) * 0.5, width, height));
    self.scrollView.contentSize = boundsSize;
    self.scrollView.contentOffset = CGPointZero;
}

- (void)centerZoomedImage
{
    CGSize boundsSize = self.scrollView.bounds.size;
    CGRect frame = self.imageView.frame;
    frame.origin.x = frame.size.width < boundsSize.width ? (boundsSize.width - frame.size.width) * 0.5 : 0.0;
    frame.origin.y = frame.size.height < boundsSize.height ? (boundsSize.height - frame.size.height) * 0.5 : 0.0;
    self.imageView.frame = frame;
}

- (void)setImage:(UIImage *)image preservingGeometry:(BOOL)preservingGeometry
{
    UIImage *oldImage = self.imageView.image;
    CGFloat oldRatio = oldImage.size.height > 0.0 ? oldImage.size.width / oldImage.size.height : 0.0;
    CGFloat newRatio = image.size.height > 0.0 ? image.size.width / image.size.height : 0.0;
    if (preservingGeometry && oldImage && image && fabs(oldRatio - newRatio) < 0.01) {
        // Placeholder and decoded still share one presentation aperture. Swap
        // only the backing pixels so zoom, geometry, and playback stay stable.
        self.imageView.image = image;
        return;
    }
    self.imageView.image = image;
    [self resetZoom];
    [self setNeedsLayout];
}

- (void)resetZoom
{
    [self.scrollView setZoomScale:self.scrollView.minimumZoomScale animated:NO];
    self.scrollView.panGestureRecognizer.enabled = NO;
    [self layoutImageAtMinimumZoom];
}

- (BOOL)isZoomed
{
    return self.scrollView.zoomScale > self.scrollView.minimumZoomScale + 0.01;
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    return scrollView == self.scrollView ? self.imageView : nil;
}

- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view
{
    (void)scrollView;
    (void)view;
    [self.delegate zoomingImagePageDidBeginInteraction:self];
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView
{
    if (scrollView != self.scrollView) return;
    scrollView.panGestureRecognizer.enabled = [self isZoomed];
    [self centerZoomedImage];
    [self.delegate zoomingImagePageDidChangeZoom:self];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    if (scrollView == self.scrollView) [self.delegate zoomingImagePageDidBeginInteraction:self];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if (scrollView == self.scrollView && !decelerate) [self.delegate zoomingImagePageDidEndInteraction:self];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    if (scrollView == self.scrollView) [self.delegate zoomingImagePageDidEndInteraction:self];
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(CGFloat)scale
{
    (void)view;
    (void)scale;
    if (scrollView == self.scrollView) [self.delegate zoomingImagePageDidEndInteraction:self];
}

- (void)imageDoubleTapped:(UITapGestureRecognizer *)recognizer
{
    [self.delegate zoomingImagePageDidBeginInteraction:self];
    if ([self isZoomed]) {
        [self.scrollView setZoomScale:self.scrollView.minimumZoomScale animated:YES];
        return;
    }
    CGPoint point = [recognizer locationInView:self.imageView];
    CGFloat scale = MIN(2.0, self.scrollView.maximumZoomScale);
    CGSize size = CGSizeMake(CGRectGetWidth(self.scrollView.bounds) / scale,
        CGRectGetHeight(self.scrollView.bounds) / scale);
    CGRect zoomRect = CGRectMake(point.x - size.width * 0.5, point.y - size.height * 0.5,
        size.width, size.height);
    [self.scrollView zoomToRect:zoomRect animated:YES];
}

@synthesize scrollView = _scrollView;
@synthesize imageView = _imageView;
@synthesize doubleTapGestureRecognizer = _doubleTapGestureRecognizer;
@synthesize representedAssetId = _representedAssetId;
@synthesize delegate = _delegate;

@end

static UIImage *RLVInformationImage(void)
{
    CGSize size = CGSizeMake(30.0, 30.0);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(context, [UIColor whiteColor].CGColor);
    CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
    CGContextSetLineWidth(context, 1.25);
    CGContextStrokeEllipseInRect(context, CGRectMake(2.0, 2.0, 26.0, 26.0));
    CGContextFillEllipseInRect(context, CGRectMake(13.8, 6.8, 2.4, 2.4));
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineWidth(context, 1.5);
    CGContextMoveToPoint(context, 15.0, 12.5);
    CGContextAddLineToPoint(context, 15.0, 22.0);
    CGContextStrokePath(context);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@interface RLVAssetDetailViewController () <UIActionSheetDelegate, UIAlertViewDelegate, UIScrollViewDelegate, RLVZoomingImagePageDelegate>
@property (nonatomic, strong) NSArray *assets;
@property (nonatomic, assign) NSUInteger selectedIndex;
@property (nonatomic, strong) RLVAsset *asset;
@property (nonatomic, strong) UIScrollView *pagingScrollView;
@property (nonatomic, strong) RLVZoomingImagePage *previousPage;
@property (nonatomic, strong) RLVZoomingImagePage *currentPage;
@property (nonatomic, strong) RLVZoomingImagePage *nextPage;
@property (nonatomic, strong) NSCache *previewCache;
@property (nonatomic, strong) NSOperationQueue *imageQueue;
@property (nonatomic, assign) NSUInteger imageLoadGeneration;
@property (nonatomic, strong) UILabel *metadataLabel;
@property (nonatomic, strong) UIButton *liveBadge;
@property (nonatomic, strong) UIToolbar *toolbar;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) id playbackTimeObserver;
@property (nonatomic, assign) RLVLivePlaybackMode playbackMode;
@property (nonatomic, assign) BOOL playingBackward;
@property (nonatomic, assign) BOOL didAutoPlay;
@property (nonatomic, assign) BOOL playbackRequested;
@property (nonatomic, assign) BOOL playerLayerCanBeShown;
@property (nonatomic, assign) BOOL playbackEndTransitionPending;
@property (nonatomic, assign) NSUInteger playbackGeneration;
@property (nonatomic, assign) RLVPlaybackIntent playbackIntent;
@property (nonatomic, assign) RLVPlaybackIntent interactionResumeIntent;
@property (nonatomic, strong) UILongPressGestureRecognizer *livePressGestureRecognizer;
@property (nonatomic, strong) UITapGestureRecognizer *fullScreenTapGestureRecognizer;
@property (nonatomic, assign, getter=isFullScreenPreview) BOOL fullScreenPreview;
@property (nonatomic, assign) BOOL metadataWasVisibleBeforeFullScreen;
@property (nonatomic, assign) BOOL livePressActive;
- (void)settlePagingScrollView;
- (void)displaySelectedAsset;
- (void)reloadPagingImages;
- (void)processPlaybackIntentIfReady;
- (void)startPreparedPlaybackIfPossible;
- (void)updatePlayerLayerVisibility;
- (void)pausePlaybackForInteraction;
- (void)resumePlaybackAfterInteractionIfNeeded;
- (void)stopPlaybackAndShowStillResetPosition:(BOOL)resetPosition;
- (BOOL)canContinuePlayback;
- (void)setFullScreenPreview:(BOOL)fullScreen animated:(BOOL)animated;
- (void)updatePreviewChromeVisibility;
- (UIImage *)displayImageForAsset:(RLVAsset *)asset maximumPixelSize:(CGFloat)maximumPixelSize;
- (UIImage *)presentationImageFromImage:(UIImage *)image asset:(RLVAsset *)asset maximumPixelSize:(CGFloat)maximumPixelSize;
@end

@implementation RLVAssetDetailViewController

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

    self.previewCache = [[NSCache alloc] init];
    self.previewCache.countLimit = 5;
    self.previewCache.totalCostLimit = 24 * 1024 * 1024;
    self.imageQueue = [[NSOperationQueue alloc] init];
    self.imageQueue.maxConcurrentOperationCount = 2;

    self.pagingScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.pagingScrollView.backgroundColor = [UIColor blackColor];
    self.pagingScrollView.delegate = self;
    self.pagingScrollView.pagingEnabled = YES;
    self.pagingScrollView.showsHorizontalScrollIndicator = NO;
    self.pagingScrollView.showsVerticalScrollIndicator = NO;
    self.pagingScrollView.alwaysBounceVertical = NO;
    self.pagingScrollView.scrollsToTop = NO;
    self.pagingScrollView.decelerationRate = UIScrollViewDecelerationRateFast;
    [root addSubview:self.pagingScrollView];

    self.previousPage = [[RLVZoomingImagePage alloc] initWithFrame:CGRectZero];
    self.previousPage.delegate = self;
    [self.pagingScrollView addSubview:self.previousPage];

    self.currentPage = [[RLVZoomingImagePage alloc] initWithFrame:CGRectZero];
    self.currentPage.delegate = self;
    [self.pagingScrollView addSubview:self.currentPage];
    self.livePressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self
        action:@selector(livePhotoPressed:)];
    self.livePressGestureRecognizer.minimumPressDuration = 0.12;
    self.livePressGestureRecognizer.enabled = NO;
    [self.currentPage.imageView addGestureRecognizer:self.livePressGestureRecognizer];
    self.fullScreenTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self
        action:@selector(previewSingleTapped:)];
    self.fullScreenTapGestureRecognizer.numberOfTapsRequired = 1;
    [self.fullScreenTapGestureRecognizer requireGestureRecognizerToFail:self.currentPage.doubleTapGestureRecognizer];
    [self.fullScreenTapGestureRecognizer requireGestureRecognizerToFail:self.livePressGestureRecognizer];
    [self.currentPage addGestureRecognizer:self.fullScreenTapGestureRecognizer];

    self.nextPage = [[RLVZoomingImagePage alloc] initWithFrame:CGRectZero];
    self.nextPage.delegate = self;
    [self.pagingScrollView addSubview:self.nextPage];

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

    CGFloat toolbarHeight = [self.toolbar sizeThatFits:CGSizeMake(CGRectGetWidth(root.bounds), CGFLOAT_MAX)].height;
    if (toolbarHeight <= 0.0) toolbarHeight = 44.0;
    RLVPrepareViewsForAutoLayout(@[self.metadataLabel, self.liveBadge, self.toolbar]);
    RLVAddVisualConstraints(root, @{ @"metadata": self.metadataLabel, @"toolbar": self.toolbar },
        @[@"H:|[metadata]|", @"H:|[toolbar]|",
          [NSString stringWithFormat:@"V:[metadata(82)][toolbar(%.0f)]|", toolbarHeight]]);
    RLVAddVisualConstraints(root, @{ @"live": self.liveBadge },
        @[@"H:|-(12)-[live]", @"V:|-(12)-[live(28)]"]);
    self.view = root;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive:)
        name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [self displaySelectedAsset];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:self.isFullScreenPreview animated:animated];
    if (!self.currentPage.imageView.image) {
        [self displaySelectedAsset];
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
    // Do not leak immersive chrome state into the library navigation stack.
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    [self tearDownPlayer];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    bounds.size.height = MAX(0.0, CGRectGetHeight(bounds) -
        (self.isFullScreenPreview ? 0.0 : CGRectGetHeight(self.toolbar.frame)));
    self.pagingScrollView.frame = bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    self.pagingScrollView.contentSize = CGSizeMake(width * 3.0, height);
    self.previousPage.frame = CGRectMake(0.0, 0.0, width, height);
    self.currentPage.frame = CGRectMake(width, 0.0, width, height);
    self.nextPage.frame = CGRectMake(width * 2.0, 0.0, width, height);
    if (!self.pagingScrollView.dragging && !self.pagingScrollView.decelerating) {
        self.pagingScrollView.contentOffset = CGPointMake(width, 0.0);
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.playerLayer.frame = self.currentPage.imageView.bounds;
    [CATransaction commit];
}

- (void)previewSingleTapped:(UITapGestureRecognizer *)recognizer
{
    if (recognizer.state != UIGestureRecognizerStateRecognized) return;
    [self setFullScreenPreview:!self.isFullScreenPreview animated:YES];
}

- (void)setFullScreenPreview:(BOOL)fullScreen animated:(BOOL)animated
{
    if (self.isFullScreenPreview == fullScreen) return;
    if (fullScreen) {
        self.metadataWasVisibleBeforeFullScreen = !self.metadataLabel.hidden && self.metadataLabel.alpha > 0.01;
    }
    self.fullScreenPreview = fullScreen;
    [self.navigationController setNavigationBarHidden:fullScreen animated:animated];
    [self updatePreviewChromeVisibility];
    [self.view setNeedsLayout];
    if (animated) {
        [UIView animateWithDuration:0.2 animations:^{ [self.view layoutIfNeeded]; }];
    } else {
        [self.view layoutIfNeeded];
    }
}

- (void)updatePreviewChromeVisibility
{
    self.toolbar.hidden = self.isFullScreenPreview;
    self.liveBadge.hidden = self.isFullScreenPreview || ![self.asset hasMotion];
    if (self.isFullScreenPreview) {
        self.metadataLabel.hidden = YES;
        self.metadataLabel.alpha = 0.0;
    } else if (self.metadataWasVisibleBeforeFullScreen) {
        self.metadataLabel.hidden = NO;
        self.metadataLabel.alpha = 1.0;
    }
}

- (void)zoomingImagePageDidBeginInteraction:(RLVZoomingImagePage *)page
{
    if (page != self.currentPage) return;
    [self pausePlaybackForInteraction];
}

- (void)pausePlaybackForInteraction
{
    // Once a stationary press has been recognized it owns playback until
    // release. Incidental scroll-view callbacks must not turn that press into
    // a pause; a drag that begins before recognition still wins normally.
    if (self.livePressActive) return;
    if (self.interactionResumeIntent == RLVPlaybackIntentNone &&
        (self.playbackRequested || fabs(self.player.rate) > 0.01)) {
        self.interactionResumeIntent = self.playerLayerCanBeShown && !self.playbackEndTransitionPending
            ? RLVPlaybackIntentResume : RLVPlaybackIntentFromBeginning;
    }
    if (self.interactionResumeIntent == RLVPlaybackIntentNone) return;
    self.playbackGeneration++;
    self.playbackIntent = RLVPlaybackIntentNone;
    self.playbackRequested = NO;
    self.playbackEndTransitionPending = NO;
    [self.player cancelPendingPrerolls];
    [self.player pause];
    [self updatePlayerLayerVisibility];
    [self setBadgeActive:NO];
}

- (void)zoomingImagePageDidEndInteraction:(RLVZoomingImagePage *)page
{
    if (page != self.currentPage || !self.view.window || self.navigationController.topViewController != self ||
        [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    self.pagingScrollView.scrollEnabled = [self.assets count] > 1 && ![page isZoomed];
    [self resumePlaybackAfterInteractionIfNeeded];
}

- (void)resumePlaybackAfterInteractionIfNeeded
{
    RLVPlaybackIntent resumeIntent = self.interactionResumeIntent;
    self.interactionResumeIntent = RLVPlaybackIntentNone;
    if (resumeIntent == RLVPlaybackIntentNone) return;
    self.playbackGeneration++;
    self.playbackRequested = YES;
    self.playbackIntent = resumeIntent;
    if (resumeIntent == RLVPlaybackIntentFromBeginning) {
        self.playerLayerCanBeShown = NO;
        self.playingBackward = NO;
    }
    [self processPlaybackIntentIfReady];
    [self setBadgeActive:YES];
}

- (void)zoomingImagePageDidChangeZoom:(RLVZoomingImagePage *)page
{
    if (page != self.currentPage) return;
    BOOL interacting = page.scrollView.zooming || page.scrollView.dragging || page.scrollView.decelerating;
    self.pagingScrollView.scrollEnabled = [self.assets count] > 1 && ![page isZoomed] && !interacting;
}

- (void)zoomingImagePageDidLayout:(RLVZoomingImagePage *)page
{
    if (page != self.currentPage || !self.playerLayer) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.playerLayer.frame = page.imageView.bounds;
    [CATransaction commit];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    if (scrollView != self.pagingScrollView) return;
    [self pausePlaybackForInteraction];
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
                     withVelocity:(CGPoint)velocity
              targetContentOffset:(inout CGPoint *)targetContentOffset
{
    (void)velocity;
    if (scrollView != self.pagingScrollView || !targetContentOffset) return;
    CGFloat width = CGRectGetWidth(scrollView.bounds);
    if (width <= 0.0) return;
    if ((targetContentOffset->x < width && self.selectedIndex == 0) ||
        (targetContentOffset->x > width && (self.selectedIndex == NSNotFound ||
            self.selectedIndex + 1 >= [self.assets count]))) {
        targetContentOffset->x = width;
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    if (scrollView == self.pagingScrollView) [self settlePagingScrollView];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if (scrollView == self.pagingScrollView && !decelerate) [self settlePagingScrollView];
}

- (void)settlePagingScrollView
{
    CGFloat width = CGRectGetWidth(self.pagingScrollView.bounds);
    if (width <= 0.0) return;
    NSInteger page = (NSInteger)floor((self.pagingScrollView.contentOffset.x + width * 0.5) / width);
    NSInteger direction = page - 1;
    BOOL canMoveBackward = direction < 0 && self.selectedIndex != NSNotFound && self.selectedIndex > 0;
    BOOL canMoveForward = direction > 0 && self.selectedIndex != NSNotFound &&
        self.selectedIndex + 1 < [self.assets count];
    if (canMoveBackward || canMoveForward) {
        self.selectedIndex = (NSUInteger)((NSInteger)self.selectedIndex + direction);
        [self displaySelectedAsset];
        return;
    }
    self.pagingScrollView.contentOffset = CGPointMake(width, 0.0);
    if ([self.asset hasMotion] && !self.player) [self preparePlayer];
    [self resumePlaybackAfterInteractionIfNeeded];
    if (!self.playbackRequested) [self startAutomaticPlaybackIfNeeded];
}

- (void)displaySelectedAsset
{
    if (self.selectedIndex == NSNotFound || self.selectedIndex >= [self.assets count]) return;
    [self tearDownPlayer];
    self.asset = [self.assets objectAtIndex:self.selectedIndex];
    self.playbackMode = [self savedPlaybackMode];
    self.didAutoPlay = NO;

    [self reloadPagingImages];
    [self updateMetadata];
    [self updatePreviewChromeVisibility];
    if ([self.asset hasMotion] && !self.player) [self preparePlayer];
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
    [self setFullScreenPreview:NO animated:NO];
    if (self.delegate) [self.delegate assetDetailViewControllerDidRequestClose:self];
    else [self.navigationController popToRootViewControllerAnimated:YES];
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
        [self setFullScreenPreview:NO animated:NO];
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    if (self.selectedIndex >= [self.assets count]) self.selectedIndex = [self.assets count] - 1;
    [self displaySelectedAsset];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    self.imageLoadGeneration++;
    [self.imageQueue cancelAllOperations];
    [self.previewCache removeAllObjects];
    if ([self isViewLoaded] && !self.view.window) {
        [self tearDownPlayer];
        self.previousPage.imageView.image = nil;
        self.currentPage.imageView.image = nil;
        self.nextPage.imageView.image = nil;
    }
}

- (RLVAsset *)assetAtIndexOffset:(NSInteger)offset
{
    if (self.selectedIndex == NSNotFound) return nil;
    NSInteger index = (NSInteger)self.selectedIndex + offset;
    if (index < 0 || index >= (NSInteger)[self.assets count]) return nil;
    return [self.assets objectAtIndex:(NSUInteger)index];
}

- (CGFloat)maximumDisplayPixelSize
{
    CGRect bounds = [[UIScreen mainScreen] bounds];
    CGFloat scale = [[UIScreen mainScreen] scale];
    CGFloat dimension = MAX(CGRectGetWidth(bounds), CGRectGetHeight(bounds)) * scale;
    return MAX(1.0, ceil(dimension));
}

- (void)configurePage:(RLVZoomingImagePage *)page
             forAsset:(RLVAsset *)asset
          loadsDetail:(BOOL)loadsDetail
{
    [page resetZoom];
    page.representedAssetId = asset.assetId;
    if (!asset) {
        [page setImage:nil preservingGeometry:NO];
        return;
    }
    NSString *assetId = asset.assetId;
    NSString *previewCacheKey = [assetId stringByAppendingString:@".preview"];
    UIImage *previewImage = [self.previewCache objectForKey:previewCacheKey];
    if (previewImage) {
        [page setImage:previewImage preservingGeometry:YES];
        if (!loadsDetail) return;
    } else {
        UIImage *placeholder = asset.thumbnailURL
            ? [UIImage imageWithContentsOfFile:[asset.thumbnailURL path]] : nil;
        placeholder = [self presentationImageFromImage:placeholder asset:asset
                                      maximumPixelSize:[self maximumDisplayPixelSize]];
        [page setImage:placeholder preservingGeometry:YES];
    }

    NSUInteger generation = self.imageLoadGeneration;
    CGFloat maximumPixelSize = loadsDetail
        ? MAX((CGFloat)asset.width, (CGFloat)asset.height) : [self maximumDisplayPixelSize];
    __weak RLVAssetDetailViewController *controller = self;
    __weak RLVZoomingImagePage *targetPage = page;
    NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        @autoreleasepool {
            RLVAssetDetailViewController *strongController = controller;
            if (!strongController || generation != strongController.imageLoadGeneration) return;
            UIImage *image = [strongController displayImageForAsset:asset maximumPixelSize:maximumPixelSize];
            if (!image || generation != strongController.imageLoadGeneration) return;
            if (!loadsDetail) {
                CGImageRef imageRef = image.CGImage;
                NSUInteger cost = imageRef ? CGImageGetBytesPerRow(imageRef) * CGImageGetHeight(imageRef) : 0;
                [strongController.previewCache setObject:image forKey:previewCacheKey cost:cost];
            }
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                RLVAssetDetailViewController *mainController = controller;
                RLVZoomingImagePage *mainPage = targetPage;
                if (!mainController || !mainPage || generation != mainController.imageLoadGeneration) return;
                if (![mainPage.representedAssetId isEqualToString:assetId]) return;
                [mainPage setImage:image preservingGeometry:YES];
            }];
        }
    }];
    [self.imageQueue addOperation:operation];
}

- (void)reloadPagingImages
{
    self.imageLoadGeneration++;
    [self.imageQueue cancelAllOperations];
    [self configurePage:self.currentPage forAsset:[self assetAtIndexOffset:0] loadsDetail:YES];
    CGFloat width = CGRectGetWidth(self.pagingScrollView.bounds);
    if (width > 0.0) self.pagingScrollView.contentOffset = CGPointMake(width, 0.0);
    [self configurePage:self.previousPage forAsset:[self assetAtIndexOffset:-1] loadsDetail:NO];
    [self configurePage:self.nextPage forAsset:[self assetAtIndexOffset:1] loadsDetail:NO];
    self.pagingScrollView.scrollEnabled = [self.assets count] > 1;
    [self.view setNeedsLayout];
}

- (UIImage *)displayImageForAsset:(RLVAsset *)asset maximumPixelSize:(CGFloat)maximumPixelSize
{
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)asset.photoURL, NULL);
    // Adjacent pages decode near the viewport size; the current page requests
    // the source dimension so detail zoom never inherits the preview limit.
    CGFloat decodePixelSize = ceil(maximumPixelSize * 1.5);
    NSDictionary *options = @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize: @(decodePixelSize)
    };
    CGImageRef decodedImage = source
        ? CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options) : NULL;
    if (source) CFRelease(source);
    UIImage *image = decodedImage ? [UIImage imageWithCGImage:decodedImage scale:1.0 orientation:UIImageOrientationUp] : nil;
    if (decodedImage) CGImageRelease(decodedImage);
    return [self presentationImageFromImage:image asset:asset maximumPixelSize:maximumPixelSize];
}

- (UIImage *)presentationImageFromImage:(UIImage *)image
                                  asset:(RLVAsset *)asset
                       maximumPixelSize:(CGFloat)maximumPixelSize
{
    if (!image || image.size.width <= 0.0 || image.size.height <= 0.0) return nil;
    CGFloat landscapeRatio = 4.0 / 3.0;
    if ([asset.aspectRatio isEqualToString:@"1:1"]) landscapeRatio = 1.0;
    else if ([asset.aspectRatio isEqualToString:@"16:9"]) landscapeRatio = 16.0 / 9.0;
    CGRect aperture = CGRectMake(0.0, 0.0, image.size.width, image.size.height);
    BOOL usesNativeAspectRatio = [asset.aspectRatio isEqualToString:@"native"];
    // Motion metadata already applies the track's preferred transform. Its
    // display ratio is the canonical Live aperture, including for "native".
    if (asset.motionWidth > 0 && asset.motionHeight > 0) {
        CGFloat motionRatio = (CGFloat)asset.motionWidth / (CGFloat)asset.motionHeight;
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
    if (!usesNativeAspectRatio) {
        CGFloat targetRatio = CGRectGetWidth(aperture) >= CGRectGetHeight(aperture)
            ? landscapeRatio : 1.0 / landscapeRatio;
        CGFloat apertureRatio = CGRectGetWidth(aperture) / CGRectGetHeight(aperture);
        if (apertureRatio > targetRatio) {
            CGFloat centerX = CGRectGetMidX(aperture);
            aperture.size.width = CGRectGetHeight(aperture) * targetRatio;
            aperture.origin.x = centerX - aperture.size.width * 0.5;
        } else {
            CGFloat centerY = CGRectGetMidY(aperture);
            aperture.size.height = CGRectGetWidth(aperture) / targetRatio;
            aperture.origin.y = centerY - aperture.size.height * 0.5;
        }
    }
    CGFloat outputScale = MIN(1.0, maximumPixelSize / MAX(CGRectGetWidth(aperture), CGRectGetHeight(aperture)));
    CGSize outputSize = CGSizeMake(MAX(1.0, floor(CGRectGetWidth(aperture) * outputScale)),
        MAX(1.0, floor(CGRectGetHeight(aperture) * outputScale)));
    UIGraphicsBeginImageContextWithOptions(outputSize, YES, 1.0);
    CGFloat drawScale = outputSize.width / CGRectGetWidth(aperture);
    [image drawInRect:CGRectMake(-aperture.origin.x * drawScale, -aperture.origin.y * drawScale,
        image.size.width * drawScale, image.size.height * drawScale)];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result ?: image;
}

- (void)preparePlayer
{
    if (self.player || ![self.asset hasMotion]) return;
    self.player = [AVPlayer playerWithURL:self.asset.motionURL];
    self.player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.playerLayer.hidden = YES;
    self.playerLayerCanBeShown = NO;
    self.playerLayer.frame = self.currentPage.imageView.bounds;
    [self.currentPage.imageView.layer addSublayer:self.playerLayer];
    [self.playerLayer addObserver:self forKeyPath:@"readyForDisplay"
                         options:NSKeyValueObservingOptionNew context:RLVPlayerLayerReadyContext];
    [self.player.currentItem addObserver:self forKeyPath:@"status"
                                 options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                                 context:RLVPlayerItemStatusContext];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemDidReachEnd:)
        name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];

    __weak RLVAssetDetailViewController *controller = self;
    __weak AVPlayer *observedPlayer = self.player;
    __weak AVPlayerItem *observedItem = self.player.currentItem;
    self.playbackTimeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 20)
        queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
            if (controller.player == observedPlayer && controller.player.currentItem == observedItem &&
                controller.playbackRequested && [controller canContinuePlayback] &&
                !controller.playbackEndTransitionPending &&
                controller.playbackMode == RLVLivePlaybackModeBounce && controller.playingBackward &&
                CMTimeGetSeconds(time) <= 0.05) {
                controller.playbackEndTransitionPending = YES;
                controller.playingBackward = NO;
                NSUInteger generation = controller.playbackGeneration;
                [observedPlayer seekToTime:kCMTimeZero completionHandler:^(BOOL finished) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (finished && controller.player == observedPlayer &&
                            controller.player.currentItem == observedItem &&
                            controller.playbackGeneration == generation && controller.playbackRequested &&
                            controller.playbackMode == RLVLivePlaybackModeBounce &&
                            [controller canContinuePlayback]) {
                            controller.playbackEndTransitionPending = NO;
                            [observedPlayer play];
                        }
                    });
                }];
            }
        }];
}

- (void)tearDownPlayer
{
    [self stopPlaybackAndShowStillResetPosition:NO];
    if (self.playbackTimeObserver) {
        [self.player removeTimeObserver:self.playbackTimeObserver];
        self.playbackTimeObserver = nil;
    }
    if (self.player.currentItem) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification
            object:self.player.currentItem];
        [self.player.currentItem removeObserver:self forKeyPath:@"status" context:RLVPlayerItemStatusContext];
    }
    if (self.playerLayer) {
        [self.playerLayer removeObserver:self forKeyPath:@"readyForDisplay" context:RLVPlayerLayerReadyContext];
    }
    [self.playerLayer removeFromSuperlayer];
    self.playerLayer = nil;
    self.player = nil;
}

- (void)startAutomaticPlaybackIfNeeded
{
    if (![self.asset hasMotion] || self.playbackRequested || !RLVLibraryAutomaticallyPlaysLivePhotos()) return;
    if (self.playbackMode == RLVLivePlaybackModeLoop || self.playbackMode == RLVLivePlaybackModeBounce) {
        [self startPlayback];
    } else if (self.playbackMode == RLVLivePlaybackModeLive && !self.didAutoPlay) {
        self.didAutoPlay = YES;
        [self startPlayback];
    }
}

- (void)startPlayback
{
    if (![self.asset hasMotion] || (self.playbackMode == RLVLivePlaybackModeStill && !self.livePressActive) ||
        !self.view.window || self.navigationController.topViewController != self ||
        [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    if (!self.player) [self preparePlayer];
    if (!self.player) return;
    self.interactionResumeIntent = RLVPlaybackIntentNone;
    self.playbackGeneration++;
    self.playbackRequested = YES;
    self.playerLayerCanBeShown = NO;
    self.playbackEndTransitionPending = NO;
    self.playingBackward = NO;
    self.playbackIntent = RLVPlaybackIntentFromBeginning;
    [self.player cancelPendingPrerolls];
    [self updatePlayerLayerVisibility];
    [self processPlaybackIntentIfReady];
    [self setBadgeActive:YES];
}

- (void)returnToStillPhoto
{
    [self stopPlaybackAndShowStillResetPosition:YES];
}

- (void)stopPlaybackAndShowStillResetPosition:(BOOL)resetPosition
{
    self.livePressActive = NO;
    self.interactionResumeIntent = RLVPlaybackIntentNone;
    self.playbackGeneration++;
    self.playbackIntent = RLVPlaybackIntentNone;
    self.playbackRequested = NO;
    self.playerLayerCanBeShown = NO;
    self.playbackEndTransitionPending = NO;
    [self.player cancelPendingPrerolls];
    [self.player pause];
    if (resetPosition && self.player.currentItem.status == AVPlayerItemStatusReadyToPlay) {
        [self.player seekToTime:kCMTimeZero];
    }
    self.playingBackward = NO;
    [self updatePlayerLayerVisibility];
    [self setBadgeActive:NO];
}

- (BOOL)canContinuePlayback
{
    return self.player && [self.asset hasMotion] && self.view.window &&
        self.navigationController.topViewController == self &&
        [UIApplication sharedApplication].applicationState == UIApplicationStateActive;
}

- (void)processPlaybackIntentIfReady
{
    if (!self.playbackRequested || self.playbackIntent == RLVPlaybackIntentNone || !self.player.currentItem) return;
    AVPlayerItemStatus status = self.player.currentItem.status;
    if (status == AVPlayerItemStatusUnknown) return;
    if (status == AVPlayerItemStatusFailed) {
        [self returnToStillPhoto];
        return;
    }

    RLVPlaybackIntent intent = self.playbackIntent;
    self.playbackIntent = RLVPlaybackIntentNone;
    NSUInteger generation = self.playbackGeneration;
    AVPlayer *requestedPlayer = self.player;
    if (intent == RLVPlaybackIntentResume) {
        self.playerLayerCanBeShown = YES;
        [self startPreparedPlaybackIfPossible];
        return;
    }

    __weak RLVAssetDetailViewController *controller = self;
    [requestedPlayer seekToTime:kCMTimeZero completionHandler:^(BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            RLVAssetDetailViewController *strongController = controller;
            if (!finished || !strongController || strongController.player != requestedPlayer ||
                strongController.playbackGeneration != generation || !strongController.playbackRequested) return;
            [requestedPlayer prerollAtRate:1.0 completionHandler:^(BOOL prerollFinished) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    RLVAssetDetailViewController *readyController = controller;
                    if (!prerollFinished || !readyController || readyController.player != requestedPlayer ||
                        readyController.playbackGeneration != generation || !readyController.playbackRequested) return;
                    readyController.playerLayerCanBeShown = YES;
                    [readyController startPreparedPlaybackIfPossible];
                });
            }];
        });
    }];
}

- (void)startPreparedPlaybackIfPossible
{
    if (self.playbackRequested && ![self canContinuePlayback]) {
        [self stopPlaybackAndShowStillResetPosition:NO];
        return;
    }
    if (!self.playbackRequested || self.playbackEndTransitionPending ||
        !self.playerLayerCanBeShown || !self.playerLayer.readyForDisplay) {
        [self updatePlayerLayerVisibility];
        return;
    }
    [self updatePlayerLayerVisibility];
    if (self.playingBackward) self.player.rate = -1.0;
    else [self.player play];
}

- (void)updatePlayerLayerVisibility
{
    BOOL visible = self.playbackRequested && self.playerLayerCanBeShown && self.playerLayer.readyForDisplay;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.playerLayer.hidden = !visible;
    [CATransaction commit];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    (void)keyPath;
    (void)change;
    if (context == RLVPlayerItemStatusContext) {
        if (![NSThread isMainThread]) {
            __weak RLVAssetDetailViewController *controller = self;
            AVPlayerItem *observedItem = object;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (observedItem != controller.player.currentItem) return;
                if (observedItem.status == AVPlayerItemStatusFailed) [controller returnToStillPhoto];
                else [controller processPlaybackIntentIfReady];
            });
            return;
        }
        if (object == self.player.currentItem) {
            if (self.player.currentItem.status == AVPlayerItemStatusFailed) [self returnToStillPhoto];
            else [self processPlaybackIntentIfReady];
        }
        return;
    }
    if (context == RLVPlayerLayerReadyContext) {
        if (![NSThread isMainThread]) {
            __weak RLVAssetDetailViewController *controller = self;
            dispatch_async(dispatch_get_main_queue(), ^{ [controller startPreparedPlaybackIfPossible]; });
            return;
        }
        if (object == self.playerLayer) [self startPreparedPlaybackIfPossible];
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)livePhotoPressed:(UILongPressGestureRecognizer *)recognizer
{
    if (![self.asset hasMotion]) return;
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        self.livePressActive = YES;
        [self startPlayback];
    } else if (recognizer.state == UIGestureRecognizerStateEnded ||
        recognizer.state == UIGestureRecognizerStateCancelled ||
        recognizer.state == UIGestureRecognizerStateFailed) {
        self.livePressActive = NO;
        [self returnToStillPhoto];
    }
}

- (void)playerItemDidReachEnd:(NSNotification *)notification
{
    if (![NSThread isMainThread]) {
        __weak RLVAssetDetailViewController *controller = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [controller playerItemDidReachEnd:notification]; });
        return;
    }
    if (!self.playbackRequested || ![self canContinuePlayback] ||
        notification.object != self.player.currentItem ||
        self.player.currentItem.status != AVPlayerItemStatusReadyToPlay) return;
    if (self.playbackMode == RLVLivePlaybackModeLoop) {
        self.playbackEndTransitionPending = YES;
        NSUInteger generation = self.playbackGeneration;
        AVPlayer *loopPlayer = self.player;
        AVPlayerItem *loopItem = self.player.currentItem;
        __weak RLVAssetDetailViewController *controller = self;
        [loopPlayer seekToTime:kCMTimeZero completionHandler:^(BOOL finished) {
            dispatch_async(dispatch_get_main_queue(), ^{
                RLVAssetDetailViewController *strongController = controller;
                if (finished && strongController.player == loopPlayer &&
                    strongController.player.currentItem == loopItem &&
                    strongController.playbackGeneration == generation && strongController.playbackRequested &&
                    strongController.playbackMode == RLVLivePlaybackModeLoop &&
                    [strongController canContinuePlayback]) {
                    strongController.playbackEndTransitionPending = NO;
                    [loopPlayer play];
                }
            });
        }];
    } else if (self.playbackMode == RLVLivePlaybackModeBounce && self.player.currentItem.canPlayReverse) {
        self.playbackEndTransitionPending = YES;
        self.playingBackward = YES;
        NSUInteger generation = self.playbackGeneration;
        __weak RLVAssetDetailViewController *controller = self;
        AVPlayer *bouncePlayer = self.player;
        AVPlayerItem *bounceItem = self.player.currentItem;
        [bouncePlayer seekToTime:bounceItem.duration completionHandler:^(BOOL finished) {
            dispatch_async(dispatch_get_main_queue(), ^{
                RLVAssetDetailViewController *strongController = controller;
                if (finished && strongController.player == bouncePlayer &&
                    strongController.player.currentItem == bounceItem &&
                    strongController.playbackGeneration == generation && strongController.playbackRequested &&
                    strongController.playbackMode == RLVLivePlaybackModeBounce && strongController.playingBackward &&
                    [strongController canContinuePlayback]) {
                    strongController.playbackEndTransitionPending = NO;
                    bouncePlayer.rate = -1.0;
                }
            });
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
    AVPlayerItem *item = self.player.currentItem;
    if (buttonIndex == RLVLivePlaybackModeBounce &&
        ((item.status == AVPlayerItemStatusReadyToPlay && !item.canPlayReverse) ||
         item.status == AVPlayerItemStatusFailed)) {
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

    self.livePressGestureRecognizer.enabled = [self.asset hasMotion];
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
    self.pagingScrollView.delegate = nil;
    self.previousPage.delegate = nil;
    self.currentPage.delegate = nil;
    self.nextPage.delegate = nil;
    [self.imageQueue cancelAllOperations];
    [self tearDownPlayer];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@synthesize assets = _assets;
@synthesize selectedIndex = _selectedIndex;
@synthesize asset = _asset;
@synthesize pagingScrollView = _pagingScrollView;
@synthesize previousPage = _previousPage;
@synthesize currentPage = _currentPage;
@synthesize nextPage = _nextPage;
@synthesize previewCache = _previewCache;
@synthesize imageQueue = _imageQueue;
@synthesize imageLoadGeneration = _imageLoadGeneration;
@synthesize metadataLabel = _metadataLabel;
@synthesize liveBadge = _liveBadge;
@synthesize toolbar = _toolbar;
@synthesize player = _player;
@synthesize playerLayer = _playerLayer;
@synthesize playbackTimeObserver = _playbackTimeObserver;
@synthesize playbackMode = _playbackMode;
@synthesize playingBackward = _playingBackward;
@synthesize didAutoPlay = _didAutoPlay;
@synthesize playbackRequested = _playbackRequested;
@synthesize playerLayerCanBeShown = _playerLayerCanBeShown;
@synthesize playbackEndTransitionPending = _playbackEndTransitionPending;
@synthesize playbackGeneration = _playbackGeneration;
@synthesize playbackIntent = _playbackIntent;
@synthesize interactionResumeIntent = _interactionResumeIntent;
@synthesize livePressGestureRecognizer = _livePressGestureRecognizer;
@synthesize fullScreenTapGestureRecognizer = _fullScreenTapGestureRecognizer;
@synthesize fullScreenPreview = _fullScreenPreview;
@synthesize metadataWasVisibleBeforeFullScreen = _metadataWasVisibleBeforeFullScreen;
@synthesize livePressActive = _livePressActive;
@synthesize delegate = _delegate;

@end
