#import "RLVCaptureEvent.h"
#import <Foundation/Foundation.h>

/// In-memory description of one validated, committed camera asset directory.
@interface RLVAsset : NSObject

@property (nonatomic, copy) NSString *assetId;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong) NSDate *captureTimestamp;
@property (nonatomic, strong) NSURL *photoURL;
@property (nonatomic, strong) NSURL *thumbnailURL;
@property (nonatomic, strong) NSURL *motionURL;
@property (nonatomic, strong) NSURL *manifestURL;
@property (nonatomic, assign) NSUInteger width;
@property (nonatomic, assign) NSUInteger height;
@property (nonatomic, assign) NSUInteger motionWidth;
@property (nonatomic, assign) NSUInteger motionHeight;
@property (nonatomic, assign) RLVCaptureOrientation orientation;
@property (nonatomic, copy) NSString *captureDevice;
@property (nonatomic, copy) NSString *aspectRatio;

/// Returns whether the referenced still-image file is currently present.
- (BOOL)hasPhoto;
/// Returns whether the optional motion companion is currently present.
- (BOOL)hasMotion;
/// Returns whether all resources required by this asset representation are present.
- (BOOL)isComplete;

@end
