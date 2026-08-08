#import "RLVDeviceCapabilities.h"
#import <UIKit/UIKit.h>
#import <sys/sysctl.h>

@interface RLVDeviceCapabilities ()
@property (nonatomic, copy, readwrite) NSString *systemVersion;
@property (nonatomic, copy, readwrite) NSString *modelIdentifier;
@property (nonatomic, copy, readwrite) NSString *architecture;
@property (nonatomic, assign, readwrite) BOOL supportsRearCamera;
@property (nonatomic, assign, readwrite) BOOL supportsFrontCamera;
@property (nonatomic, assign, readwrite) BOOL supportsFlash;
@property (nonatomic, assign, readwrite) BOOL supportsVideoCapture;
@property (nonatomic, assign, readwrite) BOOL supportsAudioCapture;
@property (nonatomic, copy, readwrite) NSArray *supportedPhotoResolutions;
@end

@implementation RLVDeviceCapabilities

+ (RLVDeviceCapabilities *)currentCapabilities
{
    RLVDeviceCapabilities *capabilities = [[RLVDeviceCapabilities alloc] init];
    capabilities.systemVersion = [[UIDevice currentDevice] systemVersion];
    capabilities.modelIdentifier = [self valueForSysctlName:"hw.machine"];
#if defined(__arm64__)
    capabilities.architecture = @"arm64";
#elif defined(__arm__)
    capabilities.architecture = @"armv7";
#elif defined(__x86_64__)
    capabilities.architecture = @"x86_64";
#else
    capabilities.architecture = @"unknown";
#endif

    AVCaptureDevice *rear = [capabilities cameraWithPosition:AVCaptureDevicePositionBack];
    AVCaptureDevice *front = [capabilities cameraWithPosition:AVCaptureDevicePositionFront];
    capabilities.supportsRearCamera = rear != nil;
    capabilities.supportsFrontCamera = front != nil;
    capabilities.supportsFlash = [rear hasFlash];
    capabilities.supportsVideoCapture = rear != nil || front != nil;
    capabilities.supportsAudioCapture = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio] != nil;

    // iOS 6 does not expose AVCaptureDeviceFormat. The exact still dimensions
    // are therefore measured from each captured JPEG and recorded in its asset.
    capabilities.supportedPhotoResolutions = [NSArray array];
    return capabilities;
}

+ (NSString *)valueForSysctlName:(const char *)name
{
    size_t size = 0;
    if (sysctlbyname(name, NULL, &size, NULL, 0) != 0 || size == 0) {
        return @"unknown";
    }
    void *buffer = malloc(size);
    if (buffer == NULL || sysctlbyname(name, buffer, &size, NULL, 0) != 0) {
        free(buffer);
        return @"unknown";
    }
    NSString *value = [NSString stringWithUTF8String:(const char *)buffer];
    free(buffer);
    return value ?: @"unknown";
}

- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position
{
    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if ([device position] == position) {
            return device;
        }
    }
    return nil;
}

@synthesize systemVersion = _systemVersion;
@synthesize modelIdentifier = _modelIdentifier;
@synthesize architecture = _architecture;
@synthesize supportsRearCamera = _supportsRearCamera;
@synthesize supportsFrontCamera = _supportsFrontCamera;
@synthesize supportsFlash = _supportsFlash;
@synthesize supportsVideoCapture = _supportsVideoCapture;
@synthesize supportsAudioCapture = _supportsAudioCapture;
@synthesize supportedPhotoResolutions = _supportedPhotoResolutions;

@end
