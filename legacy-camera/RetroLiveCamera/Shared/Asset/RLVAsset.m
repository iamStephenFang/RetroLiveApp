#import "RLVAsset.h"

@implementation RLVAsset

- (BOOL)hasPhoto
{
    return self.photoURL != nil && [[NSFileManager defaultManager] fileExistsAtPath:[self.photoURL path]];
}

- (BOOL)hasMotion
{
    return self.motionURL != nil && [[NSFileManager defaultManager] fileExistsAtPath:[self.motionURL path]];
}

- (BOOL)isComplete
{
    return [self hasPhoto] && self.manifestURL != nil &&
        [[NSFileManager defaultManager] fileExistsAtPath:[self.manifestURL path]];
}

@synthesize assetId = _assetId;
@synthesize createdAt = _createdAt;
@synthesize captureTimestamp = _captureTimestamp;
@synthesize photoURL = _photoURL;
@synthesize motionURL = _motionURL;
@synthesize manifestURL = _manifestURL;
@synthesize width = _width;
@synthesize height = _height;
@synthesize motionWidth = _motionWidth;
@synthesize motionHeight = _motionHeight;
@synthesize orientation = _orientation;
@synthesize captureDevice = _captureDevice;
@synthesize aspectRatio = _aspectRatio;

@end
