#import <UIKit/UIKit.h>

@class RLVLibraryViewController;

@protocol RLVLibraryViewControllerDelegate <NSObject>
- (void)libraryViewController:(RLVLibraryViewController *)controller
              didSelectAssets:(NSArray *)assets
                selectedIndex:(NSUInteger)selectedIndex;
- (void)libraryViewController:(RLVLibraryViewController *)controller
    didChangeSelectingAssets:(BOOL)selectingAssets;
@end

@interface RLVLibraryViewController : UICollectionViewController
@property (nonatomic, weak) id<RLVLibraryViewControllerDelegate> delegate;
@end
