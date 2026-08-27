#import "RLVCaptureEvent.h"
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

/// Lifecycle states reported by the capture controller.
typedef NS_ENUM(NSInteger, RLVCaptureState) {
    RLVCaptureStateIdle,
    RLVCaptureStatePreparing,
    RLVCaptureStateRunning,
    RLVCaptureStateCapturing,
    RLVCaptureStateInterrupted,
    RLVCaptureStateFailed
};

/// The device operations that accepted a requested point of interest.
typedef NS_OPTIONS(NSUInteger, RLVPointOfInterestResult) {
    RLVPointOfInterestResultNone = 0,
    RLVPointOfInterestResultFocus = 1 << 0,
    RLVPointOfInterestResultExposure = 1 << 1
};

@protocol RLVCaptureControllerDelegate;

/// Owns the AVFoundation capture session and rolling-motion capture.
///
/// All public entry points must be invoked on the main thread. Delegate callbacks and
/// completion blocks are delivered on the main thread.
@interface RLVCaptureController : NSObject

@property (nonatomic, assign) id<RLVCaptureControllerDelegate> delegate;
/// Current lifecycle state. Observe delegate changes rather than polling during transitions.
@property (nonatomic, assign, readonly) RLVCaptureState state;
/// Layer attached to the current session; it may be replaced during foreground recovery.
@property (nonatomic, strong, readonly) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, assign, readonly) AVCaptureDevicePosition cameraPosition;
@property (nonatomic, assign, readonly) AVCaptureFlashMode flashMode;
@property (nonatomic, assign, readonly, getter=isRecordingMotion) BOOL recordingMotion;
/// Whether rolling motion should accompany stills when the device supports it.
@property (nonatomic, assign, getter=isMotionCaptureEnabled) BOOL motionCaptureEnabled;

/// Configures capture devices and outputs. A nil error means the controller is ready to start.
- (void)prepareWithCompletion:(void (^)(NSError *error))completion;
/// Starts a prepared session. Repeated calls while starting or running are ignored.
- (void)startRunning;
/// Stops capture and returns the controller to its idle state.
- (void)stopRunning;
/// Stops session work while preserving enough state for foreground recovery.
- (void)interrupt;
/// Rebuilds preview state as needed and restarts after an interruption.
- (void)resumeAfterInterruption;
/// Replaces the preview layer when the existing layer no longer renders session output.
- (void)refreshPreviewLayer;
/// Captures a still and, when enabled and available, its rolling-motion companion.
///
/// - Parameters:
///   - orientation: Orientation written to the asset manifest.
///   - videoOrientation: Orientation applied to the captured video connection.
///   - aspectRatio: Requested still crop ratio using the protocol values (for example, `4:3`).
- (void)capturePhotoWithOrientation:(RLVCaptureOrientation)orientation
                   videoOrientation:(AVCaptureVideoOrientation)videoOrientation
                         aspectRatio:(NSString *)aspectRatio;
/// Updates preview and rolling-video connections without changing control rotation.
- (void)updateVideoOrientation:(AVCaptureVideoOrientation)videoOrientation;
/// Switches between available front and rear cameras while preserving session ownership.
- (void)switchCamera;
/// Applies a supported flash mode to the active camera; unsupported modes are ignored.
- (void)setFlashMode:(AVCaptureFlashMode)flashMode;
/// Requests focus and exposure at an AVFoundation device-coordinate point in the unit square.
/// The completion value identifies which independently supported operations were applied.
///
/// - Parameters:
///   - devicePoint: AVFoundation device-coordinate point, with both axes in the unit interval.
///   - completion: Main-thread callback describing the operations the active device accepted.
- (void)focusAndExposeAtDevicePoint:(CGPoint)devicePoint
                         completion:(void (^)(RLVPointOfInterestResult result))completion;

@end

@protocol RLVCaptureControllerDelegate <NSObject>
@optional
/// Reports lifecycle changes on the main thread.
- (void)captureController:(RLVCaptureController *)controller didChangeState:(RLVCaptureState)state;
- (void)captureController:(RLVCaptureController *)controller didChangeCameraPosition:(AVCaptureDevicePosition)position;
- (void)captureController:(RLVCaptureController *)controller didChangeMotionCaptureEnabled:(BOOL)enabled;
/// Delivers capture output for validation and permanent storage; motionURL may be nil.
- (void)captureController:(RLVCaptureController *)controller
      didCapturePhotoData:(NSData *)photoData
                motionURL:(NSURL *)motionURL
                    event:(RLVCaptureEvent *)event;
/// Reports a capture failure that the controller could not recover or degrade around.
- (void)captureController:(RLVCaptureController *)controller didFailWithError:(NSError *)error;
@end
