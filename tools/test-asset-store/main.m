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

        RLVCaptureEvent *event = [[RLVCaptureEvent alloc] init];
        event.assetId = [[[NSUUID UUID] UUIDString] uppercaseString];
        event.shutterTimestamp = [NSDate dateWithTimeIntervalSince1970:1786190400.125];
        event.orientation = RLVCaptureOrientationPortrait;
        event.cameraPosition = AVCaptureDevicePositionBack;
        event.flashMode = @"off";

        __block RLVAsset *committedAsset = nil;
        __block NSError *commitError = nil;
        __block BOOL completed = NO;
        [store createAssetWithPhotoData:RLVCreateTestJPEG() event:event capabilities:nil completion:^(RLVAsset *asset, NSError *error) {
            committedAsset = asset;
            commitError = error;
            completed = YES;
        }];
        while (!completed) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        if (!committedAsset || commitError || ![committedAsset isComplete] || committedAsset.width != 2 || committedAsset.height != 2) {
            fprintf(stderr, "FAIL asset commit: %s\n", [[commitError description] UTF8String]);
            return 1;
        }
        if (![store validateAssetAtURL:[[committedAsset photoURL] URLByDeletingLastPathComponent] error:&commitError]) {
            fprintf(stderr, "FAIL committed validation: %s\n", [[commitError description] UTF8String]);
            return 1;
        }

        NSURL *partial = [[store temporaryURL] URLByAppendingPathComponent:@"PARTIAL" isDirectory:YES];
        [[NSFileManager defaultManager] createDirectoryAtURL:partial withIntermediateDirectories:NO attributes:nil error:NULL];
        [@"partial" writeToURL:[partial URLByAppendingPathComponent:@"photo.jpg"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        __unused RLVAssetStore *restartedStore = [[RLVAssetStore alloc] initWithDocumentsURL:documentsURL];
        if ([[NSFileManager defaultManager] fileExistsAtPath:[partial path]]) {
            fprintf(stderr, "FAIL recovery left partial staging directory\n");
            return 1;
        }

        NSArray *assets = [store loadAssets:&commitError];
        if ([assets count] != 1 || ![[[assets objectAtIndex:0] assetId] isEqualToString:event.assetId]) {
            fprintf(stderr, "FAIL asset reload: %s\n", [[commitError description] UTF8String]);
            return 1;
        }
        [[NSFileManager defaultManager] removeItemAtURL:documentsURL error:NULL];
        printf("PASS asset transaction: commit, validation, reload, recovery\n");
    }
    return 0;
}
