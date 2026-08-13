#import "RLVAppDelegate.h"
#import "RLVOnboardingViewController.h"
#if RLV_CLASSIC
#import "RLVClassicCameraViewController.h"
#else
#import "RLVLegacyCameraViewController.h"
#endif

static NSString * const RLVOnboardingCompletedVersionKey = @"RLVOnboardingCompletedVersion";
static NSInteger const RLVCurrentOnboardingVersion = 1;

@interface RLVAppDelegate () <RLVOnboardingViewControllerDelegate>
- (UIViewController *)cameraViewController;
- (void)showCameraAnimated:(BOOL)animated;
@end

@implementation RLVAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    (void)application;
    (void)launchOptions;

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    NSInteger completedVersion = [[NSUserDefaults standardUserDefaults] integerForKey:RLVOnboardingCompletedVersionKey];
    if (completedVersion < RLVCurrentOnboardingVersion) {
        RLVOnboardingViewController *onboardingViewController = [[RLVOnboardingViewController alloc] init];
        onboardingViewController.delegate = self;
        self.window.rootViewController = onboardingViewController;
    } else {
        self.window.rootViewController = [self cameraViewController];
    }
    [self.window makeKeyAndVisible];
    return YES;
}

- (UIViewController *)cameraViewController
{
#if RLV_CLASSIC
    return [[RLVClassicCameraViewController alloc] init];
#else
    return [[RLVLegacyCameraViewController alloc] init];
#endif
}

- (void)showCameraAnimated:(BOOL)animated
{
    UIViewController *cameraViewController = [self cameraViewController];
    if (!animated) {
        self.window.rootViewController = cameraViewController;
        return;
    }
    [UIView transitionWithView:self.window duration:0.35 options:UIViewAnimationOptionTransitionCrossDissolve
        animations:^{ self.window.rootViewController = cameraViewController; } completion:NULL];
}

- (void)onboardingViewControllerDidFinish:(RLVOnboardingViewController *)viewController
{
    (void)viewController;
    [[NSUserDefaults standardUserDefaults] setInteger:RLVCurrentOnboardingVersion forKey:RLVOnboardingCompletedVersionKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self showCameraAnimated:YES];
}

@synthesize window = _window;

@end
