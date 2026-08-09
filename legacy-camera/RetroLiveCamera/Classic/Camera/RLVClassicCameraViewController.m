#import "RLVClassicCameraViewController.h"
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

    self.flashButton = [self flatButtonWithTitle:NSLocalizedString(@"camera.flash.auto", nil) font:[UIFont systemFontOfSize:12.0]];
    [self.topChromeView addSubview:self.flashButton];
    self.cameraSwitchButton = [self flatButtonWithTitle:@"↻" font:[UIFont systemFontOfSize:25.0]];
    self.cameraSwitchButton.accessibilityLabel = NSLocalizedString(@"camera.switch", nil);
    [self.topChromeView addSubview:self.cameraSwitchButton];

    UILabel *mode = [[UILabel alloc] initWithFrame:CGRectZero];
    mode.tag = 8001;
    mode.text = NSLocalizedString(@"camera.mode.photo", nil);
    mode.textColor = [UIColor colorWithRed:1 green:0.78 blue:0 alpha:1];
    mode.font = [UIFont systemFontOfSize:12.0];
    mode.textAlignment = NSTextAlignmentCenter;
    mode.backgroundColor = [UIColor clearColor];
    [self.bottomChromeView addSubview:mode];

    self.shutterButton = [[RLVClassicShutterButton alloc] initWithFrame:CGRectZero];
    [self.bottomChromeView addSubview:self.shutterButton];
    self.thumbnailButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.thumbnailButton.accessibilityLabel = NSLocalizedString(@"camera.last_photo", nil);
    self.thumbnailButton.clipsToBounds = YES;
    [self.bottomChromeView addSubview:self.thumbnailButton];
    self.rotatingControls = [NSArray arrayWithObjects:self.flashButton, self.cameraSwitchButton, self.thumbnailButton, nil];
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

- (void)viewDidLayoutSubviews
{
    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat height = CGRectGetHeight(self.view.bounds);
    CGFloat topHeight = 44.0;
    CGFloat bottomHeight = height >= 667.0 ? 142.0 : 128.0;
    self.previewView.frame = self.view.bounds;
    self.topChromeView.frame = CGRectMake(0, 0, width, topHeight);
    self.bottomChromeView.frame = CGRectMake(0, height - bottomHeight, width, bottomHeight);
    self.flashButton.frame = CGRectMake(4, 0, 80, topHeight);
    self.cameraSwitchButton.frame = CGRectMake(width - 58, 0, 54, topHeight);
    UILabel *mode = (UILabel *)[self.bottomChromeView viewWithTag:8001];
    mode.frame = CGRectMake(0, 5, width, 20);
    self.shutterButton.frame = CGRectMake((width - 78) / 2.0, bottomHeight - 88, 78, 78);
    self.thumbnailButton.frame = CGRectMake(16, bottomHeight - 69, 48, 48);
    [super viewDidLayoutSubviews];
}

@end
