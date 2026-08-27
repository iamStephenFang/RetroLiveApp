#import <UIKit/UIKit.h>

/// User-defaults key controlling aspect-fit versus square-filled thumbnails.
extern NSString * const RLVLibraryPreservesThumbnailAspectRatioDefaultsKey;
/// User-defaults key controlling automatic playback of motion companions.
extern NSString * const RLVLibraryAutomaticallyPlaysLivePhotosDefaultsKey;

/// Returns the effective thumbnail-aspect preference, including its default value.
BOOL RLVLibraryPreservesThumbnailAspectRatio(void);
/// Returns the effective motion-autoplay preference, including its default value.
BOOL RLVLibraryAutomaticallyPlaysLivePhotos(void);

/// Grouped system-style controls for library presentation preferences.
@interface RLVSettingsViewController : UITableViewController
@end
