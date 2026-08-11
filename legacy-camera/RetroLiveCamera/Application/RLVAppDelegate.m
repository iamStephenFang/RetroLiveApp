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
    UIViewController *cameraViewController = [[RLVClassicCameraViewController alloc] init];
#else
    UIViewController *cameraViewController = [[RLVLegacyCameraViewController alloc] init];
#endif
    self.window.rootViewController = cameraViewController;
    [self.window makeKeyAndVisible];
    return YES;
}

@synthesize window = _window;

@end
