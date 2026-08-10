#import "RLVClassicCameraViewController.h"
#import "RLVLayout.h"
#import "RLVShutterButton.h"
#import <QuartzCore/QuartzCore.h>

@implementation RLVClassicCameraViewController

- (void)loadView
{
    UIView *root = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    root.backgroundColor = [UIColor blackColor];
    self.previewView = [[UIView alloc] initWithFrame:CGRectZero];
    self.previewView.backgroundColor = [UIColor blackColor];
    self.previewView.clipsToBounds = YES;
    [root addSubview:self.previewView];

    self.topChromeView = [[UIView alloc] initWithFrame:CGRectZero];
    self.topChromeView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.62];
    [root addSubview:self.topChromeView];
    self.bottomChromeView = [[UIView alloc] initWithFrame:CGRectZero];
    self.bottomChromeView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.88];
    [root addSubview:self.bottomChromeView];

    self.flashButton = [self flatButtonWithTitle:nil font:[UIFont systemFontOfSize:12.0]];
    [self.topChromeView addSubview:self.flashButton];
    self.livePhotoButton = [self flatButtonWithTitle:nil font:[UIFont systemFontOfSize:12.0]];
    [self.topChromeView addSubview:self.livePhotoButton];
    self.aspectRatioButton = [self flatButtonWithTitle:@"4:3" font:[UIFont boldSystemFontOfSize:12.0]];
    [self.topChromeView addSubview:self.aspectRatioButton];
    self.cameraSwitchButton = [self flatButtonWithTitle:nil font:[UIFont systemFontOfSize:25.0]];
    self.cameraSwitchButton.accessibilityLabel = NSLocalizedString(@"camera.switch", nil);
    [self.bottomChromeView addSubview:self.cameraSwitchButton];

    self.shutterButton = [[RLVClassicShutterButton alloc] initWithFrame:CGRectZero];
    [self.bottomChromeView addSubview:self.shutterButton];
    self.thumbnailButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.thumbnailButton.accessibilityLabel = NSLocalizedString(@"camera.last_photo", nil);
    self.thumbnailButton.clipsToBounds = YES;
    [self.bottomChromeView addSubview:self.thumbnailButton];

    RLVInstallCameraLayout(root, self.previewView, self.topChromeView, self.bottomChromeView,
        self.flashButton, self.livePhotoButton, self.aspectRatioButton, self.thumbnailButton,
        self.shutterButton, CGSizeMake(76.0, 76.0), self.cameraSwitchButton);

    self.rotatingControls = [NSArray arrayWithObjects:self.flashButton, self.livePhotoButton, self.aspectRatioButton,
        self.cameraSwitchButton, self.thumbnailButton, nil];
    self.view = root;
}

- (UIButton *)flatButtonWithTitle:(NSString *)title font:(UIFont *)font
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:0.55 alpha:1] forState:UIControlStateHighlighted];
    button.titleLabel.font = font;
    return button;
}

@end
