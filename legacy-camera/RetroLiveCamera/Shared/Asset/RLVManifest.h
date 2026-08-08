#import "RLVCaptureEvent.h"
#import "RLVDeviceCapabilities.h"
#import <Foundation/Foundation.h>

@interface RLVManifest : NSObject

+ (NSDictionary *)manifestForEvent:(RLVCaptureEvent *)event
                         photoData:(NSData *)photoData
                              width:(NSUInteger)width
                             height:(NSUInteger)height
                       capabilities:(RLVDeviceCapabilities *)capabilities;
+ (NSData *)JSONDataForManifest:(NSDictionary *)manifest error:(NSError **)error;
+ (NSString *)SHA256ForData:(NSData *)data;
+ (NSDate *)dateFromISO8601String:(NSString *)value;

@end
