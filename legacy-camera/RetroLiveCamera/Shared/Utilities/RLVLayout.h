#import <UIKit/UIKit.h>

/// Disables autoresizing-mask constraint translation for every supplied view.
FOUNDATION_EXPORT void RLVPrepareViewsForAutoLayout(NSArray *views);
/// Adds each visual-format constraint to container using the supplied view dictionary.
FOUNDATION_EXPORT void RLVAddVisualConstraints(UIView *container, NSDictionary *views, NSArray *formats);
/// Constrains all four edges of view to container.
FOUNDATION_EXPORT void RLVPinViewToEdges(UIView *view, UIView *container);
/// Aligns one layout attribute from each view inside container.
FOUNDATION_EXPORT void RLVAlignViews(UIView *container, UIView *firstView, NSLayoutAttribute firstAttribute,
                                     UIView *secondView, NSLayoutAttribute secondAttribute);
/// Measures localized text using the best API available on the running OS.
FOUNDATION_EXPORT CGSize RLVTextSizeWithFont(NSString *text, UIFont *font);
/// Returns whether the running OS uses the iOS 7-and-later flat visual language.
FOUNDATION_EXPORT BOOL RLVUsesFlatInterfaceStyle(void);
/// Returns a template-like image rendered with a concrete tint color on supported systems.
FOUNDATION_EXPORT UIImage *RLVTintedInterfaceImage(UIImage *image, UIColor *color);
/// Creates the Live control background for the requested OS style and active state.
FOUNDATION_EXPORT UIImage *RLVLiveControlBackgroundImage(BOOL flatInterface, BOOL active);
/// Creates a legacy metal-style button with the shared sizing and highlight behavior.
FOUNDATION_EXPORT UIButton *RLVCreateMetalButton(void);
/// Installs the complete camera chrome layout using measured control sizes.
FOUNDATION_EXPORT void RLVInstallCameraLayout(UIView *rootView, UIView *previewView,
    UIView *topChromeView, UIView *bottomChromeView, UIView *flashButton, UIView *livePhotoButton,
    UIView *aspectRatioButton, UIView *thumbnailButton, UIView *shutterButton, CGSize shutterSize,
    CGFloat bottomHeight, CGFloat sideControlSize, UIView *cameraSwitchButton);
