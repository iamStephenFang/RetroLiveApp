#import "RLVAssetStore.h"
#import "RLVManifest.h"
#import <ImageIO/ImageIO.h>

NSString * const RLVAssetStoreDidChangeNotification = @"RLVAssetStoreDidChangeNotification";
NSString * const RLVAssetStoreErrorDomain = @"com.retrolive.asset-store";

static BOOL RLVIsNonEmptyString(id value)
{
    return [value isKindOfClass:[NSString class]] && [value length] > 0;
}

static BOOL RLVIsNumber(id value)
{
    return [value isKindOfClass:[NSNumber class]] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID();
}

static BOOL RLVIsBoolean(id value)
{
    return [value isKindOfClass:[NSNumber class]] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

@interface RLVAssetStore () {
    dispatch_queue_t _fileQueue;
}
@property (nonatomic, strong, readwrite) NSURL *rootURL;
@property (nonatomic, strong, readwrite) NSURL *assetsURL;
@property (nonatomic, strong, readwrite) NSURL *temporaryURL;
@end

@implementation RLVAssetStore

+ (RLVAssetStore *)sharedStore
{
    static RLVAssetStore *store = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *documents = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
        store = [[RLVAssetStore alloc] initWithDocumentsURL:[documents lastObject]];
    });
    return store;
}

- (id)initWithDocumentsURL:(NSURL *)documentsURL
{
    self = [super init];
    if (self) {
        _fileQueue = dispatch_queue_create("com.retrolive.asset-store", DISPATCH_QUEUE_SERIAL);
        _rootURL = [documentsURL URLByAppendingPathComponent:@"RetroLive" isDirectory:YES];
        _assetsURL = [_rootURL URLByAppendingPathComponent:@"Assets" isDirectory:YES];
        _temporaryURL = [_rootURL URLByAppendingPathComponent:@"Temporary" isDirectory:YES];
        [self ensureDirectories];
        [self recoverIncompleteAssets];
    }
    return self;
}

- (void)createAssetWithPhotoData:(NSData *)photoData
                       motionURL:(NSURL *)motionURL
                           event:(RLVCaptureEvent *)event
                    capabilities:(RLVDeviceCapabilities *)capabilities
                      completion:(void (^)(RLVAsset *asset, NSError *error))completion
{
    dispatch_async(_fileQueue, ^{
        NSError *error = nil;
        RLVAsset *asset = nil;
        CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)photoData, NULL);
        NSDictionary *imageProperties = imageSource ? (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL) : nil;
        NSUInteger width = [[imageProperties objectForKey:(id)kCGImagePropertyPixelWidth] unsignedIntegerValue];
        NSUInteger height = [[imageProperties objectForKey:(id)kCGImagePropertyPixelHeight] unsignedIntegerValue];
        if (imageSource) CFRelease(imageSource);
        if (width == 0 || height == 0) {
            error = [self errorWithCode:1 description:@"Captured data is not a valid JPEG image."];
        }

        NSURL *stagingURL = [self.temporaryURL URLByAppendingPathComponent:event.assetId isDirectory:YES];
        NSURL *finalURL = [self.assetsURL URLByAppendingPathComponent:event.assetId isDirectory:YES];
        NSFileManager *manager = [NSFileManager defaultManager];
        if (error == nil && ([manager fileExistsAtPath:[stagingURL path]] || [manager fileExistsAtPath:[finalURL path]])) {
            error = [self errorWithCode:2 description:@"Asset identifier already exists."];
        }
        if (error == nil && ![manager createDirectoryAtURL:stagingURL withIntermediateDirectories:NO attributes:nil error:&error]) {
            // error populated by NSFileManager
        }

        NSURL *photoURL = [stagingURL URLByAppendingPathComponent:@"photo.jpg"];
        if (error == nil && ![photoData writeToURL:photoURL options:NSDataWritingAtomic error:&error]) {
            // error populated by NSData
        }
        NSData *motionData = motionURL && error == nil ? [NSData dataWithContentsOfURL:motionURL options:NSDataReadingMappedIfSafe error:&error] : nil;
        NSURL *stagedMotionURL = [stagingURL URLByAppendingPathComponent:@"motion.mov"];
        if (motionData && error == nil && ![motionData writeToURL:stagedMotionURL options:NSDataWritingAtomic error:&error]) {
            // error populated by NSData
        }
        NSDictionary *manifest = error == nil ? [RLVManifest manifestForEvent:event photoData:photoData motionData:motionData width:width height:height capabilities:capabilities] : nil;
        NSData *manifestData = manifest ? [RLVManifest JSONDataForManifest:manifest error:&error] : nil;
        NSURL *manifestURL = [stagingURL URLByAppendingPathComponent:@"manifest.json"];
        if (error == nil && ![manifestData writeToURL:manifestURL options:NSDataWritingAtomic error:&error]) {
            // error populated by NSData
        }
        if (error == nil && ![self validateAssetAtURL:stagingURL error:&error]) {
            // validation is the final pre-commit gate
        }
        if (error == nil && ![manager moveItemAtURL:stagingURL toURL:finalURL error:&error]) {
            // directory rename is the atomic commit
        }
        if (error == nil) {
            asset = [self loadAssetAtURL:finalURL error:&error];
        }
        if (error != nil) {
            [manager removeItemAtURL:stagingURL error:NULL];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (asset) {
                [[NSNotificationCenter defaultCenter] postNotificationName:RLVAssetStoreDidChangeNotification object:self];
            }
            if (completion) completion(asset, error);
        });
    });
}

- (NSArray *)loadAssets:(NSError **)error
{
    NSArray *children = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:self.assetsURL
                                                      includingPropertiesForKeys:nil options:0 error:error];
    if (!children) return nil;
    NSMutableArray *assets = [NSMutableArray array];
    for (NSURL *url in children) {
        RLVAsset *asset = [self loadAssetAtURL:url error:NULL];
        if (asset) [assets addObject:asset];
    }
    [assets sortUsingComparator:^NSComparisonResult(RLVAsset *first, RLVAsset *second) {
        return [second.createdAt compare:first.createdAt];
    }];
    return assets;
}

- (RLVAsset *)loadAssetWithIdentifier:(NSString *)assetId error:(NSError **)error
{
    return [self loadAssetAtURL:[self.assetsURL URLByAppendingPathComponent:assetId isDirectory:YES] error:error];
}

- (BOOL)deleteAsset:(RLVAsset *)asset error:(NSError **)error
{
    NSURL *directory = [asset.photoURL URLByDeletingLastPathComponent];
    BOOL deleted = [[NSFileManager defaultManager] removeItemAtURL:directory error:error];
    if (deleted) [[NSNotificationCenter defaultCenter] postNotificationName:RLVAssetStoreDidChangeNotification object:self];
    return deleted;
}

- (BOOL)validateAssetAtURL:(NSURL *)assetURL error:(NSError **)error
{
    NSData *manifestData = [NSData dataWithContentsOfURL:[assetURL URLByAppendingPathComponent:@"manifest.json"] options:0 error:error];
    if (!manifestData) return NO;
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:error];
    if (![manifest isKindOfClass:[NSDictionary class]]) return NO;
    NSString *assetId = [manifest objectForKey:@"assetId"];
    id photoValue = [manifest objectForKey:@"photo"];
    id captureValue = [manifest objectForKey:@"capture"];
    id deviceValue = [manifest objectForKey:@"device"];
    NSDictionary *photo = [photoValue isKindOfClass:[NSDictionary class]] ? photoValue : nil;
    NSDictionary *capture = [captureValue isKindOfClass:[NSDictionary class]] ? captureValue : nil;
    NSDictionary *device = [deviceValue isKindOfClass:[NSDictionary class]] ? deviceValue : nil;
    NSString *photoFilename = [photo objectForKey:@"filename"];
    NSURL *photoURL = [assetURL URLByAppendingPathComponent:[photoFilename isKindOfClass:[NSString class]] ? photoFilename : @""];
    NSData *photoData = [NSData dataWithContentsOfURL:photoURL options:0 error:error];
    id motion = [manifest objectForKey:@"motion"];
    NSNumber *stillTimeValue = [capture objectForKey:@"stillImageTimeSeconds"];
    NSNumber *preRollValue = [capture objectForKey:@"preRollSeconds"];
    NSNumber *postRollValue = [capture objectForKey:@"postRollSeconds"];
    double stillTime = [stillTimeValue doubleValue];
    double preRoll = [preRollValue doubleValue];
    double postRoll = [postRollValue doubleValue];
    BOOL motionValid = motion == [NSNull null];
    if ([motion isKindOfClass:[NSDictionary class]]) {
        NSString *motionFilename = [motion objectForKey:@"filename"];
        NSURL *motionURL = [assetURL URLByAppendingPathComponent:[motionFilename isKindOfClass:[NSString class]] ? motionFilename : @""];
        NSData *motionData = [NSData dataWithContentsOfURL:motionURL options:NSDataReadingMappedIfSafe error:NULL];
        NSNumber *durationValue = [motion objectForKey:@"durationSeconds"];
        NSNumber *motionWidth = [motion objectForKey:@"width"];
        NSNumber *motionHeight = [motion objectForKey:@"height"];
        NSNumber *frameRate = [motion objectForKey:@"frameRate"];
        NSNumber *hasAudio = [motion objectForKey:@"hasAudio"];
        NSNumber *motionLength = [motion objectForKey:@"byteLength"];
        NSString *motionHash = [motion objectForKey:@"sha256"];
        double duration = [durationValue doubleValue];
        motionValid = motionData != nil && [motionFilename isEqualToString:@"motion.mov"] &&
            [[motion objectForKey:@"mimeType"] isEqualToString:@"video/quicktime"] &&
            RLVIsNumber(durationValue) && RLVIsNumber(motionWidth) && RLVIsNumber(motionHeight) && RLVIsNumber(frameRate) && RLVIsBoolean(hasAudio) &&
            RLVIsNumber(motionLength) && [motionHash isKindOfClass:[NSString class]] &&
            duration > 0.0 && RLVIsNumber(stillTimeValue) && RLVIsNumber(preRollValue) && RLVIsNumber(postRollValue) &&
            stillTime >= 0.0 && stillTime <= duration && preRoll >= 0.0 && postRoll >= 0.0 &&
            [motionWidth unsignedIntegerValue] > 0 && [motionHeight unsignedIntegerValue] > 0 && [frameRate doubleValue] > 0.0 &&
            [motionLength unsignedLongLongValue] == [motionData length] &&
            [motionHash isEqualToString:[RLVManifest SHA256ForData:motionData]];
    } else if (motion == [NSNull null]) {
        motionValid = RLVIsNumber(stillTimeValue) && RLVIsNumber(preRollValue) && RLVIsNumber(postRollValue) &&
            stillTime == 0.0 && preRoll == 0.0 && postRoll == 0.0;
    }
    NSString *cameraPosition = [capture objectForKey:@"cameraPosition"];
    NSNumber *orientation = [capture objectForKey:@"orientation"];
    NSString *flashMode = [capture objectForKey:@"flashMode"];
    NSString *timeAccuracy = [capture objectForKey:@"stillImageTimeAccuracy"];
    NSNumber *mirrored = [capture objectForKey:@"mirrored"];
    BOOL captureValid = [capture isKindOfClass:[NSDictionary class]] &&
        ([cameraPosition isEqualToString:@"front"] || [cameraPosition isEqualToString:@"back"]) &&
        RLVIsNumber(orientation) && [orientation integerValue] >= 1 && [orientation integerValue] <= 8 &&
        RLVIsBoolean(mirrored) &&
        ([flashMode isEqualToString:@"off"] || [flashMode isEqualToString:@"on"] || [flashMode isEqualToString:@"auto"]) &&
        ([timeAccuracy isEqualToString:@"measured"] || [timeAccuracy isEqualToString:@"estimated"]);
    BOOL deviceValid = [device isKindOfClass:[NSDictionary class]] && RLVIsNonEmptyString([device objectForKey:@"modelIdentifier"]) &&
        RLVIsNonEmptyString([device objectForKey:@"systemVersion"]) && RLVIsNonEmptyString([device objectForKey:@"appVersion"]);
    NSNumber *schemaVersion = [manifest objectForKey:@"schemaVersion"];
    NSNumber *createdMilliseconds = [manifest objectForKey:@"createdAtUnixMilliseconds"];
    NSNumber *photoWidth = [photo objectForKey:@"width"];
    NSNumber *photoHeight = [photo objectForKey:@"height"];
    NSNumber *photoLength = [photo objectForKey:@"byteLength"];
    NSString *photoHash = [photo objectForKey:@"sha256"];
    BOOL valid = RLVIsNumber(schemaVersion) && [schemaVersion integerValue] == 1 && RLVIsNonEmptyString(assetId) &&
        [[NSUUID alloc] initWithUUIDString:assetId] != nil && [assetId isEqualToString:[assetURL lastPathComponent]] &&
        [RLVManifest dateFromISO8601String:[manifest objectForKey:@"createdAt"]] != nil &&
        RLVIsNumber(createdMilliseconds) && [createdMilliseconds longLongValue] >= 0 &&
        captureValid && deviceValid && [photo isKindOfClass:[NSDictionary class]] && photoData != nil &&
        [photoFilename isEqualToString:@"photo.jpg"] && [[photo objectForKey:@"mimeType"] isEqualToString:@"image/jpeg"] &&
        RLVIsNumber(photoWidth) && RLVIsNumber(photoHeight) &&
        [photoWidth unsignedIntegerValue] > 0 && [photoHeight unsignedIntegerValue] > 0 && RLVIsNumber(photoLength) &&
        [photoLength unsignedLongLongValue] == [photoData length] && [photoHash isKindOfClass:[NSString class]] &&
        [photoHash isEqualToString:[RLVManifest SHA256ForData:photoData]] &&
        motionValid;
    if (!valid && error != NULL && *error == nil) {
        *error = [self errorWithCode:3 description:@"Asset validation failed before commit."];
    }
    return valid;
}

- (void)recoverIncompleteAssets
{
    NSArray *children = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:self.temporaryURL
                                                      includingPropertiesForKeys:nil options:0 error:NULL];
    for (NSURL *url in children) {
        [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
    }
}

- (RLVAsset *)loadAssetAtURL:(NSURL *)url error:(NSError **)error
{
    if (![self validateAssetAtURL:url error:error]) return nil;
    NSData *data = [NSData dataWithContentsOfURL:[url URLByAppendingPathComponent:@"manifest.json"] options:0 error:error];
    if (!data) return nil;
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![manifest isKindOfClass:[NSDictionary class]] ||
        ![[manifest objectForKey:@"assetId"] isEqualToString:[url lastPathComponent]] ||
        [[manifest objectForKey:@"schemaVersion"] integerValue] != 1) return nil;
    NSDictionary *photo = [manifest objectForKey:@"photo"];
    NSDictionary *capture = [manifest objectForKey:@"capture"];
    NSDictionary *device = [manifest objectForKey:@"device"];
    NSURL *photoURL = [url URLByAppendingPathComponent:[photo objectForKey:@"filename"] ?: @""];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[photoURL path] error:error];
    if (![photo isKindOfClass:[NSDictionary class]] || !attributes ||
        [[attributes objectForKey:NSFileSize] unsignedLongLongValue] != [[photo objectForKey:@"byteLength"] unsignedLongLongValue]) return nil;
    RLVAsset *asset = [[RLVAsset alloc] init];
    asset.assetId = [manifest objectForKey:@"assetId"];
    asset.createdAt = [RLVManifest dateFromISO8601String:[manifest objectForKey:@"createdAt"]];
    asset.captureTimestamp = [NSDate dateWithTimeIntervalSince1970:[[manifest objectForKey:@"createdAtUnixMilliseconds"] longLongValue] / 1000.0];
    asset.photoURL = photoURL;
    NSURL *motionURL = [url URLByAppendingPathComponent:@"motion.mov"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[motionURL path]]) asset.motionURL = motionURL;
    asset.manifestURL = [url URLByAppendingPathComponent:@"manifest.json"];
    asset.width = [[photo objectForKey:@"width"] unsignedIntegerValue];
    asset.height = [[photo objectForKey:@"height"] unsignedIntegerValue];
    asset.orientation = [[capture objectForKey:@"orientation"] integerValue];
    asset.captureDevice = [device objectForKey:@"modelIdentifier"];
    return asset;
}

- (void)ensureDirectories
{
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager createDirectoryAtURL:self.rootURL withIntermediateDirectories:YES attributes:nil error:NULL];
    [manager createDirectoryAtURL:self.assetsURL withIntermediateDirectories:YES attributes:nil error:NULL];
    [manager createDirectoryAtURL:self.temporaryURL withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description
{
    return [NSError errorWithDomain:RLVAssetStoreErrorDomain code:code
                           userInfo:[NSDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey]];
}

@synthesize rootURL = _rootURL;
@synthesize assetsURL = _assetsURL;
@synthesize temporaryURL = _temporaryURL;

@end
