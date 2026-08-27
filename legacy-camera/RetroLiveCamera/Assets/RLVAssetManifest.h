#import <Foundation/Foundation.h>

/// Length and digest metadata shared by all Manifest V1 media resources.
@interface RLVMediaResource : NSObject
@property (nonatomic, copy) NSString *filename;
@property (nonatomic, copy) NSString *mimeType;
@property (nonatomic, assign) unsigned long long byteLength;
@property (nonatomic, copy) NSString *sha256;
@end

/// Manifest V1 metadata for a still image.
@interface RLVImageResource : RLVMediaResource
@property (nonatomic, assign) NSUInteger width;
@property (nonatomic, assign) NSUInteger height;
@end

/// Manifest V1 metadata for an optional motion companion.
@interface RLVMotionResource : RLVMediaResource
@property (nonatomic, assign) NSTimeInterval durationSeconds;
@property (nonatomic, assign) NSUInteger width;
@property (nonatomic, assign) NSUInteger height;
@property (nonatomic, assign) double frameRate;
@property (nonatomic, assign) BOOL hasAudio;
@end

/// Normalized shutter-time and orientation metadata from Manifest V1.
@interface RLVCaptureMetadata : NSObject
@property (nonatomic, copy) NSString *cameraPosition;
@property (nonatomic, assign) NSUInteger orientation;
@property (nonatomic, assign) BOOL mirrored;
@property (nonatomic, copy) NSString *flashMode;
@property (nonatomic, copy) NSString *aspectRatio;
@property (nonatomic, assign) NSTimeInterval stillImageTimeSeconds;
@property (nonatomic, copy) NSString *stillImageTimeAccuracy;
@property (nonatomic, assign) NSTimeInterval preRollSeconds;
@property (nonatomic, assign) NSTimeInterval postRollSeconds;
@end

/// Capturing device and app versions recorded in Manifest V1.
@interface RLVDeviceMetadata : NSObject
@property (nonatomic, copy) NSString *modelIdentifier;
@property (nonatomic, copy) NSString *systemVersion;
@property (nonatomic, copy) NSString *appVersion;
@end

/// Parsed, validated object representation of one Manifest V1 document.
@interface RLVAssetManifest : NSObject
@property (nonatomic, assign) NSInteger schemaVersion;
@property (nonatomic, copy) NSString *assetId;
@property (nonatomic, copy) NSString *createdAt;
@property (nonatomic, assign) long long createdAtUnixMilliseconds;
@property (nonatomic, strong) RLVCaptureMetadata *capture;
@property (nonatomic, strong) RLVImageResource *photo;
/// Optional motion companion; nil for a photo-only asset.
@property (nonatomic, strong) RLVMotionResource *motion;
/// Optional generated thumbnail.
@property (nonatomic, strong) RLVImageResource *thumbnail;
@property (nonatomic, strong) RLVDeviceMetadata *device;
@end
