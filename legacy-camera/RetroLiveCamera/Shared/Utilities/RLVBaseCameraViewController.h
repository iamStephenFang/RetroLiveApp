#import "RLVCameraOrientationCoordinator.h"
#import "RLVCaptureController.h"
#import <UIKit/UIKit.h>

@class RLVDeviceCapabilities;
@class RLVShutterButton;

@protocol RLVFocusPreviewViewDelegate;

@interface RLVFocusPreviewView : UIView
@property (nonatomic, assign) id<RLVFocusPreviewViewDelegate> focusDelegate;
@end

@protocol RLVFocusPreviewViewDelegate <NSObject>
- (void)focusPreviewViewDidRequestCenterFocus:(RLVFocusPreviewView *)previewView;
@end

@interface RLVBaseCameraViewController : UIViewController <RLVCaptureControllerDelegate,
    RLVCameraOrientationCoordinatorDelegate, RLVFocusPreviewViewDelegate, UIActionSheetDelegate>

@property (nonatomic, strong) UIView *previewView;
@property (nonatomic, strong) UIView *topChromeView;
@property (nonatomic, strong) UIView *bottomChromeView;
@property (nonatomic, strong) RLVShutterButton *shutterButton;
@property (nonatomic, strong) UIButton *thumbnailButton;
@property (nonatomic, strong) UIButton *flashButton;
@property (nonatomic, strong) UIButton *livePhotoButton;
@property (nonatomic, strong) UIButton *cameraSwitchButton;
@property (nonatomic, strong) UIButton *aspectRatioButton;
@property (nonatomic, strong) NSArray *rotatingControls;
@property (nonatomic, strong, readonly) RLVDeviceCapabilities *capabilities;

@end
