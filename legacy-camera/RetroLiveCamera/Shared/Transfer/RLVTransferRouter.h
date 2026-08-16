#import <Foundation/Foundation.h>

@class RLVAssetStore;
@class RLVHTTPResponse;

extern NSString * const RLVTransferRouterDidPairNotification;
extern NSString * const RLVTransferRouterPairedClientNameKey;

@interface RLVTransferRouter : NSObject

@property (nonatomic, copy, readonly) NSString *pairingCode;
@property (nonatomic, copy, readonly) NSString *pairedClientName;

- (id)initWithAssetStore:(RLVAssetStore *)assetStore
              deviceInfo:(NSDictionary *)deviceInfo
             pairingCode:(NSString *)pairingCode;
- (RLVHTTPResponse *)responseForMethod:(NSString *)method
                                  path:(NSString *)path
                               headers:(NSDictionary *)headers
                                  body:(NSData *)body;

@end
