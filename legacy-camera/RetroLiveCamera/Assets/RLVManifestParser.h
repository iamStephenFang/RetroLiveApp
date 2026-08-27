#import <Foundation/Foundation.h>

@class RLVAssetManifest;

/// Error domain used for schema and value validation failures.
extern NSString * const RLVManifestParserErrorDomain;

/// Stable parser failure categories; detailed field information is carried by NSError.
typedef enum {
    RLVManifestParserErrorInvalidJSON = 1,
    RLVManifestParserErrorMissingValue = 2,
    RLVManifestParserErrorInvalidValue = 3,
    RLVManifestParserErrorUnsupportedSchema = 4
} RLVManifestParserErrorCode;

/// Parses and validates Manifest V1 data without accessing referenced media files.
@interface RLVManifestParser : NSObject
/// Returns a populated manifest, or nil with a parser-domain error for invalid input.
- (RLVAssetManifest *)manifestFromData:(NSData *)data error:(NSError **)error;
@end
