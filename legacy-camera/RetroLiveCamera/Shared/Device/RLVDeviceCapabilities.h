#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

@interface RLVDeviceCapabilities : NSObject

@property (nonatomic, copy, readonly) NSString *systemVersion;
@property (nonatomic, copy, readonly) NSString *modelIdentifier;
@property (nonatomic, copy, readonly) NSString *architecture;
@property (nonatomic, assign, readonly) BOOL supportsRearCamera;
@property (nonatomic, assign, readonly) BOOL supportsFrontCamera;
@property (nonatomic, assign, readonly) BOOL supportsFlash;
@property (nonatomic, assign, readonly) BOOL supportsVideoCapture;
@property (nonatomic, assign, readonly) BOOL supportsAudioCapture;
@property (nonatomic, copy, readonly) NSArray *supportedPhotoResolutions;

+ (RLVDeviceCapabilities *)currentCapabilities;
- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position;

@end
