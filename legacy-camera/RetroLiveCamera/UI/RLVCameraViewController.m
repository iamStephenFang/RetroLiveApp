#import "RLVCameraViewController.h"

@implementation RLVCameraViewController

- (void)loadView
{
    UIView *rootView = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    rootView.backgroundColor = [UIColor blackColor];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20.0, 80.0, 280.0, 80.0)];
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    titleLabel.backgroundColor = [UIColor clearColor];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 2;
    titleLabel.text = [NSString stringWithFormat:@"RetroLive Camera\n%@", NSLocalizedString(@"camera.ready", nil)];
    [rootView addSubview:titleLabel];

    self.view = rootView;
}

@end
