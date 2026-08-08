#import "RLVHTTPResponse.h"

@implementation RLVHTTPResponse

+ (RLVHTTPResponse *)JSONResponseWithStatusCode:(NSInteger)statusCode object:(id)object
{
    RLVHTTPResponse *response = [[RLVHTTPResponse alloc] init];
    response.statusCode = statusCode;
    response.headers = [NSDictionary dictionaryWithObject:@"application/json; charset=utf-8" forKey:@"Content-Type"];
    response.body = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
    return response;
}

@synthesize statusCode = _statusCode;
@synthesize headers = _headers;
@synthesize body = _body;
@synthesize fileURL = _fileURL;
@synthesize fileOffset = _fileOffset;
@synthesize fileLength = _fileLength;

@end
