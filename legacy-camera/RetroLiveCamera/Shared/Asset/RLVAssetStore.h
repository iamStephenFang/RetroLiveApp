#import "RLVAsset.h"
#import "RLVDeviceCapabilities.h"
#import <Foundation/Foundation.h>

extern NSString * const RLVAssetStoreDidChangeNotification;

@interface RLVAssetStore : NSObject

@property (nonatomic, strong, readonly) NSURL *rootURL;
@property (nonatomic, strong, readonly) NSURL *assetsURL;
@property (nonatomic, strong, readonly) NSURL *temporaryURL;

+ (RLVAssetStore *)sharedStore;
- (id)initWithDocumentsURL:(NSURL *)documentsURL;
- (void)createAssetWithPhotoData:(NSData *)photoData
                           event:(RLVCaptureEvent *)event
                    capabilities:(RLVDeviceCapabilities *)capabilities
                      completion:(void (^)(RLVAsset *asset, NSError *error))completion;
- (NSArray *)loadAssets:(NSError **)error;
- (RLVAsset *)loadAssetWithIdentifier:(NSString *)assetId error:(NSError **)error;
- (BOOL)deleteAsset:(RLVAsset *)asset error:(NSError **)error;
- (BOOL)validateAssetAtURL:(NSURL *)assetURL error:(NSError **)error;
- (void)recoverIncompleteAssets;

@end
