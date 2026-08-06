#import "RLVManifestParser.h"
#import "RLVAssetManifest.h"

NSString * const RLVManifestParserErrorDomain = @"com.retrolive.manifest";

@interface RLVManifestParser ()
- (void)setError:(NSError **)error code:(RLVManifestParserErrorCode)code message:(NSString *)message;
- (BOOL)readResource:(NSDictionary *)dictionary into:(RLVMediaResource *)resource image:(BOOL)image error:(NSError **)error;
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
    if (![version isKindOfClass:[NSNumber class]]) {
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
    NSDictionary *motionJSON = [root objectForKey:@"motion"];
    NSDictionary *thumbnailJSON = [root objectForKey:@"thumbnail"];
    NSDictionary *deviceJSON = [root objectForKey:@"device"];
    if (![assetId isKindOfClass:[NSString class]] || ![createdAt isKindOfClass:[NSString class]] ||
        ![createdMilliseconds isKindOfClass:[NSNumber class]] || ![captureJSON isKindOfClass:[NSDictionary class]] ||
        ![photoJSON isKindOfClass:[NSDictionary class]] || ![motionJSON isKindOfClass:[NSDictionary class]] ||
        ![thumbnailJSON isKindOfClass:[NSDictionary class]] || ![deviceJSON isKindOfClass:[NSDictionary class]]) {
        [self setError:error code:RLVManifestParserErrorMissingValue message:@"Manifest is missing one or more required values."];
        return nil;
    }
    if ([[NSUUID alloc] initWithUUIDString:assetId] == nil || [createdMilliseconds longLongValue] < 0) {
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
    if (![cameraPosition isKindOfClass:[NSString class]] || ![orientation isKindOfClass:[NSNumber class]] ||
        ![mirrored isKindOfClass:[NSNumber class]] || ![flashMode isKindOfClass:[NSString class]] ||
        ![stillImageTime isKindOfClass:[NSNumber class]] || ![stillImageTimeAccuracy isKindOfClass:[NSString class]] ||
        ![preRoll isKindOfClass:[NSNumber class]] || ![postRoll isKindOfClass:[NSNumber class]]) {
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
    RLVMotionResource *motion = [[RLVMotionResource alloc] init];
    RLVImageResource *thumbnail = [[RLVImageResource alloc] init];
    if (![self readResource:photoJSON into:photo image:YES error:error] ||
        ![self readResource:motionJSON into:motion image:NO error:error] ||
        ![self readResource:thumbnailJSON into:thumbnail image:YES error:error]) {
        return nil;
    }

    id duration = [motionJSON objectForKey:@"durationSeconds"];
    id motionWidth = [motionJSON objectForKey:@"width"];
    id motionHeight = [motionJSON objectForKey:@"height"];
    id frameRate = [motionJSON objectForKey:@"frameRate"];
    id hasAudio = [motionJSON objectForKey:@"hasAudio"];
    if (![duration isKindOfClass:[NSNumber class]] || ![motionWidth isKindOfClass:[NSNumber class]] ||
        ![motionHeight isKindOfClass:[NSNumber class]] || ![frameRate isKindOfClass:[NSNumber class]] ||
        ![hasAudio isKindOfClass:[NSNumber class]]) {
        [self setError:error code:RLVManifestParserErrorMissingValue message:@"motion is missing one or more required values."];
        return nil;
    }
    motion.durationSeconds = [duration doubleValue];
    motion.width = [motionWidth unsignedIntegerValue];
    motion.height = [motionHeight unsignedIntegerValue];
    motion.frameRate = [frameRate doubleValue];
    motion.hasAudio = [hasAudio boolValue];
    if (motion.durationSeconds <= 0 || motion.width == 0 || motion.height == 0 || motion.frameRate <= 0 || capture.stillImageTimeSeconds > motion.durationSeconds) {
        [self setError:error code:RLVManifestParserErrorInvalidValue message:@"motion contains an invalid value or still image time is out of range."];
        return nil;
    }

    id modelIdentifier = [deviceJSON objectForKey:@"modelIdentifier"];
    id systemVersion = [deviceJSON objectForKey:@"systemVersion"];
    id appVersion = [deviceJSON objectForKey:@"appVersion"];
    if (![modelIdentifier isKindOfClass:[NSString class]] || ![systemVersion isKindOfClass:[NSString class]] ||
        ![appVersion isKindOfClass:[NSString class]] || [modelIdentifier length] == 0 ||
        [systemVersion length] == 0 || [appVersion length] == 0) {
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
    if (!filenameValid || ![mimeType isKindOfClass:[NSString class]] || ![byteLength isKindOfClass:[NSNumber class]] || [byteLength longLongValue] < 0 || !hashValid) {
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
        if (![width isKindOfClass:[NSNumber class]] || ![height isKindOfClass:[NSNumber class]] ||
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
