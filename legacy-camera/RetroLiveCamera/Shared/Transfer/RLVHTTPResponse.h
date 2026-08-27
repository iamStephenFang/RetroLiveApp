#import <Foundation/Foundation.h>

/// Transport-neutral HTTP response produced by the router and written by the service.
@interface RLVHTTPResponse : NSObject

@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, copy) NSDictionary *headers;
/// In-memory response body. Mutually exclusive with fileURL.
@property (nonatomic, strong) NSData *body;
/// File-backed response body used for streaming immutable media. Mutually exclusive with body.
@property (nonatomic, strong) NSURL *fileURL;
/// Inclusive start offset for a file-backed response.
@property (nonatomic, assign) unsigned long long fileOffset;
/// Number of bytes to stream from fileOffset.
@property (nonatomic, assign) unsigned long long fileLength;

/// Creates a JSON response and applies the appropriate content type.
+ (RLVHTTPResponse *)JSONResponseWithStatusCode:(NSInteger)statusCode object:(id)object;

@end
