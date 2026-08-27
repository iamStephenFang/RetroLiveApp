#import <UIKit/UIKit.h>

@class RLVAssetDetailViewController;

@protocol RLVAssetDetailViewControllerDelegate <NSObject>
/// Requests dismissal of the detail browser without mutating its assets.
- (void)assetDetailViewControllerDidRequestClose:(RLVAssetDetailViewController *)controller;
@end

/// Paged full-screen browser over a stable asset snapshot.
@interface RLVAssetDetailViewController : UIViewController
@property (nonatomic, weak) id<RLVAssetDetailViewControllerDelegate> delegate;
/// Creates a browser positioned at selectedIndex, which must be within assets.
- (id)initWithAssets:(NSArray *)assets selectedIndex:(NSUInteger)selectedIndex;
@end
