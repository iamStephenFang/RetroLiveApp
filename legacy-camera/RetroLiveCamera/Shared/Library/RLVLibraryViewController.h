#import <UIKit/UIKit.h>

@class RLVLibraryViewController;

@protocol RLVLibraryViewControllerDelegate <NSObject>
/// Opens the supplied stable asset snapshot at selectedIndex.
- (void)libraryViewController:(RLVLibraryViewController *)controller
              didSelectAssets:(NSArray *)assets
                selectedIndex:(NSUInteger)selectedIndex;
/// Reports entry to or exit from multi-selection so containing chrome can update.
- (void)libraryViewController:(RLVLibraryViewController *)controller
    didChangeSelectingAssets:(BOOL)selectingAssets;
@end

/// Adaptive thumbnail collection for committed camera assets.
@interface RLVLibraryViewController : UICollectionViewController
@property (nonatomic, weak) id<RLVLibraryViewControllerDelegate> delegate;
@end
