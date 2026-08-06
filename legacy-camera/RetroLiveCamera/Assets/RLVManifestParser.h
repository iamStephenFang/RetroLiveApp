#import <Foundation/Foundation.h>

@class RLVAssetManifest;

extern NSString * const RLVManifestParserErrorDomain;

typedef enum {
    RLVManifestParserErrorInvalidJSON = 1,
    RLVManifestParserErrorMissingValue = 2,
    RLVManifestParserErrorInvalidValue = 3,
    RLVManifestParserErrorUnsupportedSchema = 4
} RLVManifestParserErrorCode;

@interface RLVManifestParser : NSObject
- (RLVAssetManifest *)manifestFromData:(NSData *)data error:(NSError **)error;
@end

