#import "RLVCaptureEvent.h"
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, RLVCaptureState) {
    RLVCaptureStateIdle,
    RLVCaptureStatePreparing,
    RLVCaptureStateRunning,
    RLVCaptureStateCapturing,
    RLVCaptureStateInterrupted,
    RLVCaptureStateFailed
};

@protocol RLVCaptureControllerDelegate;

@interface RLVCaptureController : NSObject

@property (nonatomic, assign) id<RLVCaptureControllerDelegate> delegate;
@property (nonatomic, assign, readonly) RLVCaptureState state;
@property (nonatomic, strong, readonly) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, assign, readonly) AVCaptureDevicePosition cameraPosition;
@property (nonatomic, assign, readonly) AVCaptureFlashMode flashMode;

- (void)prepareWithCompletion:(void (^)(NSError *error))completion;
- (void)startRunning;
- (void)stopRunning;
- (void)interrupt;
- (void)resumeAfterInterruption;
- (void)capturePhotoWithOrientation:(RLVCaptureOrientation)orientation
                   videoOrientation:(AVCaptureVideoOrientation)videoOrientation;
- (void)updateVideoOrientation:(AVCaptureVideoOrientation)videoOrientation;
- (void)switchCamera;
- (void)setFlashMode:(AVCaptureFlashMode)flashMode;
- (void)focusAtDevicePoint:(CGPoint)devicePoint;

@end

@protocol RLVCaptureControllerDelegate <NSObject>
@optional
- (void)captureController:(RLVCaptureController *)controller didChangeState:(RLVCaptureState)state;
- (void)captureController:(RLVCaptureController *)controller didChangeCameraPosition:(AVCaptureDevicePosition)position;
- (void)captureController:(RLVCaptureController *)controller
      didCapturePhotoData:(NSData *)photoData
                motionURL:(NSURL *)motionURL
                    event:(RLVCaptureEvent *)event;
- (void)captureController:(RLVCaptureController *)controller didFailWithError:(NSError *)error;
@end
