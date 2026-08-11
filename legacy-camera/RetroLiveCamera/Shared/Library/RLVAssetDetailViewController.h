#import <UIKit/UIKit.h>

@class RLVAssetDetailViewController;

@protocol RLVAssetDetailViewControllerDelegate <NSObject>
- (void)assetDetailViewControllerDidRequestClose:(RLVAssetDetailViewController *)controller;
@end

@interface RLVAssetDetailViewController : UIViewController
@property (nonatomic, weak) id<RLVAssetDetailViewControllerDelegate> delegate;
- (id)initWithAssets:(NSArray *)assets selectedIndex:(NSUInteger)selectedIndex;
@end
