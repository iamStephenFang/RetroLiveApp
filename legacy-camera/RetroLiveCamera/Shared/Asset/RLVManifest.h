#import "RLVCaptureEvent.h"
#import "RLVDeviceCapabilities.h"
#import <Foundation/Foundation.h>

/// Builds and serializes the camera-side Manifest V1 representation.
@interface RLVManifest : NSObject

/// Returns a Manifest V1 dictionary; optional motion and thumbnail data may be nil.
+ (NSDictionary *)manifestForEvent:(RLVCaptureEvent *)event
                         photoData:(NSData *)photoData
                        motionData:(NSData *)motionData
                     thumbnailData:(NSData *)thumbnailData
                              width:(NSUInteger)width
                             height:(NSUInteger)height
                    thumbnailWidth:(NSUInteger)thumbnailWidth
                   thumbnailHeight:(NSUInteger)thumbnailHeight
                       capabilities:(RLVDeviceCapabilities *)capabilities;
/// Serializes a manifest using JSON types accepted by the protocol contract.
+ (NSData *)JSONDataForManifest:(NSDictionary *)manifest error:(NSError **)error;
/// Returns the lowercase hexadecimal SHA-256 digest for data.
+ (NSString *)SHA256ForData:(NSData *)data;
/// Parses the protocol's UTC ISO-8601 timestamp representation, or returns nil.
+ (NSDate *)dateFromISO8601String:(NSString *)value;

@end
