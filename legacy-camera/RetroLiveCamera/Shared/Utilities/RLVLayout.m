#import "RLVLayout.h"
#import <QuartzCore/QuartzCore.h>

@interface RLVMetalButton : UIButton
@end

@implementation RLVMetalButton

- (void)drawRect:(CGRect)rect
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect metalRect = CGRectInset(self.bounds, 1.5, 1.5);
    UIBezierPath *metalPath = [UIBezierPath bezierPathWithRoundedRect:metalRect cornerRadius:7.0];

    CGContextSaveGState(context);
    [metalPath addClip];

    BOOL pressed = self.highlighted;
    NSArray *colors = pressed
        ? @[(id)[UIColor colorWithWhite:0.67 alpha:1.0].CGColor,
            (id)[UIColor colorWithWhite:0.53 alpha:1.0].CGColor,
            (id)[UIColor colorWithWhite:0.40 alpha:1.0].CGColor]
        : @[(id)[UIColor colorWithWhite:0.96 alpha:1.0].CGColor,
            (id)[UIColor colorWithWhite:0.79 alpha:1.0].CGColor,
            (id)[UIColor colorWithWhite:0.59 alpha:1.0].CGColor];
    CGFloat locations[] = {0.0, 0.52, 1.0};
    CGGradientRef gradient = CGGradientCreateWithColors(NULL, (__bridge CFArrayRef)colors, locations);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0.0, CGRectGetMinY(metalRect)),
        CGPointMake(0.0, CGRectGetMaxY(metalRect)), 0);
    CGGradientRelease(gradient);

    CGContextRestoreGState(context);

    [[UIColor colorWithWhite:0.18 alpha:0.95] setStroke];
    metalPath.lineWidth = 1.0;
    [metalPath stroke];
    UIBezierPath *innerPath = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(metalRect, 1.0, 1.0)
        cornerRadius:6.0];
    [[UIColor colorWithWhite:1.0 alpha:pressed ? 0.20 : 0.62] setStroke];
    innerPath.lineWidth = 1.0;
    [innerPath stroke];

    [super drawRect:rect];
}

- (void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    [self setNeedsDisplay];
}

- (void)setEnabled:(BOOL)enabled
{
    [super setEnabled:enabled];
    self.alpha = enabled ? 1.0 : 0.52;
    [self setNeedsDisplay];
}

@end

void RLVPrepareViewsForAutoLayout(NSArray *views)
{
    for (UIView *view in views) view.translatesAutoresizingMaskIntoConstraints = NO;
}

void RLVAddVisualConstraints(UIView *container, NSDictionary *views, NSArray *formats)
{
    for (NSString *format in formats) {
        [container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:format
            options:0 metrics:nil views:views]];
    }
}

void RLVPinViewToEdges(UIView *view, UIView *container)
{
    RLVPrepareViewsForAutoLayout(@[view]);
    RLVAddVisualConstraints(container, @{@"view": view}, @[@"H:|[view]|", @"V:|[view]|"]);
}

void RLVAlignViews(UIView *container, UIView *firstView, NSLayoutAttribute firstAttribute,
                   UIView *secondView, NSLayoutAttribute secondAttribute)
{
    [container addConstraint:[NSLayoutConstraint constraintWithItem:firstView attribute:firstAttribute
        relatedBy:NSLayoutRelationEqual toItem:secondView attribute:secondAttribute multiplier:1 constant:0]];
}

UIButton *RLVCreateMetalButton(void)
{
    RLVMetalButton *button = [RLVMetalButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor = [UIColor clearColor];
    button.opaque = NO;
    button.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
    button.titleLabel.shadowOffset = CGSizeMake(0.0, 1.0);
    [button setTitleColor:[UIColor colorWithWhite:0.12 alpha:1.0] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:0.08 alpha:1.0] forState:UIControlStateHighlighted];
    [button setTitleShadowColor:[UIColor colorWithWhite:1.0 alpha:0.68] forState:UIControlStateNormal];
    [button setTitleShadowColor:[UIColor colorWithWhite:1.0 alpha:0.30] forState:UIControlStateHighlighted];
    button.layer.shadowColor = [UIColor blackColor].CGColor;
    button.layer.shadowOpacity = 0.42;
    button.layer.shadowOffset = CGSizeMake(0.0, 1.0);
    button.layer.shadowRadius = 1.5;
    return button;
}

void RLVInstallCameraLayout(UIView *rootView, UIView *previewView,
    UIView *topChromeView, UIView *bottomChromeView, UIView *flashButton, UIView *livePhotoButton,
    UIView *aspectRatioButton, UIView *thumbnailButton, UIView *shutterButton, CGSize shutterSize,
    CGFloat bottomHeight, CGFloat sideControlSize, UIView *cameraSwitchButton)
{
    RLVPrepareViewsForAutoLayout(@[previewView, topChromeView, bottomChromeView, flashButton,
        livePhotoButton, aspectRatioButton, thumbnailButton, shutterButton, cameraSwitchButton]);
    RLVAddVisualConstraints(rootView,
        @{@"preview": previewView, @"top": topChromeView, @"bottom": bottomChromeView},
        @[@"H:|[top]|", @"H:|[preview]|", @"H:|[bottom]|",
          [NSString stringWithFormat:@"V:|[top(44)][preview][bottom(%.0f)]|", bottomHeight]]);
    RLVAddVisualConstraints(topChromeView,
        @{@"flash": flashButton, @"live": livePhotoButton, @"aspect": aspectRatioButton},
        @[@"H:|-4-[flash(44)]", @"V:|[flash]|", @"H:[live(52)]", @"V:|[live]|",
          @"H:[aspect(52)]-4-|", @"V:|[aspect]|"]);
    RLVAlignViews(topChromeView, livePhotoButton, NSLayoutAttributeCenterX,
        topChromeView, NSLayoutAttributeCenterX);
    RLVAddVisualConstraints(bottomChromeView,
        @{@"thumbnail": thumbnailButton, @"shutter": shutterButton, @"switch": cameraSwitchButton},
        @[[NSString stringWithFormat:@"H:|-14-[thumbnail(%.0f)]", sideControlSize],
          [NSString stringWithFormat:@"H:[switch(%.0f)]-14-|", sideControlSize],
          [NSString stringWithFormat:@"V:[thumbnail(%.0f)]", sideControlSize],
          [NSString stringWithFormat:@"V:[switch(%.0f)]", sideControlSize]]);
    [bottomChromeView addConstraint:[NSLayoutConstraint constraintWithItem:shutterButton
        attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil
        attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0 constant:shutterSize.width]];
    [bottomChromeView addConstraint:[NSLayoutConstraint constraintWithItem:shutterButton
        attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil
        attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0 constant:shutterSize.height]];
    RLVAlignViews(bottomChromeView, thumbnailButton, NSLayoutAttributeCenterY,
        bottomChromeView, NSLayoutAttributeCenterY);
    RLVAlignViews(bottomChromeView, shutterButton, NSLayoutAttributeCenterX,
        bottomChromeView, NSLayoutAttributeCenterX);
    RLVAlignViews(bottomChromeView, shutterButton, NSLayoutAttributeCenterY,
        bottomChromeView, NSLayoutAttributeCenterY);
    RLVAlignViews(bottomChromeView, cameraSwitchButton, NSLayoutAttributeCenterY,
        bottomChromeView, NSLayoutAttributeCenterY);
}
