#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import "RLVAssetStore.h"

static NSData *RLVCreateTestJPEG(void)
{
    unsigned char pixels[16] = {
        255, 0, 0, 255, 0, 255, 0, 255,
        0, 0, 255, 255, 255, 255, 255, 255
    };
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, 2, 2, 8, 8, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGImageRef image = CGBitmapContextCreateImage(context);
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,
        CFSTR("public.jpeg"), 1, NULL);
    CGImageDestinationAddImage(destination, image, NULL);
    BOOL finalized = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    CGImageRelease(image);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    return finalized ? data : nil;
}

int main(void)
{
    @autoreleasepool {
        NSString *basePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        NSURL *documentsURL = [NSURL fileURLWithPath:basePath isDirectory:YES];
        [[NSFileManager defaultManager] createDirectoryAtURL:documentsURL withIntermediateDirectories:YES attributes:nil error:NULL];
        RLVAssetStore *store = [[RLVAssetStore alloc] initWithDocumentsURL:documentsURL];

        __block NSArray *preloadedAssets = nil;
        __block BOOL preloadCompleted = NO;
        __block NSError *preloadError = nil;
        [store loadAssetsWithCompletion:^(NSArray *assets, NSError *error) {
            preloadedAssets = assets;
            preloadError = error;
            preloadCompleted = YES;
        }];
        while (!preloadCompleted) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        if (preloadError || [preloadedAssets count] != 0) {
            fprintf(stderr, "FAIL initial asynchronous catalog preload: %s\n", [[preloadError description] UTF8String]);
            return 1;
        }

        RLVCaptureEvent *event = [[RLVCaptureEvent alloc] init];
        event.assetId = [[[NSUUID UUID] UUIDString] uppercaseString];
        event.shutterTimestamp = [NSDate dateWithTimeIntervalSince1970:1786190400.125];
        event.orientation = RLVCaptureOrientationPortrait;
        event.cameraPosition = AVCaptureDevicePositionBack;
        event.flashMode = @"off";
        event.stillImageTimeSeconds = 1.5;
        event.preRollSeconds = 1.5;
        event.postRollSeconds = 1.5;
        event.motionDurationSeconds = 3.0;
        event.motionWidth = 1280;
        event.motionHeight = 720;
        event.motionFrameRate = 30.0;
        event.motionHasAudio = YES;
        NSURL *motionURL = [documentsURL URLByAppendingPathComponent:@"source-motion.mov"];
        [[@"synthetic-motion-payload" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:motionURL atomically:YES];

        __block RLVAsset *committedAsset = nil;
        __block NSError *commitError = nil;
        __block BOOL completed = NO;
        [store createAssetWithPhotoData:RLVCreateTestJPEG() motionURL:motionURL event:event capabilities:nil completion:^(RLVAsset *asset, NSError *error) {
            committedAsset = asset;
            commitError = error;
            completed = YES;
        }];
        while (!completed) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        if (!committedAsset || commitError || ![committedAsset isComplete] || ![committedAsset hasMotion] || committedAsset.width != 2 || committedAsset.height != 2) {
            fprintf(stderr, "FAIL asset commit: %s\n", [[commitError description] UTF8String]);
            return 1;
        }
        if (![store validateAssetAtURL:[[committedAsset photoURL] URLByDeletingLastPathComponent] error:&commitError]) {
            fprintf(stderr, "FAIL committed validation: %s\n", [[commitError description] UTF8String]);
            return 1;
        }
        NSData *manifestData = [NSData dataWithContentsOfURL:committedAsset.manifestURL];
        NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&commitError];
        NSDictionary *motion = [manifest objectForKey:@"motion"];
        NSDictionary *capture = [manifest objectForKey:@"capture"];
        if (![[motion objectForKey:@"filename"] isEqualToString:@"motion.mov"] ||
            [[motion objectForKey:@"durationSeconds"] doubleValue] != 3.0 ||
            [[motion objectForKey:@"frameRate"] doubleValue] != 30.0 ||
            [[capture objectForKey:@"stillImageTimeSeconds"] doubleValue] != 1.5) {
            fprintf(stderr, "FAIL motion manifest metadata\n");
            return 1;
        }

        RLVCaptureEvent *photoEvent = [[RLVCaptureEvent alloc] init];
        photoEvent.assetId = [[[NSUUID UUID] UUIDString] uppercaseString];
        photoEvent.shutterTimestamp = [NSDate dateWithTimeIntervalSince1970:1786190401.125];
        photoEvent.orientation = RLVCaptureOrientationLandscapeLeft;
        photoEvent.cameraPosition = AVCaptureDevicePositionFront;
        photoEvent.mirrored = YES;
        photoEvent.flashMode = @"off";
        completed = NO;
        committedAsset = nil;
        commitError = nil;
        [store createAssetWithPhotoData:RLVCreateTestJPEG() motionURL:nil event:photoEvent capabilities:nil completion:^(RLVAsset *asset, NSError *error) {
            committedAsset = asset;
            commitError = error;
            completed = YES;
        }];
        while (!completed) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        if (!committedAsset || commitError || [committedAsset hasMotion]) {
            fprintf(stderr, "FAIL photo-only commit: %s\n", [[commitError description] UTF8String]);
            return 1;
        }
        NSData *photoManifestData = [NSData dataWithContentsOfURL:committedAsset.manifestURL];
        NSDictionary *photoManifest = [NSJSONSerialization JSONObjectWithData:photoManifestData options:0 error:&commitError];
        NSDictionary *photoCapture = [photoManifest objectForKey:@"capture"];
        if ([photoManifest objectForKey:@"motion"] != [NSNull null] ||
            [[photoCapture objectForKey:@"stillImageTimeSeconds"] doubleValue] != 0.0 ||
            [[photoCapture objectForKey:@"preRollSeconds"] doubleValue] != 0.0 ||
            [[photoCapture objectForKey:@"postRollSeconds"] doubleValue] != 0.0) {
            fprintf(stderr, "FAIL photo-only manifest semantics\n");
            return 1;
        }

        NSURL *partial = [[store temporaryURL] URLByAppendingPathComponent:@"PARTIAL" isDirectory:YES];
        [[NSFileManager defaultManager] createDirectoryAtURL:partial withIntermediateDirectories:NO attributes:nil error:NULL];
        [@"partial" writeToURL:[partial URLByAppendingPathComponent:@"photo.jpg"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        RLVAssetStore *restartedStore = [[RLVAssetStore alloc] initWithDocumentsURL:documentsURL];
        if ([[NSFileManager defaultManager] fileExistsAtPath:[partial path]]) {
            fprintf(stderr, "FAIL recovery left partial staging directory\n");
            return 1;
        }

        NSString *corruptId = [[[NSUUID UUID] UUIDString] uppercaseString];
        NSURL *corruptURL = [[store assetsURL] URLByAppendingPathComponent:corruptId isDirectory:YES];
        [[NSFileManager defaultManager] createDirectoryAtURL:corruptURL withIntermediateDirectories:NO attributes:nil error:NULL];
        [RLVCreateTestJPEG() writeToURL:[corruptURL URLByAppendingPathComponent:@"photo.jpg"] atomically:YES];
        NSMutableDictionary *corruptManifest = [photoManifest mutableCopy];
        NSMutableDictionary *corruptPhoto = [[corruptManifest objectForKey:@"photo"] mutableCopy];
        [corruptManifest setObject:corruptId forKey:@"assetId"];
        [corruptPhoto setObject:@"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" forKey:@"sha256"];
        [corruptManifest setObject:corruptPhoto forKey:@"photo"];
        NSData *corruptData = [NSJSONSerialization dataWithJSONObject:corruptManifest options:0 error:NULL];
        [corruptData writeToURL:[corruptURL URLByAppendingPathComponent:@"manifest.json"] atomically:YES];

        NSString *missingId = [[[NSUUID UUID] UUIDString] uppercaseString];
        NSURL *missingURL = [[store assetsURL] URLByAppendingPathComponent:missingId isDirectory:YES];
        [[NSFileManager defaultManager] createDirectoryAtURL:missingURL withIntermediateDirectories:NO attributes:nil error:NULL];
        [photoManifestData writeToURL:[missingURL URLByAppendingPathComponent:@"manifest.json"] atomically:YES];

        NSArray *cachedAssets = [store loadAssets:&commitError];
        if ([cachedAssets count] != 2) {
            fprintf(stderr, "FAIL verified catalog cache update: %s\n", [[commitError description] UTF8String]);
            return 1;
        }
        NSArray *assets = [restartedStore loadAssets:&commitError];
        if ([assets count] != 2) {
            fprintf(stderr, "FAIL asset reload: %s\n", [[commitError description] UTF8String]);
            return 1;
        }
        RLVAsset *outsideAsset = [[RLVAsset alloc] init];
        outsideAsset.assetId = photoEvent.assetId;
        outsideAsset.photoURL = [documentsURL URLByAppendingPathComponent:@"outside/photo.jpg"];
        commitError = nil;
        if ([store deleteAsset:outsideAsset error:&commitError] || commitError == nil) {
            fprintf(stderr, "FAIL delete escaped managed asset root\n");
            return 1;
        }
        [[NSFileManager defaultManager] removeItemAtURL:documentsURL error:NULL];
        printf("PASS asset transactions: motion, photo-only, validation, filtering, recovery, deletion boundary\n");
    }
    return 0;
}
