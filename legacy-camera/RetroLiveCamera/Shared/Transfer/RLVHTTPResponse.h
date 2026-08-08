#import <Foundation/Foundation.h>

@interface RLVHTTPResponse : NSObject

@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, copy) NSDictionary *headers;
@property (nonatomic, strong) NSData *body;
@property (nonatomic, strong) NSURL *fileURL;
@property (nonatomic, assign) unsigned long long fileOffset;
@property (nonatomic, assign) unsigned long long fileLength;

+ (RLVHTTPResponse *)JSONResponseWithStatusCode:(NSInteger)statusCode object:(id)object;

@end
