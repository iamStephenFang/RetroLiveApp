#import <UIKit/UIKit.h>

@interface RLVShutterButton : UIControl
@property (nonatomic, assign, getter=isCapturing) BOOL capturing;
@end

@interface RLVLegacyShutterButton : RLVShutterButton
@end

@interface RLVClassicShutterButton : RLVShutterButton
@end
