#import "RLVCameraViewController.h"
#import "RLVLayout.h"

@implementation RLVCameraViewController

- (void)loadView
{
    UIView *rootView = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    rootView.backgroundColor = [UIColor blackColor];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.backgroundColor = [UIColor clearColor];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 2;
    titleLabel.text = [NSString stringWithFormat:@"RetroLive Camera\n%@", NSLocalizedString(@"camera.ready", nil)];
    [rootView addSubview:titleLabel];
    RLVPrepareViewsForAutoLayout(@[titleLabel]);
    RLVAddVisualConstraints(rootView, @{@"title": titleLabel},
        @[@"H:|-20-[title]-20-|", @"V:[title(80)]"]);
    RLVAlignViews(rootView, titleLabel, NSLayoutAttributeCenterY, rootView, NSLayoutAttributeCenterY);

    self.view = rootView;
}

@end
