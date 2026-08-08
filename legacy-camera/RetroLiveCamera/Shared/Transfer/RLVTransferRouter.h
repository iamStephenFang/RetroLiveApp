#import <Foundation/Foundation.h>

@class RLVAssetStore;
@class RLVHTTPResponse;

@interface RLVTransferRouter : NSObject

@property (nonatomic, copy, readonly) NSString *pairingCode;

- (id)initWithAssetStore:(RLVAssetStore *)assetStore
              deviceInfo:(NSDictionary *)deviceInfo
             pairingCode:(NSString *)pairingCode;
- (RLVHTTPResponse *)responseForMethod:(NSString *)method
                                  path:(NSString *)path
                               headers:(NSDictionary *)headers
                                  body:(NSData *)body;

@end
