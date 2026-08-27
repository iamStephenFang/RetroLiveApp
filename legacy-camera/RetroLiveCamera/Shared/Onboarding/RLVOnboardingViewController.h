#import <UIKit/UIKit.h>

@class RLVOnboardingViewController;

@protocol RLVOnboardingViewControllerDelegate <NSObject>
/// Reports explicit completion so the app can persist and transition out of onboarding.
- (void)onboardingViewControllerDidFinish:(RLVOnboardingViewController *)viewController;
@end

/// First-run explanation of the camera-to-importer workflow.
@interface RLVOnboardingViewController : UIViewController

@property (nonatomic, weak) id<RLVOnboardingViewControllerDelegate> delegate;

@end
