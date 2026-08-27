#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

/// EXIF-compatible orientation values persisted in Manifest V1.
typedef NS_ENUM(NSInteger, RLVCaptureOrientation) {
    RLVCaptureOrientationPortrait = 6,
    RLVCaptureOrientationPortraitUpsideDown = 8,
    RLVCaptureOrientationLandscapeLeft = 1,
    RLVCaptureOrientationLandscapeRight = 3
};

/// Immutable-in-practice snapshot of shutter-time metadata shared by capture and storage.
@interface RLVCaptureEvent : NSObject

@property (nonatomic, copy) NSString *assetId;
@property (nonatomic, strong) NSDate *shutterTimestamp;
@property (nonatomic, assign) RLVCaptureOrientation orientation;
@property (nonatomic, assign) AVCaptureDevicePosition cameraPosition;
@property (nonatomic, assign, getter=isMirrored) BOOL mirrored;
@property (nonatomic, copy) NSString *flashMode;
@property (nonatomic, copy) NSString *aspectRatio;
@property (nonatomic, assign) NSTimeInterval stillImageTimeSeconds;
@property (nonatomic, assign) NSTimeInterval preRollSeconds;
@property (nonatomic, assign) NSTimeInterval postRollSeconds;
@property (nonatomic, assign) NSTimeInterval motionDurationSeconds;
@property (nonatomic, assign) NSUInteger motionWidth;
@property (nonatomic, assign) NSUInteger motionHeight;
@property (nonatomic, assign) double motionFrameRate;
@property (nonatomic, assign) BOOL motionHasAudio;

@end
