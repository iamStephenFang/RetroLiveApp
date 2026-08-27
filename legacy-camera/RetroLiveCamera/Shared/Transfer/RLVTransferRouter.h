#import <Foundation/Foundation.h>

@class RLVAssetStore;
@class RLVHTTPResponse;

/// Posted after a client successfully pairs with this router.
extern NSString * const RLVTransferRouterDidPairNotification;
/// `userInfo` key containing the paired client's display name.
extern NSString * const RLVTransferRouterPairedClientNameKey;

/// Validates and routes API v1 requests without owning sockets.
/// Asset paths are resolved through RLVAssetStore rather than constructed from request input.
@interface RLVTransferRouter : NSObject

@property (nonatomic, copy, readonly) NSString *pairingCode;
@property (nonatomic, copy, readonly) NSString *pairedClientName;

/// Creates a router with a fixed device description and six-digit pairing code.
///
/// - Parameters:
///   - assetStore: Store used to resolve validated committed assets.
///   - deviceInfo: Protocol v1 device response fields.
///   - pairingCode: Six-digit code required to establish a session.
/// - Returns: An initialized request router.
- (id)initWithAssetStore:(RLVAssetStore *)assetStore
              deviceInfo:(NSDictionary *)deviceInfo
             pairingCode:(NSString *)pairingCode;
/// Returns a complete response for one parsed request, including authorization and range handling.
///
/// - Parameters:
///   - method: Uppercase HTTP method.
///   - path: Request path rooted at `/api/v1`.
///   - headers: Parsed request headers.
///   - body: Request payload, or `nil` when absent.
/// - Returns: A response suitable for direct serialization by the transfer service.
- (RLVHTTPResponse *)responseForMethod:(NSString *)method
                                  path:(NSString *)path
                               headers:(NSDictionary *)headers
                                  body:(NSData *)body;

@end
