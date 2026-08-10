#import "RLVLibraryTabBarController.h"
#import "RLVLibraryViewController.h"
#import "RLVTransferViewController.h"

@implementation RLVLibraryTabBarController

- (id)init
{
    self = [super init];
    if (self) {
        RLVLibraryViewController *library = [[RLVLibraryViewController alloc] init];
        RLVTransferViewController *transfer = [[RLVTransferViewController alloc] init];
        library.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"library.title", nil)
            image:nil tag:0];
        transfer.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"transfer.title", nil)
            image:[UIImage imageNamed:@"InterfaceIcons/RLVTransfer"] tag:1];

        UINavigationController *libraryNavigation = [[UINavigationController alloc]
            initWithRootViewController:library];
        UINavigationController *transferNavigation = [[UINavigationController alloc]
            initWithRootViewController:transfer];
        libraryNavigation.navigationBar.barStyle = UIBarStyleBlack;
        libraryNavigation.toolbar.barStyle = UIBarStyleBlack;
        transferNavigation.navigationBar.barStyle = UIBarStyleBlack;

        library.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close:)];
        transfer.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close:)];
        self.viewControllers = @[libraryNavigation, transferNavigation];
    }
    return self;
}

- (void)close:(id)sender
{
    (void)sender;
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
