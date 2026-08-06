#import "RLVAssetManifest.h"

@implementation RLVMediaResource
@synthesize filename = _filename, mimeType = _mimeType, byteLength = _byteLength, sha256 = _sha256;
@end

@implementation RLVImageResource
@synthesize width = _width, height = _height;
@end

@implementation RLVMotionResource
@synthesize durationSeconds = _durationSeconds, width = _width, height = _height, frameRate = _frameRate, hasAudio = _hasAudio;
@end

@implementation RLVCaptureMetadata
@synthesize cameraPosition = _cameraPosition, orientation = _orientation, mirrored = _mirrored, flashMode = _flashMode;
@synthesize stillImageTimeSeconds = _stillImageTimeSeconds, stillImageTimeAccuracy = _stillImageTimeAccuracy;
@synthesize preRollSeconds = _preRollSeconds, postRollSeconds = _postRollSeconds;
@end

@implementation RLVDeviceMetadata
@synthesize modelIdentifier = _modelIdentifier, systemVersion = _systemVersion, appVersion = _appVersion;
@end

@implementation RLVAssetManifest
@synthesize schemaVersion = _schemaVersion, assetId = _assetId, createdAt = _createdAt;
@synthesize createdAtUnixMilliseconds = _createdAtUnixMilliseconds, capture = _capture, photo = _photo;
@synthesize motion = _motion, thumbnail = _thumbnail, device = _device;
@end
