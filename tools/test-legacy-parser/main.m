#import <Foundation/Foundation.h>
#include <string.h>
#import "RLVAssetManifest.h"
#import "RLVManifestParser.h"

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        BOOL expectInvalid = argc == 3 && strcmp(argv[1], "--expect-invalid") == 0;
        BOOL expectUnsupported = argc == 3 && strcmp(argv[1], "--expect-unsupported") == 0;
        BOOL hasExpectation = expectInvalid || expectUnsupported;
        if ((!hasExpectation && argc != 2) || (hasExpectation && argc != 3)) {
            fprintf(stderr, "usage: legacy-manifest-test [--expect-invalid|--expect-unsupported] manifest.json\n");
            return 64;
        }
        NSString *path = [NSString stringWithUTF8String:argv[hasExpectation ? 2 : 1]];
        NSData *data = [NSData dataWithContentsOfFile:path];
        NSError *error = nil;
        RLVManifestParser *parser = [[RLVManifestParser alloc] init];
        RLVAssetManifest *parsed = [parser manifestFromData:data error:&error];
        if (parsed == nil) {
            if (expectInvalid && error.code != RLVManifestParserErrorUnsupportedSchema) {
                printf("PASS legacy parser rejected invalid manifest\n");
                return 0;
            }
            if (expectUnsupported && error.code == RLVManifestParserErrorUnsupportedSchema) {
                printf("PASS legacy parser rejected unsupported manifest\n");
                return 0;
            }
            fprintf(stderr, "%s\n", [[error localizedDescription] UTF8String]);
            return (error.code == RLVManifestParserErrorUnsupportedSchema) ? 2 : 1;
        }
        if (hasExpectation) {
            fprintf(stderr, "FAIL legacy parser unexpectedly accepted manifest\n");
            return 1;
        }
        printf("PASS legacy parser: %s schema=%ld\n", [parsed.assetId UTF8String], (long)parsed.schemaVersion);
        return 0;
    }
}
