#import <Foundation/Foundation.h>
#import "RLVAssetStore.h"
#import "RLVHTTPResponse.h"
#import "RLVManifest.h"
#import "RLVTransferRouter.h"

static void RLVAssert(BOOL condition, NSString *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL %s\n", [message UTF8String]);
        exit(1);
    }
}

static NSDictionary *RLVJSONObject(RLVHTTPResponse *response)
{
    return response.body ? [NSJSONSerialization JSONObjectWithData:response.body options:0 error:NULL] : nil;
}

static void RLVCreateAsset(RLVAssetStore *store, NSString *assetId, NSString *createdAt, long long milliseconds, NSData *photo)
{
    NSURL *directory = [store.assetsURL URLByAppendingPathComponent:assetId isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:nil error:NULL];
    [photo writeToURL:[directory URLByAppendingPathComponent:@"photo.jpg"] atomically:YES];
    NSDictionary *manifest = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInteger:1], @"schemaVersion", assetId, @"assetId", createdAt, @"createdAt",
        [NSNumber numberWithLongLong:milliseconds], @"createdAtUnixMilliseconds",
        [NSDictionary dictionaryWithObjectsAndKeys:@"photo.jpg", @"filename", @"image/jpeg", @"mimeType",
            [NSNumber numberWithInteger:2], @"width", [NSNumber numberWithInteger:2], @"height",
            [NSNumber numberWithUnsignedLongLong:[photo length]], @"byteLength",
            [RLVManifest SHA256ForData:photo], @"sha256", nil], @"photo",
        [NSNull null], @"motion",
        [NSDictionary dictionaryWithObjectsAndKeys:@"back", @"cameraPosition",
            [NSNumber numberWithInteger:1], @"orientation", [NSNumber numberWithBool:NO], @"mirrored",
            @"off", @"flashMode", [NSNumber numberWithDouble:0.0], @"stillImageTimeSeconds",
            @"estimated", @"stillImageTimeAccuracy", [NSNumber numberWithDouble:0.0], @"preRollSeconds",
            [NSNumber numberWithDouble:0.0], @"postRollSeconds", nil], @"capture",
        [NSDictionary dictionaryWithObjectsAndKeys:@"TestDevice1,1", @"modelIdentifier",
            @"6.1.6", @"systemVersion", @"1.0", @"appVersion", nil], @"device", nil];
    NSData *manifestData = [NSJSONSerialization dataWithJSONObject:manifest options:0 error:NULL];
    [manifestData writeToURL:[directory URLByAppendingPathComponent:@"manifest.json"] atomically:YES];
}

int main(void)
{
    @autoreleasepool {
        NSString *basePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        NSURL *documentsURL = [NSURL fileURLWithPath:basePath isDirectory:YES];
        RLVAssetStore *store = [[RLVAssetStore alloc] initWithDocumentsURL:documentsURL];
        NSString *newerId = @"AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA";
        NSString *olderId = @"BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB";
        NSData *photo = [@"0123456789" dataUsingEncoding:NSUTF8StringEncoding];
        RLVCreateAsset(store, olderId, @"2026-08-08T10:00:00.000Z", 1786183200000, photo);
        RLVCreateAsset(store, newerId, @"2026-08-08T11:00:00.000Z", 1786186800000, photo);

        NSDictionary *capabilities = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithBool:YES], @"rangeDownload", [NSNumber numberWithBool:NO], @"batchExport",
            [NSNumber numberWithBool:NO], @"delete", nil];
        NSDictionary *device = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInteger:1], @"protocolVersion",
            @"CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC", @"deviceId", @"Test Camera", @"deviceName",
            @"TestDevice1,1", @"modelIdentifier", @"6.1.6", @"systemVersion", @"1.0", @"appVersion",
            capabilities, @"capabilities", nil];
        RLVTransferRouter *router = [[RLVTransferRouter alloc] initWithAssetStore:store deviceInfo:device pairingCode:@"123456"];

        RLVHTTPResponse *response = [router responseForMethod:@"GET" path:@"/api/v1/health" headers:[NSDictionary dictionary] body:nil];
        RLVAssert(response.statusCode == 200 && [[[RLVJSONObject(response) objectForKey:@"status"] description] isEqualToString:@"ok"], @"health");
        response = [router responseForMethod:@"GET" path:@"/api/v1/device" headers:[NSDictionary dictionary] body:nil];
        RLVAssert(response.statusCode == 401, @"authorization required");

        NSData *badPairing = [NSJSONSerialization dataWithJSONObject:[NSDictionary dictionaryWithObjectsAndKeys:
            @"000000", @"pairingCode", @"Importer", @"clientName", nil] options:0 error:NULL];
        response = [router responseForMethod:@"POST" path:@"/api/v1/session" headers:[NSDictionary dictionary] body:badPairing];
        RLVAssert(response.statusCode == 401, @"bad pairing rejected");
        NSData *pairing = [NSJSONSerialization dataWithJSONObject:[NSDictionary dictionaryWithObjectsAndKeys:
            @"123456", @"pairingCode", @"Importer", @"clientName", nil] options:0 error:NULL];
        response = [router responseForMethod:@"POST" path:@"/api/v1/session" headers:[NSDictionary dictionary] body:pairing];
        NSString *token = [RLVJSONObject(response) objectForKey:@"token"];
        RLVAssert(response.statusCode == 200 && [token length] >= 32 &&
            [router.pairedClientName isEqualToString:@"Importer"], @"pairing token and client identity");
        NSDictionary *headers = [NSDictionary dictionaryWithObject:[@"Bearer " stringByAppendingString:token] forKey:@"authorization"];

        response = [router responseForMethod:@"GET" path:@"/api/v1/device" headers:headers body:nil];
        RLVAssert(response.statusCode == 200 && [[RLVJSONObject(response) objectForKey:@"assetCount"] integerValue] == 2, @"device info");
        response = [router responseForMethod:@"GET" path:@"/api/v1/assets?limit=1" headers:headers body:nil];
        NSDictionary *page = RLVJSONObject(response);
        NSArray *items = [page objectForKey:@"items"];
        RLVAssert(response.statusCode == 200 && [items count] == 1 &&
            [[[[items objectAtIndex:0] objectForKey:@"assetId"] description] isEqualToString:newerId] &&
            [[items objectAtIndex:0] objectForKey:@"thumbnailURL"] == nil &&
            [[page objectForKey:@"nextCursor"] isEqualToString:newerId], @"first asset page");

        NSString *secondPage = [NSString stringWithFormat:@"/api/v1/assets?limit=1&cursor=%@", newerId];
        response = [router responseForMethod:@"GET" path:secondPage headers:headers body:nil];
        page = RLVJSONObject(response);
        RLVAssert([[[[[page objectForKey:@"items"] objectAtIndex:0] objectForKey:@"assetId"] description] isEqualToString:olderId] &&
            [page objectForKey:@"nextCursor"] == [NSNull null], @"cursor pagination");

        NSString *base = [NSString stringWithFormat:@"/api/v1/assets/%@", newerId];
        response = [router responseForMethod:@"GET" path:[base stringByAppendingString:@"/manifest"] headers:headers body:nil];
        RLVAssert(response.statusCode == 200 && response.fileLength > 0, @"manifest download");
        response = [router responseForMethod:@"GET" path:[base stringByAppendingString:@"/photo"] headers:headers body:nil];
        RLVAssert(response.statusCode == 200 && response.fileOffset == 0 && response.fileLength == 10, @"complete photo");
        NSMutableDictionary *rangeHeaders = [NSMutableDictionary dictionaryWithDictionary:headers];
        [rangeHeaders setObject:@"bytes=2-5" forKey:@"range"];
        response = [router responseForMethod:@"GET" path:[base stringByAppendingString:@"/photo"] headers:rangeHeaders body:nil];
        RLVAssert(response.statusCode == 206 && response.fileOffset == 2 && response.fileLength == 4, @"bounded byte range");
        [rangeHeaders setObject:@"bytes=-3" forKey:@"range"];
        response = [router responseForMethod:@"GET" path:[base stringByAppendingString:@"/photo"] headers:rangeHeaders body:nil];
        RLVAssert(response.statusCode == 206 && response.fileOffset == 7 && response.fileLength == 3, @"suffix range");
        response = [router responseForMethod:@"GET" path:[base stringByAppendingString:@"/thumbnail"] headers:headers body:nil];
        RLVAssert(response.statusCode == 404, @"missing optional thumbnail");
        [rangeHeaders setObject:@"bytes=99-" forKey:@"range"];
        response = [router responseForMethod:@"GET" path:[base stringByAppendingString:@"/photo"] headers:rangeHeaders body:nil];
        RLVAssert(response.statusCode == 416, @"unsatisfiable range");
        response = [router responseForMethod:@"GET" path:[base stringByAppendingString:@"/motion"] headers:headers body:nil];
        RLVAssert(response.statusCode == 404, @"missing optional motion");
        response = [router responseForMethod:@"GET" path:@"/api/v1/assets/not-a-uuid/photo" headers:headers body:nil];
        RLVAssert(response.statusCode == 404, @"malformed asset id");
        response = [router responseForMethod:@"GET" path:@"/api/v1/assets?limit=1garbage" headers:headers body:nil];
        RLVAssert(response.statusCode == 400, @"malformed pagination limit");
        [rangeHeaders setObject:@"bytes=184467440737095516160-" forKey:@"range"];
        response = [router responseForMethod:@"GET" path:[base stringByAppendingString:@"/photo"] headers:rangeHeaders body:nil];
        RLVAssert(response.statusCode == 416, @"overflowing range rejected");

        RLVTransferRouter *limitedRouter = [[RLVTransferRouter alloc] initWithAssetStore:store deviceInfo:device pairingCode:@"123456"];
        for (NSUInteger attempt = 0; attempt < 5; attempt++) {
            [limitedRouter responseForMethod:@"POST" path:@"/api/v1/session" headers:[NSDictionary dictionary] body:badPairing];
        }
        response = [limitedRouter responseForMethod:@"POST" path:@"/api/v1/session" headers:[NSDictionary dictionary] body:pairing];
        RLVAssert(response.statusCode == 429, @"pairing attempt lockout");

        [[NSFileManager defaultManager] removeItemAtURL:documentsURL error:NULL];
        printf("PASS transfer router: pairing, lockout, auth, pagination, optional resources, ranges, errors\n");
    }
    return 0;
}
