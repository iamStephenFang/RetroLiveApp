#import "RLVAsset.h"
#import "RLVDeviceCapabilities.h"
#import <Foundation/Foundation.h>

/// Posted on the main thread after the committed asset collection changes.
extern NSString * const RLVAssetStoreDidChangeNotification;

/// Owns camera-side staging, validation, atomic commit, discovery, deletion, and recovery.
/// Only fully committed assets are returned to callers or exposed to transfer code.
@interface RLVAssetStore : NSObject

@property (nonatomic, strong, readonly) NSURL *rootURL;
@property (nonatomic, strong, readonly) NSURL *assetsURL;
@property (nonatomic, strong, readonly) NSURL *temporaryURL;

+ (RLVAssetStore *)sharedStore;
/// Creates an isolated store rooted beneath the supplied documents directory, primarily for tests.
///
/// - Parameter documentsURL: Existing documents directory beneath which the store creates its root.
/// - Returns: An initialized asset store.
- (id)initWithDocumentsURL:(NSURL *)documentsURL;
/// Validates and atomically commits captured resources. `motionURL` may be nil for a photo-only asset.
/// The completion block is delivered on the main thread with exactly one of asset or error.
///
/// - Parameters:
///   - photoData: JPEG data for the required still resource.
///   - motionURL: Optional temporary URL for the captured motion companion.
///   - event: Shutter-time identity and capture metadata.
///   - capabilities: Device metadata recorded in the manifest.
///   - completion: Main-thread callback containing either the committed asset or an error.
- (void)createAssetWithPhotoData:(NSData *)photoData
                       motionURL:(NSURL *)motionURL
                           event:(RLVCaptureEvent *)event
                    capabilities:(RLVDeviceCapabilities *)capabilities
                      completion:(void (^)(RLVAsset *asset, NSError *error))completion;
/// Synchronously returns committed assets ordered newest first.
///
/// - Parameter error: Receives a filesystem or validation error, or may be `NULL`.
/// - Returns: The committed asset snapshot, or `nil` when loading fails.
- (NSArray *)loadAssets:(NSError **)error;
/// Loads committed assets away from the caller and delivers the result on the main thread.
- (void)loadAssetsWithCompletion:(void (^)(NSArray *assets, NSError *error))completion;
/// Resolves only a valid committed asset identifier; returns nil for missing or invalid assets.
///
/// - Parameters:
///   - assetId: Canonical UUID string identifying the committed asset.
///   - error: Receives a validation or filesystem error, or may be `NULL`.
/// - Returns: The matching committed asset, or `nil`.
- (RLVAsset *)loadAssetWithIdentifier:(NSString *)assetId error:(NSError **)error;
/// Permanently removes the supplied committed asset directory.
- (BOOL)deleteAsset:(RLVAsset *)asset error:(NSError **)error;
/// Verifies required files and Manifest V1 length/hash metadata without modifying the asset.
- (BOOL)validateAssetAtURL:(NSURL *)assetURL error:(NSError **)error;
/// Removes abandoned staging data while preserving every committed asset.
- (void)recoverIncompleteAssets;

@end
