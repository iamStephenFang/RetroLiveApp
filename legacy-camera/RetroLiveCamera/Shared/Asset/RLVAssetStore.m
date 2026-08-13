#import "RLVAssetStore.h"
#import "RLVManifest.h"
#import <ImageIO/ImageIO.h>
#import <math.h>

NSString * const RLVAssetStoreDidChangeNotification = @"RLVAssetStoreDidChangeNotification";
NSString * const RLVAssetStoreErrorDomain = @"com.retrolive.asset-store";
static void *RLVAssetStoreFileQueueKey = &RLVAssetStoreFileQueueKey;

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

static BOOL RLVIsSafeFilename(id value)
{
    if (!RLVIsNonEmptyString(value) || [value isEqualToString:@"."] || [value isEqualToString:@".."]) return NO;
    return [value rangeOfString:@"/"].location == NSNotFound &&
        [value rangeOfString:@"\\"].location == NSNotFound;
}

static BOOL RLVIsLowercaseSHA256(id value)
{
    if (![value isKindOfClass:[NSString class]] || [value length] != 64) return NO;
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet];
    return [value rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

@interface RLVAssetStore () {
    dispatch_queue_t _fileQueue;
}
@property (nonatomic, strong, readwrite) NSURL *rootURL;
@property (nonatomic, strong, readwrite) NSURL *assetsURL;
@property (nonatomic, strong, readwrite) NSURL *temporaryURL;
@property (nonatomic, strong) NSArray *cachedAssets;
- (NSArray *)cachedAssetsLoadingFromDiskIfNeeded:(NSError **)error;
- (NSArray *)loadAssetsFromDisk:(NSError **)error;
- (RLVAsset *)loadAssetMetadataAtURL:(NSURL *)url error:(NSError **)error;
- (NSData *)thumbnailDataForPhotoData:(NSData *)photoData
                         maxPixelSize:(NSUInteger)maxPixelSize
                                width:(NSUInteger *)width
                               height:(NSUInteger *)height;
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
        dispatch_queue_set_specific(_fileQueue, RLVAssetStoreFileQueueKey, (__bridge void *)self, NULL);
        _rootURL = [documentsURL URLByAppendingPathComponent:@"RetroLive" isDirectory:YES];
        _assetsURL = [_rootURL URLByAppendingPathComponent:@"Assets" isDirectory:YES];
        _temporaryURL = [_rootURL URLByAppendingPathComponent:@"Temporary" isDirectory:YES];
        [self ensureDirectories];
        dispatch_async(_fileQueue, ^{ [self recoverIncompleteAssets]; });
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
            error = [self errorWithCode:1 description:NSLocalizedString(@"asset.error.invalid_jpeg", nil)];
        }

        NSUUID *eventUUID = [[NSUUID alloc] initWithUUIDString:event.assetId];
        if (error == nil && (eventUUID == nil || ![[eventUUID UUIDString] isEqualToString:event.assetId])) {
            error = [self errorWithCode:4 description:NSLocalizedString(@"asset.error.uuid_required", nil)];
        }

        NSURL *stagingURL = [self.temporaryURL URLByAppendingPathComponent:event.assetId isDirectory:YES];
        NSURL *finalURL = [self.assetsURL URLByAppendingPathComponent:event.assetId isDirectory:YES];
        NSFileManager *manager = [NSFileManager defaultManager];
        if (error == nil && ([manager fileExistsAtPath:[stagingURL path]] || [manager fileExistsAtPath:[finalURL path]])) {
            error = [self errorWithCode:2 description:NSLocalizedString(@"asset.error.already_exists", nil)];
        }
        if (error == nil && ![manager createDirectoryAtURL:stagingURL withIntermediateDirectories:NO attributes:nil error:&error]) {
            // error populated by NSFileManager
        }

        NSURL *photoURL = [stagingURL URLByAppendingPathComponent:@"photo.jpg"];
        if (error == nil && ![photoData writeToURL:photoURL options:NSDataWritingAtomic error:&error]) {
            // error populated by NSData
        }
        NSUInteger thumbnailWidth = 0;
        NSUInteger thumbnailHeight = 0;
        NSData *thumbnailData = error == nil ? [self thumbnailDataForPhotoData:photoData
                                                                  maxPixelSize:320
                                                                         width:&thumbnailWidth
                                                                        height:&thumbnailHeight] : nil;
        NSURL *thumbnailURL = [stagingURL URLByAppendingPathComponent:@"thumbnail.jpg"];
        if (thumbnailData && ![thumbnailData writeToURL:thumbnailURL options:NSDataWritingAtomic error:&error]) {
            // A generated thumbnail is part of the transaction once written.
        }
        NSData *motionData = motionURL && error == nil ? [NSData dataWithContentsOfURL:motionURL options:NSDataReadingMappedIfSafe error:&error] : nil;
        NSURL *stagedMotionURL = [stagingURL URLByAppendingPathComponent:@"motion.mov"];
        if (motionData && error == nil && ![motionData writeToURL:stagedMotionURL options:NSDataWritingAtomic error:&error]) {
            // error populated by NSData
        }
        NSDictionary *manifest = error == nil ? [RLVManifest manifestForEvent:event
                                                                     photoData:photoData
                                                                    motionData:motionData
                                                                 thumbnailData:thumbnailData
                                                                         width:width
                                                                        height:height
                                                                thumbnailWidth:thumbnailWidth
                                                               thumbnailHeight:thumbnailHeight
                                                                  capabilities:capabilities] : nil;
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
        if (asset && self.cachedAssets) {
            NSMutableArray *updatedAssets = [self.cachedAssets mutableCopy];
            [updatedAssets addObject:asset];
            [updatedAssets sortUsingComparator:^NSComparisonResult(RLVAsset *first, RLVAsset *second) {
                return [second.createdAt compare:first.createdAt];
            }];
            self.cachedAssets = [NSArray arrayWithArray:updatedAssets];
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
    __block NSArray *assets = nil;
    __block NSError *loadError = nil;
    void (^loadBlock)(void) = ^{
        assets = [self cachedAssetsLoadingFromDiskIfNeeded:&loadError];
    };
    if (dispatch_get_specific(RLVAssetStoreFileQueueKey) == (__bridge void *)self) {
        loadBlock();
    } else {
        dispatch_sync(_fileQueue, loadBlock);
    }
    if (error) *error = loadError;
    return assets;
}

- (void)loadAssetsWithCompletion:(void (^)(NSArray *assets, NSError *error))completion
{
    dispatch_async(_fileQueue, ^{
        NSError *error = nil;
        NSArray *assets = [self cachedAssetsLoadingFromDiskIfNeeded:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(assets, error);
        });
    });
}

- (NSArray *)cachedAssetsLoadingFromDiskIfNeeded:(NSError **)error
{
    if (self.cachedAssets) return self.cachedAssets;
    NSArray *assets = [self loadAssetsFromDisk:error];
    if (assets) self.cachedAssets = assets;
    return assets;
}

- (NSArray *)loadAssetsFromDisk:(NSError **)error
{
    NSArray *children = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:self.assetsURL
                                                      includingPropertiesForKeys:nil options:0 error:error];
    if (!children) return nil;
    NSMutableArray *assets = [NSMutableArray array];
    for (NSURL *url in children) {
        RLVAsset *asset = [self loadAssetMetadataAtURL:url error:NULL];
        if (asset) [assets addObject:asset];
    }
    [assets sortUsingComparator:^NSComparisonResult(RLVAsset *first, RLVAsset *second) {
        return [second.createdAt compare:first.createdAt];
    }];
    return assets;
}

- (RLVAsset *)loadAssetWithIdentifier:(NSString *)assetId error:(NSError **)error
{
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:assetId];
    if (!uuid) {
        if (error) *error = [self errorWithCode:4 description:NSLocalizedString(@"asset.error.invalid_id", nil)];
        return nil;
    }
    __block RLVAsset *matchedAsset = nil;
    __block NSError *loadError = nil;
    void (^loadBlock)(void) = ^{
        NSArray *assets = [self cachedAssetsLoadingFromDiskIfNeeded:&loadError];
        for (RLVAsset *asset in assets) {
            if ([asset.assetId isEqualToString:[uuid UUIDString]]) {
                matchedAsset = asset;
                break;
            }
        }
    };
    if (dispatch_get_specific(RLVAssetStoreFileQueueKey) == (__bridge void *)self) loadBlock();
    else dispatch_sync(_fileQueue, loadBlock);
    if (error) *error = loadError;
    return matchedAsset;
}

- (BOOL)deleteAsset:(RLVAsset *)asset error:(NSError **)error
{
    __block BOOL deleted = NO;
    __block NSError *deleteError = nil;
    void (^deleteBlock)(void) = ^{
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:asset.assetId];
        NSURL *directory = [asset.photoURL URLByDeletingLastPathComponent];
        NSURL *expectedDirectory = uuid ? [self.assetsURL URLByAppendingPathComponent:[uuid UUIDString] isDirectory:YES] : nil;
        if (!expectedDirectory || ![[directory URLByStandardizingPath] isEqual:[expectedDirectory URLByStandardizingPath]]) {
            deleteError = [self errorWithCode:4 description:NSLocalizedString(@"asset.error.outside_store", nil)];
            return;
        }
        deleted = [[NSFileManager defaultManager] removeItemAtURL:directory error:&deleteError];
        if (deleted) self.cachedAssets = nil;
    };
    if (dispatch_get_specific(RLVAssetStoreFileQueueKey) == (__bridge void *)self) {
        deleteBlock();
    } else {
        dispatch_sync(_fileQueue, deleteBlock);
    }
    if (error) *error = deleteError;
    if (deleted) {
        void (^notifyBlock)(void) = ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:RLVAssetStoreDidChangeNotification object:self];
        };
        if ([NSThread isMainThread]) notifyBlock();
        else dispatch_async(dispatch_get_main_queue(), notifyBlock);
    }
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
    id thumbnailValue = [manifest objectForKey:@"thumbnail"];
    BOOL thumbnailValid = thumbnailValue == nil;
    if ([thumbnailValue isKindOfClass:[NSDictionary class]]) {
        NSDictionary *thumbnail = thumbnailValue;
        NSString *thumbnailFilename = [thumbnail objectForKey:@"filename"];
        NSURL *thumbnailURL = [assetURL URLByAppendingPathComponent:[thumbnailFilename isKindOfClass:[NSString class]] ? thumbnailFilename : @""];
        NSData *thumbnailData = [NSData dataWithContentsOfURL:thumbnailURL options:0 error:NULL];
        NSNumber *thumbnailWidth = [thumbnail objectForKey:@"width"];
        NSNumber *thumbnailHeight = [thumbnail objectForKey:@"height"];
        NSNumber *thumbnailLength = [thumbnail objectForKey:@"byteLength"];
        NSString *thumbnailHash = [thumbnail objectForKey:@"sha256"];
        thumbnailValid = thumbnailData != nil && [thumbnailFilename isEqualToString:@"thumbnail.jpg"] &&
            [[thumbnail objectForKey:@"mimeType"] isEqualToString:@"image/jpeg"] &&
            RLVIsNumber(thumbnailWidth) && [thumbnailWidth unsignedIntegerValue] > 0 &&
            RLVIsNumber(thumbnailHeight) && [thumbnailHeight unsignedIntegerValue] > 0 &&
            RLVIsNumber(thumbnailLength) && [thumbnailLength unsignedLongLongValue] == [thumbnailData length] &&
            [thumbnailHash isKindOfClass:[NSString class]] &&
            [thumbnailHash isEqualToString:[RLVManifest SHA256ForData:thumbnailData]];
    }
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
            stillTime >= 0.0 && stillTime < duration && preRoll >= 0.0 && postRoll >= 0.0 &&
            [motionWidth unsignedIntegerValue] > 0 && [motionHeight unsignedIntegerValue] > 0 && [frameRate doubleValue] > 0.0 &&
            [motionLength unsignedLongLongValue] > 0 && [motionLength unsignedLongLongValue] == [motionData length] &&
            [motionHash isEqualToString:[RLVManifest SHA256ForData:motionData]];
    } else if (motion == [NSNull null]) {
        motionValid = RLVIsNumber(stillTimeValue) && RLVIsNumber(preRollValue) && RLVIsNumber(postRollValue) &&
            stillTime == 0.0 && preRoll == 0.0 && postRoll == 0.0;
    }
    NSString *cameraPosition = [capture objectForKey:@"cameraPosition"];
    NSNumber *orientation = [capture objectForKey:@"orientation"];
    NSString *flashMode = [capture objectForKey:@"flashMode"];
    NSString *timeAccuracy = [capture objectForKey:@"stillImageTimeAccuracy"];
    NSString *aspectRatio = [capture objectForKey:@"aspectRatio"];
    NSNumber *mirrored = [capture objectForKey:@"mirrored"];
    BOOL captureValid = [capture isKindOfClass:[NSDictionary class]] &&
        ([cameraPosition isEqualToString:@"front"] || [cameraPosition isEqualToString:@"back"]) &&
        RLVIsNumber(orientation) && [orientation integerValue] >= 1 && [orientation integerValue] <= 8 &&
        RLVIsBoolean(mirrored) &&
        ([flashMode isEqualToString:@"off"] || [flashMode isEqualToString:@"on"] || [flashMode isEqualToString:@"auto"]) &&
        (aspectRatio == nil || [aspectRatio isEqualToString:@"4:3"] || [aspectRatio isEqualToString:@"1:1"] ||
            [aspectRatio isEqualToString:@"16:9"]) &&
        ([timeAccuracy isEqualToString:@"measured"] || [timeAccuracy isEqualToString:@"estimated"]);
    BOOL deviceValid = [device isKindOfClass:[NSDictionary class]] && RLVIsNonEmptyString([device objectForKey:@"modelIdentifier"]) &&
        RLVIsNonEmptyString([device objectForKey:@"systemVersion"]) && RLVIsNonEmptyString([device objectForKey:@"appVersion"]);
    NSNumber *schemaVersion = [manifest objectForKey:@"schemaVersion"];
    NSNumber *createdMilliseconds = [manifest objectForKey:@"createdAtUnixMilliseconds"];
    NSDate *createdDate = [RLVManifest dateFromISO8601String:[manifest objectForKey:@"createdAt"]];
    double createdDifference = fabs([createdDate timeIntervalSince1970] * 1000.0 - [createdMilliseconds longLongValue]);
    NSNumber *photoWidth = [photo objectForKey:@"width"];
    NSNumber *photoHeight = [photo objectForKey:@"height"];
    NSNumber *photoLength = [photo objectForKey:@"byteLength"];
    NSString *photoHash = [photo objectForKey:@"sha256"];
    BOOL valid = RLVIsNumber(schemaVersion) && [schemaVersion integerValue] == 1 && RLVIsNonEmptyString(assetId) &&
        [[NSUUID alloc] initWithUUIDString:assetId] != nil && [assetId isEqualToString:[assetURL lastPathComponent]] &&
        createdDate != nil && RLVIsNumber(createdMilliseconds) && [createdMilliseconds longLongValue] >= 0 &&
        createdDifference <= 1.0 &&
        captureValid && deviceValid && [photo isKindOfClass:[NSDictionary class]] && photoData != nil &&
        [photoFilename isEqualToString:@"photo.jpg"] && [[photo objectForKey:@"mimeType"] isEqualToString:@"image/jpeg"] &&
        RLVIsNumber(photoWidth) && RLVIsNumber(photoHeight) &&
        [photoWidth unsignedIntegerValue] > 0 && [photoHeight unsignedIntegerValue] > 0 && RLVIsNumber(photoLength) &&
        [photoLength unsignedLongLongValue] > 0 && [photoLength unsignedLongLongValue] == [photoData length] && [photoHash isKindOfClass:[NSString class]] &&
        [photoHash isEqualToString:[RLVManifest SHA256ForData:photoData]] &&
        motionValid && thumbnailValid;
    if (!valid && error != NULL && *error == nil) {
        *error = [self errorWithCode:3 description:NSLocalizedString(@"asset.error.validation_failed", nil)];
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
    return [self loadAssetMetadataAtURL:url error:error];
}

- (RLVAsset *)loadAssetMetadataAtURL:(NSURL *)url error:(NSError **)error
{
    NSData *data = [NSData dataWithContentsOfURL:[url URLByAppendingPathComponent:@"manifest.json"] options:0 error:error];
    if (!data) return nil;
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![manifest isKindOfClass:[NSDictionary class]]) return nil;
    NSNumber *schemaVersion = [manifest objectForKey:@"schemaVersion"];
    NSString *assetId = [manifest objectForKey:@"assetId"];
    id photoValue = [manifest objectForKey:@"photo"];
    id captureValue = [manifest objectForKey:@"capture"];
    id deviceValue = [manifest objectForKey:@"device"];
    NSDictionary *photo = [photoValue isKindOfClass:[NSDictionary class]] ? photoValue : nil;
    NSDictionary *capture = [captureValue isKindOfClass:[NSDictionary class]] ? captureValue : nil;
    NSDictionary *device = [deviceValue isKindOfClass:[NSDictionary class]] ? deviceValue : nil;
    NSString *photoFilename = [photo objectForKey:@"filename"];
    NSString *photoHash = [photo objectForKey:@"sha256"];
    NSNumber *photoLength = [photo objectForKey:@"byteLength"];
    NSDate *createdAt = [RLVManifest dateFromISO8601String:[manifest objectForKey:@"createdAt"]];
    NSNumber *createdMilliseconds = [manifest objectForKey:@"createdAtUnixMilliseconds"];
    double createdDifference = fabs([createdAt timeIntervalSince1970] * 1000.0 - [createdMilliseconds longLongValue]);
    NSString *cameraPosition = [capture objectForKey:@"cameraPosition"];
    NSNumber *orientation = [capture objectForKey:@"orientation"];
    NSNumber *mirrored = [capture objectForKey:@"mirrored"];
    NSString *flashMode = [capture objectForKey:@"flashMode"];
    NSString *timeAccuracy = [capture objectForKey:@"stillImageTimeAccuracy"];
    NSString *aspectRatio = [capture objectForKey:@"aspectRatio"];
    NSNumber *stillTime = [capture objectForKey:@"stillImageTimeSeconds"];
    NSNumber *preRoll = [capture objectForKey:@"preRollSeconds"];
    NSNumber *postRoll = [capture objectForKey:@"postRollSeconds"];
    BOOL captureValid = ([cameraPosition isEqualToString:@"front"] || [cameraPosition isEqualToString:@"back"]) &&
        RLVIsNumber(orientation) && [orientation integerValue] >= 1 && [orientation integerValue] <= 8 &&
        RLVIsBoolean(mirrored) && ([flashMode isEqualToString:@"off"] || [flashMode isEqualToString:@"on"] ||
        [flashMode isEqualToString:@"auto"]) && (aspectRatio == nil || [aspectRatio isEqualToString:@"4:3"] ||
        [aspectRatio isEqualToString:@"1:1"] || [aspectRatio isEqualToString:@"16:9"]) &&
        ([timeAccuracy isEqualToString:@"measured"] || [timeAccuracy isEqualToString:@"estimated"]) &&
        RLVIsNumber(stillTime) && [stillTime doubleValue] >= 0.0 && RLVIsNumber(preRoll) && [preRoll doubleValue] >= 0.0 &&
        RLVIsNumber(postRoll) && [postRoll doubleValue] >= 0.0;
    BOOL deviceValid = RLVIsNonEmptyString([device objectForKey:@"modelIdentifier"]) &&
        RLVIsNonEmptyString([device objectForKey:@"systemVersion"]) &&
        RLVIsNonEmptyString([device objectForKey:@"appVersion"]);
    if (!RLVIsNumber(schemaVersion) || [schemaVersion integerValue] != 1 || !RLVIsNonEmptyString(assetId) ||
        [[NSUUID alloc] initWithUUIDString:assetId] == nil || ![assetId isEqualToString:[url lastPathComponent]] ||
        !createdAt || !RLVIsNumber(createdMilliseconds) || [createdMilliseconds longLongValue] < 0 || createdDifference > 1.0 ||
        !photo || !capture || !device || !captureValid || !deviceValid ||
        ![photoFilename isEqualToString:@"photo.jpg"] || !RLVIsSafeFilename(photoFilename) ||
        ![[photo objectForKey:@"mimeType"] isEqualToString:@"image/jpeg"] ||
        !RLVIsNumber(photoLength) || [photoLength unsignedLongLongValue] == 0 ||
        !RLVIsLowercaseSHA256(photoHash) || !RLVIsNumber([photo objectForKey:@"width"]) ||
        !RLVIsNumber([photo objectForKey:@"height"]) || [[photo objectForKey:@"width"] unsignedIntegerValue] == 0 ||
        [[photo objectForKey:@"height"] unsignedIntegerValue] == 0 || ![capture isKindOfClass:[NSDictionary class]] ||
        ![device isKindOfClass:[NSDictionary class]]) return nil;

    NSURL *photoURL = [url URLByAppendingPathComponent:photoFilename];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[photoURL path] error:error];
    if (!attributes || [[attributes objectForKey:NSFileSize] unsignedLongLongValue] != [photoLength unsignedLongLongValue]) return nil;

    NSDictionary *thumbnail = [[manifest objectForKey:@"thumbnail"] isKindOfClass:[NSDictionary class]] ?
        [manifest objectForKey:@"thumbnail"] : nil;
    NSURL *thumbnailURL = nil;
    if (thumbnail) {
        NSString *filename = [thumbnail objectForKey:@"filename"];
        NSNumber *length = [thumbnail objectForKey:@"byteLength"];
        thumbnailURL = [url URLByAppendingPathComponent:RLVIsSafeFilename(filename) ? filename : @""];
        NSDictionary *thumbnailAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[thumbnailURL path] error:NULL];
        if (![filename isEqualToString:@"thumbnail.jpg"] || ![[thumbnail objectForKey:@"mimeType"] isEqualToString:@"image/jpeg"] ||
            !RLVIsNumber(length) || [length unsignedLongLongValue] == 0 || !RLVIsLowercaseSHA256([thumbnail objectForKey:@"sha256"]) ||
            !RLVIsNumber([thumbnail objectForKey:@"width"]) || [[thumbnail objectForKey:@"width"] unsignedIntegerValue] == 0 ||
            !RLVIsNumber([thumbnail objectForKey:@"height"]) || [[thumbnail objectForKey:@"height"] unsignedIntegerValue] == 0 ||
            !thumbnailAttributes || [[thumbnailAttributes objectForKey:NSFileSize] unsignedLongLongValue] != [length unsignedLongLongValue]) return nil;
    } else if ([manifest objectForKey:@"thumbnail"] != nil) {
        return nil;
    }

    NSDictionary *motion = [[manifest objectForKey:@"motion"] isKindOfClass:[NSDictionary class]] ?
        [manifest objectForKey:@"motion"] : nil;
    NSURL *motionURL = nil;
    if (motion) {
        NSString *filename = [motion objectForKey:@"filename"];
        NSNumber *length = [motion objectForKey:@"byteLength"];
        motionURL = [url URLByAppendingPathComponent:RLVIsSafeFilename(filename) ? filename : @""];
        NSDictionary *motionAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[motionURL path] error:NULL];
        if (![filename isEqualToString:@"motion.mov"] || ![[motion objectForKey:@"mimeType"] isEqualToString:@"video/quicktime"] ||
            !RLVIsNumber(length) || [length unsignedLongLongValue] == 0 || !RLVIsLowercaseSHA256([motion objectForKey:@"sha256"]) ||
            !RLVIsNumber([motion objectForKey:@"durationSeconds"]) || [[motion objectForKey:@"durationSeconds"] doubleValue] <= 0.0 ||
            !RLVIsNumber([motion objectForKey:@"width"]) || [[motion objectForKey:@"width"] unsignedIntegerValue] == 0 ||
            !RLVIsNumber([motion objectForKey:@"height"]) || [[motion objectForKey:@"height"] unsignedIntegerValue] == 0 ||
            !RLVIsNumber([motion objectForKey:@"frameRate"]) || [[motion objectForKey:@"frameRate"] doubleValue] <= 0.0 ||
            !RLVIsBoolean([motion objectForKey:@"hasAudio"]) || [stillTime doubleValue] >= [[motion objectForKey:@"durationSeconds"] doubleValue] ||
            !motionAttributes || [[motionAttributes objectForKey:NSFileSize] unsignedLongLongValue] != [length unsignedLongLongValue]) return nil;
    } else if ([manifest objectForKey:@"motion"] != [NSNull null]) {
        return nil;
    } else if ([stillTime doubleValue] != 0.0 || [preRoll doubleValue] != 0.0 || [postRoll doubleValue] != 0.0) {
        return nil;
    }

    RLVAsset *asset = [[RLVAsset alloc] init];
    asset.assetId = assetId;
    asset.createdAt = createdAt;
    asset.captureTimestamp = [NSDate dateWithTimeIntervalSince1970:[[manifest objectForKey:@"createdAtUnixMilliseconds"] longLongValue] / 1000.0];
    asset.photoURL = photoURL;
    asset.thumbnailURL = thumbnailURL;
    asset.motionURL = motionURL;
    asset.manifestURL = [url URLByAppendingPathComponent:@"manifest.json"];
    asset.width = [[photo objectForKey:@"width"] unsignedIntegerValue];
    asset.height = [[photo objectForKey:@"height"] unsignedIntegerValue];
    asset.motionWidth = [[motion objectForKey:@"width"] unsignedIntegerValue];
    asset.motionHeight = [[motion objectForKey:@"height"] unsignedIntegerValue];
    asset.orientation = [[capture objectForKey:@"orientation"] integerValue];
    asset.captureDevice = [device objectForKey:@"modelIdentifier"];
    asset.aspectRatio = [capture objectForKey:@"aspectRatio"] ?: @"native";
    return asset;
}

- (NSData *)thumbnailDataForPhotoData:(NSData *)photoData
                         maxPixelSize:(NSUInteger)maxPixelSize
                                width:(NSUInteger *)width
                               height:(NSUInteger *)height
{
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)photoData, NULL);
    if (!source) return nil;
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool:YES], (id)kCGImageSourceCreateThumbnailFromImageAlways,
        [NSNumber numberWithBool:YES], (id)kCGImageSourceCreateThumbnailWithTransform,
        [NSNumber numberWithUnsignedInteger:maxPixelSize], (id)kCGImageSourceThumbnailMaxPixelSize, nil];
    CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!image) return nil;
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData(
        (__bridge CFMutableDataRef)data,
        CFSTR("public.jpeg"),
        1,
        NULL
    );
    if (!destination) {
        CGImageRelease(image);
        return nil;
    }
    NSDictionary *properties = [NSDictionary dictionaryWithObject:[NSNumber numberWithDouble:0.78]
                                                             forKey:(id)kCGImageDestinationLossyCompressionQuality];
    CGImageDestinationAddImage(destination, image, (__bridge CFDictionaryRef)properties);
    BOOL finalized = CGImageDestinationFinalize(destination);
    if (width) *width = CGImageGetWidth(image);
    if (height) *height = CGImageGetHeight(image);
    CFRelease(destination);
    CGImageRelease(image);
    return finalized ? [NSData dataWithData:data] : nil;
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
@synthesize cachedAssets = _cachedAssets;

@end
