#import <Foundation/Foundation.h>
#include <string.h>
#import "RLVAssetManifest.h"
#import "RLVManifestParser.h"

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        BOOL expectInvalid = argc == 3 && strcmp(argv[1], "--expect-invalid") == 0;
        if ((!expectInvalid && argc != 2) || (expectInvalid && argc != 3)) {
            fprintf(stderr, "usage: legacy-manifest-test [--expect-invalid] manifest.json\n");
            return 64;
        }
        NSString *path = [NSString stringWithUTF8String:argv[expectInvalid ? 2 : 1]];
        NSData *data = [NSData dataWithContentsOfFile:path];
        NSError *error = nil;
        RLVManifestParser *parser = [[RLVManifestParser alloc] init];
        RLVAssetManifest *parsed = [parser manifestFromData:data error:&error];
        if (parsed == nil) {
            if (expectInvalid && error.code != RLVManifestParserErrorUnsupportedSchema) {
                printf("PASS legacy parser rejected invalid manifest\n");
                return 0;
            }
            fprintf(stderr, "%s\n", [[error localizedDescription] UTF8String]);
            return (error.code == RLVManifestParserErrorUnsupportedSchema) ? 2 : 1;
        }
        if (expectInvalid) {
            fprintf(stderr, "FAIL legacy parser unexpectedly accepted invalid manifest\n");
            return 1;
        }
        printf("PASS legacy parser: %s schema=%ld\n", [parsed.assetId UTF8String], (long)parsed.schemaVersion);
        return 0;
    }
}
