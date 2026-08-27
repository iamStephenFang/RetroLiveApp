#import <UIKit/UIKit.h>

/// Shutter control that exposes a capture-in-progress visual state.
@interface RLVShutterButton : UIControl
@property (nonatomic, assign, getter=isCapturing) BOOL capturing;
@end

/// iOS 6-era shutter appearance.
@interface RLVLegacyShutterButton : RLVShutterButton
@end

/// iOS 8-era shutter appearance.
@interface RLVClassicShutterButton : RLVShutterButton
@end
