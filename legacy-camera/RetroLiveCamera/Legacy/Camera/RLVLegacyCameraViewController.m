#import "RLVLegacyCameraViewController.h"
#import "RLVShutterButton.h"
#import <QuartzCore/QuartzCore.h>

@interface RLVLegacyChromeView : UIView
@property (nonatomic, assign) BOOL top;
@end

@implementation RLVLegacyChromeView
- (void)drawRect:(CGRect)rect
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    UIColor *start = self.top ? [UIColor colorWithRed:0.24 green:0.25 blue:0.26 alpha:1] : [UIColor colorWithRed:0.19 green:0.20 blue:0.21 alpha:1];
    UIColor *end = self.top ? [UIColor colorWithRed:0.08 green:0.09 blue:0.10 alpha:1] : [UIColor colorWithRed:0.06 green:0.065 blue:0.07 alpha:1];
    NSArray *colors = [NSArray arrayWithObjects:(id)start.CGColor, (id)end.CGColor, nil];
    CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, 0), CGPointMake(0, CGRectGetHeight(rect)), 0);
    CGContextSetStrokeColorWithColor(context, [UIColor colorWithWhite:self.top ? 0.0 : 0.38 alpha:1].CGColor);
    CGContextMoveToPoint(context, 0, self.top ? CGRectGetHeight(rect) - 0.5 : 0.5);
    CGContextAddLineToPoint(context, CGRectGetWidth(rect), self.top ? CGRectGetHeight(rect) - 0.5 : 0.5);
    CGContextStrokePath(context);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
}
@synthesize top = _top;
@end

@implementation RLVLegacyCameraViewController

- (void)loadView
{
    CGRect bounds = [[UIScreen mainScreen] bounds];
    UIView *root = [[UIView alloc] initWithFrame:bounds];
    root.backgroundColor = [UIColor blackColor];

    self.previewView = [[UIView alloc] initWithFrame:CGRectZero];
    self.previewView.backgroundColor = [UIColor blackColor];
    self.previewView.clipsToBounds = YES;
    [root addSubview:self.previewView];

    RLVLegacyChromeView *top = [[RLVLegacyChromeView alloc] initWithFrame:CGRectZero];
    top.top = YES;
    self.topChromeView = top;
    [root addSubview:top];

    RLVLegacyChromeView *bottom = [[RLVLegacyChromeView alloc] initWithFrame:CGRectZero];
    bottom.top = NO;
    self.bottomChromeView = bottom;
    [root addSubview:bottom];

    self.flashButton = [self chromeButtonWithTitle:@"Flash Auto"];
    self.flashButton.titleLabel.font = [UIFont boldSystemFontOfSize:11.0];
    [top addSubview:self.flashButton];

    self.cameraSwitchButton = [self chromeButtonWithTitle:@"↻"];
    self.cameraSwitchButton.titleLabel.font = [UIFont boldSystemFontOfSize:23.0];
    self.cameraSwitchButton.accessibilityLabel = @"Switch Camera";
    [top addSubview:self.cameraSwitchButton];

    self.thumbnailButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.thumbnailButton.layer.borderColor = [UIColor colorWithWhite:0.75 alpha:1].CGColor;
    self.thumbnailButton.layer.borderWidth = 1.0;
    self.thumbnailButton.layer.cornerRadius = 3.0;
    self.thumbnailButton.accessibilityLabel = @"Last Photo";
    [bottom addSubview:self.thumbnailButton];

    self.shutterButton = [[RLVLegacyShutterButton alloc] initWithFrame:CGRectZero];
    [bottom addSubview:self.shutterButton];

    UILabel *mode = [[UILabel alloc] initWithFrame:CGRectZero];
    mode.tag = 6001;
    mode.backgroundColor = [UIColor clearColor];
    mode.text = @"PHOTO";
    mode.textColor = [UIColor colorWithWhite:0.88 alpha:1];
    mode.font = [UIFont boldSystemFontOfSize:9.0];
    mode.textAlignment = NSTextAlignmentCenter;
    mode.shadowColor = [UIColor blackColor];
    mode.shadowOffset = CGSizeMake(0, -1);
    [bottom addSubview:mode];

    self.rotatingControls = [NSArray arrayWithObjects:self.flashButton, self.cameraSwitchButton, self.thumbnailButton, nil];
    self.view = root;
}

- (UIButton *)chromeButtonWithTitle:(NSString *)title
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:0.9 alpha:1] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:0.58 alpha:1] forState:UIControlStateHighlighted];
    button.titleLabel.shadowColor = [UIColor blackColor];
    button.titleLabel.shadowOffset = CGSizeMake(0, -1);
    return button;
}

- (void)viewDidLayoutSubviews
{
    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat height = CGRectGetHeight(self.view.bounds);
    CGFloat topHeight = 44.0;
    CGFloat bottomHeight = height <= 480.0 ? 88.0 : 96.0;
    self.topChromeView.frame = CGRectMake(0, 0, width, topHeight);
    self.bottomChromeView.frame = CGRectMake(0, height - bottomHeight, width, bottomHeight);
    self.previewView.frame = CGRectMake(0, topHeight, width, height - topHeight - bottomHeight);
    self.flashButton.frame = CGRectMake(4, 0, 86, topHeight);
    self.cameraSwitchButton.frame = CGRectMake(width - 58, 0, 54, topHeight);
    self.shutterButton.frame = CGRectMake((width - 76) / 2.0, 5.0, 76, 76);
    self.thumbnailButton.frame = CGRectMake(14, (bottomHeight - 48) / 2.0, 48, 48);
    UIView *mode = [self.bottomChromeView viewWithTag:6001];
    mode.frame = CGRectMake(width - 70, (bottomHeight - 25) / 2.0, 54, 25);
    [super viewDidLayoutSubviews];
}

@end
