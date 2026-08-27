#import "RLVCaptureEvent.h"
#import <UIKit/UIKit.h>

@protocol RLVCameraOrientationCoordinatorDelegate;

/// Converts physical device orientation into distinct preview/capture and control transforms.
/// It does not rotate or store media itself.
@interface RLVCameraOrientationCoordinator : NSObject

@property (nonatomic, assign) id<RLVCameraOrientationCoordinatorDelegate> delegate;
@property (nonatomic, assign, readonly) RLVCaptureOrientation captureOrientation;
@property (nonatomic, assign, readonly) AVCaptureVideoOrientation videoOrientation;
@property (nonatomic, assign, readonly) CGAffineTransform controlTransform;

/// Starts device-orientation observation and immediately publishes the current transform.
- (void)start;
/// Stops observation. Safe to call repeatedly.
- (void)stop;

@end

@protocol RLVCameraOrientationCoordinatorDelegate <NSObject>
/// Requests a visual rotation for chrome controls; the preview layer is handled separately.
- (void)orientationCoordinator:(RLVCameraOrientationCoordinator *)coordinator
      didUpdateControlTransform:(CGAffineTransform)transform;
@end
