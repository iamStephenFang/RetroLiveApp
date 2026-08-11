#import <UIKit/UIKit.h>

FOUNDATION_EXPORT void RLVPrepareViewsForAutoLayout(NSArray *views);
FOUNDATION_EXPORT void RLVAddVisualConstraints(UIView *container, NSDictionary *views, NSArray *formats);
FOUNDATION_EXPORT void RLVPinViewToEdges(UIView *view, UIView *container);
FOUNDATION_EXPORT void RLVAlignViews(UIView *container, UIView *firstView, NSLayoutAttribute firstAttribute,
                                     UIView *secondView, NSLayoutAttribute secondAttribute);
FOUNDATION_EXPORT void RLVInstallCameraLayout(UIView *rootView, UIView *previewView,
    UIView *topChromeView, UIView *bottomChromeView, UIView *flashButton, UIView *livePhotoButton,
    UIView *aspectRatioButton, UIView *thumbnailButton, UIView *shutterButton, CGSize shutterSize,
    CGFloat bottomHeight, CGFloat sideControlSize, UIView *cameraSwitchButton);
