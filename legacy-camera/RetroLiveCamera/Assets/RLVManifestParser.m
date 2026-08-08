#import "RLVManifestParser.h"
#import "RLVAssetManifest.h"
#import <math.h>

NSString * const RLVManifestParserErrorDomain = @"com.retrolive.manifest";

static BOOL RLVParserIsNumber(id value)
{
    return [value isKindOfClass:[NSNumber class]] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID();
}

static BOOL RLVParserIsBoolean(id value)
{
    return [value isKindOfClass:[NSNumber class]] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

static BOOL RLVParserIsNonEmptyString(id value)
{
    return [value isKindOfClass:[NSString class]] && [value length] > 0;
}

static BOOL RLVParserIsISO8601Date(id value)
{
    if (![value isKindOfClass:[NSString class]]) return NO;
    NSArray *formats = [NSArray arrayWithObjects:@"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ", @"yyyy-MM-dd'T'HH:mm:ssZZZZZ", nil];
    for (NSString *format in formats) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = format;
        if ([formatter dateFromString:value] != nil) return YES;
    }
    return NO;
}

@interface RLVManifestParser ()
- (void)setError:(NSError **)error code:(RLVManifestParserErrorCode)code message:(NSString *)message;
- (BOOL)readResource:(NSDictionary *)dictionary into:(RLVMediaResource *)resource image:(BOOL)image error:(NSError **)error;
- (NSDate *)dateFromISO8601String:(NSString *)value;
@end


@implementation RLVManifestParser

- (RLVAssetManifest *)manifestFromData:(NSData *)data error:(NSError **)error
{
    NSError *jsonError = nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (![value isKindOfClass:[NSDictionary class]]) {
        [self setError:error code:RLVManifestParserErrorInvalidJSON message:[jsonError localizedDescription] ?: @"Manifest root must be an object."];
        return nil;
    }

    NSDictionary *root = (NSDictionary *)value;
    NSNumber *version = [root objectForKey:@"schemaVersion"];
    if (!RLVParserIsNumber(version)) {
        [self setError:error code:RLVManifestParserErrorMissingValue message:@"schemaVersion is required."];
        return nil;
    }
    if ([version integerValue] != 1) {
        [self setError:error code:RLVManifestParserErrorUnsupportedSchema message:[NSString stringWithFormat:@"Unsupported schemaVersion %@; supported versions: 1.", version]];
        return nil;
    }

    NSString *assetId = [root objectForKey:@"assetId"];
    NSString *createdAt = [root objectForKey:@"createdAt"];
    NSNumber *createdMilliseconds = [root objectForKey:@"createdAtUnixMilliseconds"];
    NSDictionary *captureJSON = [root objectForKey:@"capture"];
    NSDictionary *photoJSON = [root objectForKey:@"photo"];
    id motionValue = [root objectForKey:@"motion"];
    id thumbnailValue = [root objectForKey:@"thumbnail"];
    NSDictionary *motionJSON = [motionValue isKindOfClass:[NSDictionary class]] ? motionValue : nil;
    NSDictionary *thumbnailJSON = [thumbnailValue isKindOfClass:[NSDictionary class]] ? thumbnailValue : nil;
    NSDictionary *deviceJSON = [root objectForKey:@"device"];
    if (!RLVParserIsNonEmptyString(assetId) || !RLVParserIsISO8601Date(createdAt) ||
        !RLVParserIsNumber(createdMilliseconds) || ![captureJSON isKindOfClass:[NSDictionary class]] ||
        ![photoJSON isKindOfClass:[NSDictionary class]] || motionValue == nil ||
        !([motionValue isKindOfClass:[NSDictionary class]] || motionValue == [NSNull null]) ||
        (thumbnailValue != nil && ![thumbnailValue isKindOfClass:[NSDictionary class]]) ||
        ![deviceJSON isKindOfClass:[NSDictionary class]]) {
        [self setError:error code:RLVManifestParserErrorMissingValue message:@"Manifest is missing one or more required values."];
        return nil;
    }
    NSDate *createdDate = [self dateFromISO8601String:createdAt];
    double timestampDifference = fabs([createdDate timeIntervalSince1970] * 1000.0 - [createdMilliseconds longLongValue]);
    if ([[NSUUID alloc] initWithUUIDString:assetId] == nil || [createdMilliseconds longLongValue] < 0 ||
        createdDate == nil || timestampDifference > 1.0) {
        [self setError:error code:RLVManifestParserErrorInvalidValue message:@"assetId or createdAtUnixMilliseconds is invalid."];
        return nil;
    }

    id cameraPosition = [captureJSON objectForKey:@"cameraPosition"];
    id orientation = [captureJSON objectForKey:@"orientation"];
    id mirrored = [captureJSON objectForKey:@"mirrored"];
    id flashMode = [captureJSON objectForKey:@"flashMode"];
    id stillImageTime = [captureJSON objectForKey:@"stillImageTimeSeconds"];
    id stillImageTimeAccuracy = [captureJSON objectForKey:@"stillImageTimeAccuracy"];
    id preRoll = [captureJSON objectForKey:@"preRollSeconds"];
    id postRoll = [captureJSON objectForKey:@"postRollSeconds"];
    if (![cameraPosition isKindOfClass:[NSString class]] || !RLVParserIsNumber(orientation) ||
        !RLVParserIsBoolean(mirrored) || ![flashMode isKindOfClass:[NSString class]] ||
        !RLVParserIsNumber(stillImageTime) || ![stillImageTimeAccuracy isKindOfClass:[NSString class]] ||
        !RLVParserIsNumber(preRoll) || !RLVParserIsNumber(postRoll)) {
        [self setError:error code:RLVManifestParserErrorMissingValue message:@"capture is missing one or more required values."];
        return nil;
    }
    RLVCaptureMetadata *capture = [[RLVCaptureMetadata alloc] init];
    capture.cameraPosition = cameraPosition;
    capture.orientation = [orientation unsignedIntegerValue];
    capture.mirrored = [mirrored boolValue];
    capture.flashMode = flashMode;
    capture.stillImageTimeSeconds = [stillImageTime doubleValue];
    capture.stillImageTimeAccuracy = stillImageTimeAccuracy;
    capture.preRollSeconds = [preRoll doubleValue];
    capture.postRollSeconds = [postRoll doubleValue];
    if (!([capture.cameraPosition isEqualToString:@"front"] || [capture.cameraPosition isEqualToString:@"back"]) ||
        capture.orientation < 1 || capture.orientation > 8 ||
        !([capture.flashMode isEqualToString:@"off"] || [capture.flashMode isEqualToString:@"on"] || [capture.flashMode isEqualToString:@"auto"]) ||
        !([capture.stillImageTimeAccuracy isEqualToString:@"measured"] || [capture.stillImageTimeAccuracy isEqualToString:@"estimated"]) ||
        capture.stillImageTimeSeconds < 0 || capture.preRollSeconds < 0 || capture.postRollSeconds < 0) {
        [self setError:error code:RLVManifestParserErrorInvalidValue message:@"capture contains an invalid value."];
        return nil;
    }

    RLVImageResource *photo = [[RLVImageResource alloc] init];
    RLVMotionResource *motion = motionJSON ? [[RLVMotionResource alloc] init] : nil;
    RLVImageResource *thumbnail = thumbnailJSON ? [[RLVImageResource alloc] init] : nil;
    if (![self readResource:photoJSON into:photo image:YES error:error] ||
        (motion && ![self readResource:motionJSON into:motion image:NO error:error]) ||
        (thumbnail && ![self readResource:thumbnailJSON into:thumbnail image:YES error:error])) {
        return nil;
    }

    if (motion) {
        id duration = [motionJSON objectForKey:@"durationSeconds"];
        id motionWidth = [motionJSON objectForKey:@"width"];
        id motionHeight = [motionJSON objectForKey:@"height"];
        id frameRate = [motionJSON objectForKey:@"frameRate"];
        id hasAudio = [motionJSON objectForKey:@"hasAudio"];
        if (!RLVParserIsNumber(duration) || !RLVParserIsNumber(motionWidth) ||
            !RLVParserIsNumber(motionHeight) || !RLVParserIsNumber(frameRate) ||
            !RLVParserIsBoolean(hasAudio)) {
            [self setError:error code:RLVManifestParserErrorMissingValue message:@"motion is missing one or more required values."];
            return nil;
        }
        motion.durationSeconds = [duration doubleValue];
        motion.width = [motionWidth unsignedIntegerValue];
        motion.height = [motionHeight unsignedIntegerValue];
        motion.frameRate = [frameRate doubleValue];
        motion.hasAudio = [hasAudio boolValue];
        if (motion.durationSeconds <= 0 || motion.width == 0 || motion.height == 0 || motion.frameRate <= 0 || capture.stillImageTimeSeconds >= motion.durationSeconds) {
            [self setError:error code:RLVManifestParserErrorInvalidValue message:@"motion contains an invalid value or still image time is out of range."];
            return nil;
        }
    } else if (capture.stillImageTimeSeconds != 0 || capture.preRollSeconds != 0 || capture.postRollSeconds != 0) {
        [self setError:error code:RLVManifestParserErrorInvalidValue message:@"Photo-only assets require zero motion timing values."];
        return nil;
    }

    id modelIdentifier = [deviceJSON objectForKey:@"modelIdentifier"];
    id systemVersion = [deviceJSON objectForKey:@"systemVersion"];
    id appVersion = [deviceJSON objectForKey:@"appVersion"];
    if (!RLVParserIsNonEmptyString(modelIdentifier) || !RLVParserIsNonEmptyString(systemVersion) ||
        !RLVParserIsNonEmptyString(appVersion)) {
        [self setError:error code:RLVManifestParserErrorMissingValue message:@"device values are required."];
        return nil;
    }
    RLVDeviceMetadata *device = [[RLVDeviceMetadata alloc] init];
    device.modelIdentifier = modelIdentifier;
    device.systemVersion = systemVersion;
    device.appVersion = appVersion;

    RLVAssetManifest *manifest = [[RLVAssetManifest alloc] init];
    manifest.schemaVersion = [version integerValue];
    manifest.assetId = assetId;
    manifest.createdAt = createdAt;
    manifest.createdAtUnixMilliseconds = [createdMilliseconds longLongValue];
    manifest.capture = capture;
    manifest.photo = photo;
    manifest.motion = motion;
    manifest.thumbnail = thumbnail;
    manifest.device = device;
    return manifest;
}

- (NSDate *)dateFromISO8601String:(NSString *)value
{
    NSArray *formats = [NSArray arrayWithObjects:@"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ", @"yyyy-MM-dd'T'HH:mm:ssZZZZZ", nil];
    for (NSString *format in formats) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = format;
        NSDate *date = [formatter dateFromString:value];
        if (date) return date;
    }
    return nil;
}

- (BOOL)readResource:(NSDictionary *)dictionary into:(RLVMediaResource *)resource image:(BOOL)image error:(NSError **)error
{
    NSString *filename = [dictionary objectForKey:@"filename"];
    NSString *mimeType = [dictionary objectForKey:@"mimeType"];
    NSNumber *byteLength = [dictionary objectForKey:@"byteLength"];
    NSString *sha256 = [dictionary objectForKey:@"sha256"];
    NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
    BOOL hashValid = [sha256 isKindOfClass:[NSString class]] && [sha256 length] == 64 && [sha256 rangeOfCharacterFromSet:[hexSet invertedSet]].location == NSNotFound;
    BOOL filenameValid = [filename isKindOfClass:[NSString class]] && [filename length] > 0 &&
        ![filename isEqualToString:@"."] && ![filename isEqualToString:@".."] &&
        [filename rangeOfString:@"/"].location == NSNotFound && [filename rangeOfString:@"\\"].location == NSNotFound;
    if (!filenameValid || !RLVParserIsNonEmptyString(mimeType) || !RLVParserIsNumber(byteLength) || [byteLength longLongValue] <= 0 || !hashValid) {
        [self setError:error code:RLVManifestParserErrorInvalidValue message:@"Media resource contains an invalid filename, length, MIME type, or SHA-256 value."];
        return NO;
    }
    resource.filename = filename;
    resource.mimeType = mimeType;
    resource.byteLength = [byteLength unsignedLongLongValue];
    resource.sha256 = sha256;
    if (image) {
        RLVImageResource *imageResource = (RLVImageResource *)resource;
        id width = [dictionary objectForKey:@"width"];
        id height = [dictionary objectForKey:@"height"];
        if (!RLVParserIsNumber(width) || !RLVParserIsNumber(height) ||
            [width unsignedIntegerValue] == 0 || [height unsignedIntegerValue] == 0) {
            [self setError:error code:RLVManifestParserErrorInvalidValue message:@"Image dimensions must be positive."];
            return NO;
        }
        imageResource.width = [width unsignedIntegerValue];
        imageResource.height = [height unsignedIntegerValue];
    }
    return YES;
}

- (void)setError:(NSError **)error code:(RLVManifestParserErrorCode)code message:(NSString *)message
{
    if (error != NULL) {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:(message ?: @"Invalid manifest.") forKey:NSLocalizedDescriptionKey];
        *error = [NSError errorWithDomain:RLVManifestParserErrorDomain code:code userInfo:userInfo];
    }
}

@end
