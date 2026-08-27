#import <UIKit/UIKit.h>

/// Container that coordinates the asset library and its settings tab.
@interface RLVLibraryTabBarController : UITabBarController
/// Creates the library from a stable snapshot and optionally opens selectedIndex.
- (id)initWithAssets:(NSArray *)assets selectedIndex:(NSUInteger)selectedIndex;
@end
