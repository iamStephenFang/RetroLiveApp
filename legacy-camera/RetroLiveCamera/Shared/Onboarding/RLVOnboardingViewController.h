#import <UIKit/UIKit.h>

@class RLVOnboardingViewController;

@protocol RLVOnboardingViewControllerDelegate <NSObject>
- (void)onboardingViewControllerDidFinish:(RLVOnboardingViewController *)viewController;
@end

@interface RLVOnboardingViewController : UIViewController

@property (nonatomic, weak) id<RLVOnboardingViewControllerDelegate> delegate;

@end
