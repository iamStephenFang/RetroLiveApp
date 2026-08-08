#import "RLVCaptureEvent.h"
#import <UIKit/UIKit.h>

@protocol RLVCameraOrientationCoordinatorDelegate;

@interface RLVCameraOrientationCoordinator : NSObject

@property (nonatomic, assign) id<RLVCameraOrientationCoordinatorDelegate> delegate;
@property (nonatomic, assign, readonly) RLVCaptureOrientation captureOrientation;
@property (nonatomic, assign, readonly) AVCaptureVideoOrientation videoOrientation;
@property (nonatomic, assign, readonly) CGAffineTransform controlTransform;

- (void)start;
- (void)stop;

@end

@protocol RLVCameraOrientationCoordinatorDelegate <NSObject>
- (void)orientationCoordinator:(RLVCameraOrientationCoordinator *)coordinator
      didUpdateControlTransform:(CGAffineTransform)transform;
@end
