#import "RLVAppDelegate.h"
#import "RLVCameraViewController.h"

@implementation RLVAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    (void)application;
    (void)launchOptions;

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.cameraViewController = [[RLVCameraViewController alloc] init];
    self.window.rootViewController = self.cameraViewController;
    [self.window makeKeyAndVisible];
    return YES;
}

@synthesize window = _window;
@synthesize cameraViewController = _cameraViewController;

@end
