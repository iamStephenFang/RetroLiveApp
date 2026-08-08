#import "RLVCaptureEvent.h"
#import <Foundation/Foundation.h>

@interface RLVAsset : NSObject

@property (nonatomic, copy) NSString *assetId;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong) NSDate *captureTimestamp;
@property (nonatomic, strong) NSURL *photoURL;
@property (nonatomic, strong) NSURL *motionURL;
@property (nonatomic, strong) NSURL *manifestURL;
@property (nonatomic, assign) NSUInteger width;
@property (nonatomic, assign) NSUInteger height;
@property (nonatomic, assign) RLVCaptureOrientation orientation;
@property (nonatomic, copy) NSString *captureDevice;

- (BOOL)hasPhoto;
- (BOOL)hasMotion;
- (BOOL)isComplete;

@end
