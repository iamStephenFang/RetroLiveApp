#import "RLVCaptureEvent.h"
#import "RLVDeviceCapabilities.h"
#import <Foundation/Foundation.h>

@interface RLVManifest : NSObject

+ (NSDictionary *)manifestForEvent:(RLVCaptureEvent *)event
                         photoData:(NSData *)photoData
                        motionData:(NSData *)motionData
                     thumbnailData:(NSData *)thumbnailData
                              width:(NSUInteger)width
                             height:(NSUInteger)height
                    thumbnailWidth:(NSUInteger)thumbnailWidth
                   thumbnailHeight:(NSUInteger)thumbnailHeight
                       capabilities:(RLVDeviceCapabilities *)capabilities;
+ (NSData *)JSONDataForManifest:(NSDictionary *)manifest error:(NSError **)error;
+ (NSString *)SHA256ForData:(NSData *)data;
+ (NSDate *)dateFromISO8601String:(NSString *)value;

@end
