#import <UIKit/UIKit.h>

typedef void (^RLVLibrarySelectionHandler)(NSArray *assets, NSUInteger selectedIndex);

@interface RLVLibraryViewController : UICollectionViewController
- (id)initWithSelectionHandler:(RLVLibrarySelectionHandler)selectionHandler;
@end
