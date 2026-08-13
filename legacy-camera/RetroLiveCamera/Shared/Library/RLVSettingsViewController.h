#import <UIKit/UIKit.h>

extern NSString * const RLVLibraryPreservesThumbnailAspectRatioDefaultsKey;
extern NSString * const RLVLibraryAutomaticallyPlaysLivePhotosDefaultsKey;

BOOL RLVLibraryPreservesThumbnailAspectRatio(void);
BOOL RLVLibraryAutomaticallyPlaysLivePhotos(void);

@interface RLVSettingsViewController : UITableViewController
@end
