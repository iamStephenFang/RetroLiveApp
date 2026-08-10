#import "RLVAsset.h"
#import <UIKit/UIKit.h>

@interface RLVAssetDetailViewController : UIViewController
- (id)initWithAsset:(RLVAsset *)asset;
- (id)initWithAssets:(NSArray *)assets selectedIndex:(NSUInteger)selectedIndex;
- (void)selectAssetFromAssets:(NSArray *)assets atIndex:(NSUInteger)index;
@end
