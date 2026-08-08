#import "RLVAppDelegate.h"
#if RLV_CLASSIC
#import "RLVClassicCameraViewController.h"
#else
#import "RLVLegacyCameraViewController.h"
#endif

@implementation RLVAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    (void)application;
    (void)launchOptions;

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
#if RLV_CLASSIC
    self.cameraViewController = [[RLVClassicCameraViewController alloc] init];
#else
    self.cameraViewController = [[RLVLegacyCameraViewController alloc] init];
#endif
    self.navigationController = [[UINavigationController alloc] initWithRootViewController:self.cameraViewController];
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.window.rootViewController = self.navigationController;
    [self.window makeKeyAndVisible];
    return YES;
}

@synthesize window = _window;
@synthesize cameraViewController = _cameraViewController;
@synthesize navigationController = _navigationController;

@end
