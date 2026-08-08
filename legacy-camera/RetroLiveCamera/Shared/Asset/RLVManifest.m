#import "RLVManifest.h"
#import <CommonCrypto/CommonDigest.h>

@implementation RLVManifest

+ (NSDictionary *)manifestForEvent:(RLVCaptureEvent *)event
                         photoData:(NSData *)photoData
                        motionData:(NSData *)motionData
                              width:(NSUInteger)width
                             height:(NSUInteger)height
                       capabilities:(RLVDeviceCapabilities *)capabilities
{
    NSString *createdAt = [self ISO8601StringFromDate:event.shutterTimestamp];
    long long milliseconds = (long long)llround([event.shutterTimestamp timeIntervalSince1970] * 1000.0);
    NSString *cameraPosition = event.cameraPosition == AVCaptureDevicePositionFront ? @"front" : @"back";
    NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ?: @"1.0";
    BOOL hasMotion = motionData != nil;
    NSDictionary *capture = [NSDictionary dictionaryWithObjectsAndKeys:
        cameraPosition, @"cameraPosition",
        [NSNumber numberWithInteger:event.orientation], @"orientation",
        [NSNumber numberWithBool:event.isMirrored], @"mirrored",
        event.flashMode ?: @"off", @"flashMode",
        [NSNumber numberWithDouble:hasMotion ? event.stillImageTimeSeconds : 0.0], @"stillImageTimeSeconds",
        @"estimated", @"stillImageTimeAccuracy",
        [NSNumber numberWithDouble:hasMotion ? event.preRollSeconds : 0.0], @"preRollSeconds",
        [NSNumber numberWithDouble:hasMotion ? event.postRollSeconds : 0.0], @"postRollSeconds",
        [NSNumber numberWithLongLong:milliseconds], @"shutterTimestampUnixMilliseconds", nil];
    NSDictionary *photo = [NSDictionary dictionaryWithObjectsAndKeys:
        @"photo.jpg", @"filename", @"image/jpeg", @"mimeType",
        [NSNumber numberWithUnsignedInteger:width], @"width",
        [NSNumber numberWithUnsignedInteger:height], @"height",
        [NSNumber numberWithUnsignedLongLong:[photoData length]], @"byteLength",
        [self SHA256ForData:photoData], @"sha256", nil];
    NSDictionary *device = [NSDictionary dictionaryWithObjectsAndKeys:
        capabilities.modelIdentifier ?: @"unknown", @"modelIdentifier",
        capabilities.systemVersion ?: @"unknown", @"systemVersion",
        appVersion, @"appVersion",
        capabilities.architecture ?: @"unknown", @"architecture", nil];
    id motion = [NSNull null];
    if (hasMotion) {
        motion = [NSDictionary dictionaryWithObjectsAndKeys:
            @"motion.mov", @"filename", @"video/quicktime", @"mimeType",
            [NSNumber numberWithDouble:event.motionDurationSeconds], @"durationSeconds",
            [NSNumber numberWithUnsignedInteger:event.motionWidth], @"width",
            [NSNumber numberWithUnsignedInteger:event.motionHeight], @"height",
            [NSNumber numberWithDouble:event.motionFrameRate], @"frameRate",
            [NSNumber numberWithBool:event.motionHasAudio], @"hasAudio",
            [NSNumber numberWithUnsignedLongLong:[motionData length]], @"byteLength",
            [self SHA256ForData:motionData], @"sha256", nil];
    }
    return [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInteger:1], @"schemaVersion",
        event.assetId, @"assetId", createdAt, @"createdAt",
        [NSNumber numberWithLongLong:milliseconds], @"createdAtUnixMilliseconds",
        capture, @"capture", photo, @"photo", motion, @"motion", device, @"device", nil];
}

+ (NSData *)JSONDataForManifest:(NSDictionary *)manifest error:(NSError **)error
{
    return [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:error];
}

+ (NSString *)SHA256ForData:(NSData *)data
{
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256([data bytes], (CC_LONG)[data length], digest);
    NSMutableString *value = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [value appendFormat:@"%02x", digest[index]];
    }
    return value;
}

+ (NSString *)ISO8601StringFromDate:(NSDate *)date
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    return [formatter stringFromDate:date];
}

+ (NSDate *)dateFromISO8601String:(NSString *)value
{
    if (![value isKindOfClass:[NSString class]]) return nil;
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    return [formatter dateFromString:value];
}

@end
