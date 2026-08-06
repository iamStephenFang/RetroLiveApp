#import <Foundation/Foundation.h>
#import "RLVAssetManifest.h"
#import "RLVManifestParser.h"

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc != 2) {
            fprintf(stderr, "usage: legacy-manifest-test manifest.json\n");
            return 64;
        }
        NSString *path = [NSString stringWithUTF8String:argv[1]];
        NSData *data = [NSData dataWithContentsOfFile:path];
        NSError *error = nil;
        RLVManifestParser *parser = [[RLVManifestParser alloc] init];
        RLVAssetManifest *parsed = [parser manifestFromData:data error:&error];
        if (parsed == nil) {
            fprintf(stderr, "%s\n", [[error localizedDescription] UTF8String]);
            return (error.code == RLVManifestParserErrorUnsupportedSchema) ? 2 : 1;
        }
        printf("PASS legacy parser: %s schema=%ld\n", [parsed.assetId UTF8String], (long)parsed.schemaVersion);
        return 0;
    }
}
