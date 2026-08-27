#import "RLVCameraOrientationCoordinator.h"
#import "RLVCaptureController.h"
#import <UIKit/UIKit.h>

@class RLVDeviceCapabilities;
@class RLVShutterButton;

@protocol RLVFocusPreviewViewDelegate;

/// Preview surface that distinguishes tap-to-focus from a centered accessibility action.
@interface RLVFocusPreviewView : UIView
@property (nonatomic, assign) id<RLVFocusPreviewViewDelegate> focusDelegate;
@end

@protocol RLVFocusPreviewViewDelegate <NSObject>
/// Requests focus at the preview center and returns whether the request was accepted.
- (BOOL)focusPreviewViewDidRequestCenterFocus:(RLVFocusPreviewView *)previewView;
@end

/// Shared camera orchestration for the Legacy and Classic presentations.
/// Subclasses own era-specific styling while capture behavior remains centralized here.
@interface RLVBaseCameraViewController : UIViewController <RLVCaptureControllerDelegate,
    RLVCameraOrientationCoordinatorDelegate, RLVFocusPreviewViewDelegate>

@property (nonatomic, strong) UIView *previewView;
@property (nonatomic, strong) UIView *topChromeView;
@property (nonatomic, strong) UIView *bottomChromeView;
@property (nonatomic, strong) RLVShutterButton *shutterButton;
@property (nonatomic, strong) UIButton *thumbnailButton;
@property (nonatomic, strong) UIButton *flashButton;
@property (nonatomic, strong) UIButton *livePhotoButton;
@property (nonatomic, strong) UIButton *cameraSwitchButton;
@property (nonatomic, strong) UIButton *aspectRatioButton;
/// Chrome controls that follow controlTransform; the preview and thumbnail use separate orientation rules.
@property (nonatomic, strong) NSArray *rotatingControls;
/// Hardware capability snapshot used to enable or degrade optional camera features.
@property (nonatomic, strong, readonly) RLVDeviceCapabilities *capabilities;

@end
