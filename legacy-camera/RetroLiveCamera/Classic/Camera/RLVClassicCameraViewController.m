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

    RLVPrepareViewsForAutoLayout(@[self.previewView, self.topChromeView, self.bottomChromeView,
        self.flashButton, self.cameraSwitchButton, mode, self.shutterButton, self.thumbnailButton]);
    RLVAddVisualConstraints(root,
        @{@"preview": self.previewView, @"top": self.topChromeView, @"bottom": self.bottomChromeView},
        @[@"H:|[preview]|", @"V:|[preview]|", @"H:|[top]|", @"V:|[top(44)]",
          @"H:|[bottom]|", @"V:[bottom(128)]|"]);
    RLVAddVisualConstraints(self.topChromeView,
        @{@"flash": self.flashButton, @"switch": self.cameraSwitchButton},
        @[@"H:|-4-[flash(80)]", @"H:[switch(54)]-4-|", @"V:|[flash]|", @"V:|[switch]|"]);
    RLVAddVisualConstraints(self.bottomChromeView,
        @{@"mode": mode, @"shutter": self.shutterButton, @"thumbnail": self.thumbnailButton},
        @[@"H:|[mode]|", @"V:|-5-[mode(20)]", @"H:[shutter(78)]", @"V:[shutter(78)]-10-|",
          @"H:|-16-[thumbnail(48)]", @"V:[thumbnail(48)]-21-|"]);
    RLVAlignViews(self.bottomChromeView, self.shutterButton, NSLayoutAttributeCenterX,
        self.bottomChromeView, NSLayoutAttributeCenterX);

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

@end
