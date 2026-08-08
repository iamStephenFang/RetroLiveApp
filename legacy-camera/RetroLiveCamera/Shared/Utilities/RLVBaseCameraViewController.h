#import "RLVCameraOrientationCoordinator.h"
#import "RLVCaptureController.h"
#import <UIKit/UIKit.h>

@class RLVDeviceCapabilities;
@class RLVShutterButton;

@interface RLVBaseCameraViewController : UIViewController <RLVCaptureControllerDelegate, RLVCameraOrientationCoordinatorDelegate>

@property (nonatomic, strong) UIView *previewView;
@property (nonatomic, strong) UIView *topChromeView;
@property (nonatomic, strong) UIView *bottomChromeView;
@property (nonatomic, strong) RLVShutterButton *shutterButton;
@property (nonatomic, strong) UIButton *thumbnailButton;
@property (nonatomic, strong) UIButton *flashButton;
@property (nonatomic, strong) UIButton *cameraSwitchButton;
@property (nonatomic, strong) NSArray *rotatingControls;
@property (nonatomic, strong, readonly) RLVDeviceCapabilities *capabilities;

- (void)configureCameraActions;
- (void)updateThumbnail;

@end
