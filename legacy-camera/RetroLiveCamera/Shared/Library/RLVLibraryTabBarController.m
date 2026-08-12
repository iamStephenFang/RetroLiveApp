#import "RLVLibraryTabBarController.h"
#import "RLVAssetDetailViewController.h"
#import "RLVLibraryViewController.h"
#import "RLVTransferViewController.h"

static UIImage *RLVTemplateTabImage(void (^drawing)(CGContextRef context))
{
    CGSize size = CGSizeMake(26.0, 26.0);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
    CGContextSetStrokeColorWithColor(context, [UIColor whiteColor].CGColor);
    drawing(context);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if ([image respondsToSelector:@selector(imageWithRenderingMode:)]) {
        image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    return image;
}

static UIImage *RLVLibraryTabImage(void)
{
    return RLVTemplateTabImage(^(CGContextRef context) {
        for (NSUInteger row = 0; row < 2; row++) {
            for (NSUInteger column = 0; column < 2; column++) {
                CGRect square = CGRectMake(3.0 + column * 11.0, 3.0 + row * 11.0, 9.0, 9.0);
                CGContextFillRect(context, square);
            }
        }
    });
}

static UIImage *RLVTransferTabImage(void)
{
    return RLVTemplateTabImage(^(CGContextRef context) {
        CGContextSetLineWidth(context, 1.8);
        CGContextStrokeRect(context, CGRectMake(2.5, 4.0, 7.0, 15.5));
        CGContextStrokeRect(context, CGRectMake(16.5, 6.5, 7.0, 15.5));
        CGContextSetLineWidth(context, 2.0);
        CGContextMoveToPoint(context, 10.5, 9.0);
        CGContextAddLineToPoint(context, 15.0, 9.0);
        CGContextAddLineToPoint(context, 13.0, 7.0);
        CGContextMoveToPoint(context, 15.5, 17.0);
        CGContextAddLineToPoint(context, 11.0, 17.0);
        CGContextAddLineToPoint(context, 13.0, 19.0);
        CGContextStrokePath(context);
    });
}

@interface RLVLibraryTabBarController () <RLVLibraryViewControllerDelegate,
    RLVAssetDetailViewControllerDelegate>
@property (nonatomic, assign, getter=isTabBarManuallyHidden) BOOL tabBarManuallyHidden;
@property (nonatomic, assign) BOOL didShowInitialDetail;
@property (nonatomic, strong) NSArray *initialAssets;
@property (nonatomic, assign) NSUInteger initialSelectedIndex;
@property (nonatomic, strong) UINavigationController *libraryNavigationController;
- (void)setTabBarHidden:(BOOL)hidden animated:(BOOL)animated;
@end

@implementation RLVLibraryTabBarController

- (id)init
{
    return [self initWithAssets:nil selectedIndex:NSNotFound];
}

- (id)initWithAssets:(NSArray *)assets selectedIndex:(NSUInteger)selectedIndex
{
    self = [super init];
    if (self) {
        RLVLibraryViewController *library = [[RLVLibraryViewController alloc] init];
        library.delegate = self;
        RLVTransferViewController *transfer = [[RLVTransferViewController alloc] init];
        library.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"library.title", nil)
            image:RLVLibraryTabImage() tag:0];
        transfer.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"transfer.title", nil)
            image:RLVTransferTabImage() tag:1];

        UINavigationController *libraryNavigation = [[UINavigationController alloc]
            initWithRootViewController:library];
        UINavigationController *transferNavigation = [[UINavigationController alloc]
            initWithRootViewController:transfer];
        libraryNavigation.navigationBar.barStyle = UIBarStyleBlack;
        transferNavigation.navigationBar.barStyle = UIBarStyleBlack;

        library.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close:)];
        transfer.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close:)];
        self.viewControllers = @[libraryNavigation, transferNavigation];
        self.libraryNavigationController = libraryNavigation;
        self.initialAssets = [assets copy];
        self.initialSelectedIndex = selectedIndex;
        self.view.backgroundColor = [UIColor blackColor];
        UIColor *accentColor = [UIColor colorWithRed:1.0 green:0.78 blue:0.0 alpha:1.0];
        if ([self.tabBar respondsToSelector:@selector(setBarTintColor:)]) {
            // iOS 7 and later: dark translucent material with a tinted
            // selected item.
            self.tabBar.barStyle = UIBarStyleBlack;
            self.tabBar.tintColor = accentColor;
            self.tabBar.barTintColor = [UIColor blackColor];
            self.tabBar.translucent = YES;
        } else {
            // iOS 6: tintColor controls the tab bar background rather than
            // the selected item. selectedImageTintColor is available on the
            // iOS 6 runtime and preserves the yellow selection treatment.
            self.tabBar.tintColor = [UIColor blackColor];
            self.tabBar.selectedImageTintColor = accentColor;
        }
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (!self.didShowInitialDetail && [self.initialAssets count] > 0 &&
        self.initialSelectedIndex < [self.initialAssets count]) {
        self.didShowInitialDetail = YES;
        [self showDetailForAssets:self.initialAssets selectedIndex:self.initialSelectedIndex animated:NO];
        self.initialAssets = nil;
    }
}

- (void)showDetailForAssets:(NSArray *)assets selectedIndex:(NSUInteger)selectedIndex animated:(BOOL)animated
{
    if ([assets count] == 0 || selectedIndex >= [assets count]) return;
    RLVAssetDetailViewController *detail = [[RLVAssetDetailViewController alloc]
        initWithAssets:assets selectedIndex:selectedIndex];
    detail.delegate = self;
    detail.hidesBottomBarWhenPushed = YES;
    [self.libraryNavigationController pushViewController:detail animated:animated];
}

- (void)libraryViewController:(RLVLibraryViewController *)controller
              didSelectAssets:(NSArray *)assets
                selectedIndex:(NSUInteger)selectedIndex
{
    (void)controller;
    [self showDetailForAssets:assets selectedIndex:selectedIndex animated:YES];
}

- (void)libraryViewController:(RLVLibraryViewController *)controller
    didChangeSelectingAssets:(BOOL)selectingAssets
{
    (void)controller;
    [self setTabBarHidden:selectingAssets animated:YES];
}

- (void)assetDetailViewControllerDidRequestClose:(RLVAssetDetailViewController *)controller
{
    (void)controller;
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)setTabBarHidden:(BOOL)hidden animated:(BOOL)animated
{
    if (self.isTabBarManuallyHidden == hidden) return;
    self.tabBarManuallyHidden = hidden;
    self.tabBar.hidden = NO;
    void (^changes)(void) = ^{
        [self layoutTabBarForHiddenState:hidden];
    };
    void (^completion)(BOOL finished) = ^(BOOL finished) {
        (void)finished;
        self.tabBar.hidden = hidden;
        [self.view setNeedsLayout];
    };
    if (animated) [UIView animateWithDuration:0.2 animations:changes completion:completion];
    else {
        changes();
        completion(YES);
    }
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    if (self.isTabBarManuallyHidden) {
        [self layoutTabBarForHiddenState:YES];
        self.tabBar.hidden = YES;
    }
}

- (void)layoutTabBarForHiddenState:(BOOL)hidden
{
    CGFloat tabBarHeight = CGRectGetHeight(self.tabBar.frame);
    if (tabBarHeight <= 0.0) tabBarHeight = 49.0;
    CGRect bounds = self.view.bounds;
    CGRect tabBarFrame = self.tabBar.frame;
    tabBarFrame.origin.y = CGRectGetHeight(bounds) - (hidden ? 0.0 : tabBarHeight);
    tabBarFrame.size.height = tabBarHeight;
    self.tabBar.frame = tabBarFrame;

    BOOL tabBarOverlaysContent = [self.tabBar respondsToSelector:@selector(isTranslucent)] &&
        self.tabBar.isTranslucent;
    if (hidden || tabBarOverlaysContent) {
        // iOS 7 and later: translucent bars overlay full-height content. This
        // also keeps the grid height stable during batch-mode transitions.
        self.selectedViewController.view.frame = bounds;
    } else {
        // iOS 6: the tab bar is opaque, so visible content ends above it.
        self.selectedViewController.view.frame = CGRectMake(0.0, 0.0,
            CGRectGetWidth(bounds), CGRectGetMinY(tabBarFrame));
    }
}

- (void)close:(id)sender
{
    (void)sender;
    [self dismissViewControllerAnimated:YES completion:nil];
}

@synthesize tabBarManuallyHidden = _tabBarManuallyHidden;
@synthesize didShowInitialDetail = _didShowInitialDetail;
@synthesize initialAssets = _initialAssets;
@synthesize initialSelectedIndex = _initialSelectedIndex;
@synthesize libraryNavigationController = _libraryNavigationController;

@end
