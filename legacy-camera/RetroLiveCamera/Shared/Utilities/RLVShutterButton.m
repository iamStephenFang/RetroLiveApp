#import "RLVShutterButton.h"
#import <QuartzCore/QuartzCore.h>

@implementation RLVShutterButton

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.accessibilityLabel = NSLocalizedString(@"camera.shutter", nil);
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    [self setNeedsDisplay];
}

- (void)setEnabled:(BOOL)enabled
{
    [super setEnabled:enabled];
    [self setNeedsDisplay];
}

- (void)setCapturing:(BOOL)capturing
{
    _capturing = capturing;
    [self setNeedsDisplay];
}

@synthesize capturing = _capturing;

@end

@interface RLVLegacyShutterButton ()
- (void)drawCompactCameraButtonInRect:(CGRect)rect;
@end

@implementation RLVLegacyShutterButton

- (void)drawRect:(CGRect)rect
{
    if (CGRectGetWidth(rect) > CGRectGetHeight(rect) * 1.4) {
        [self drawCompactCameraButtonInRect:rect];
        return;
    }

    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect ring = CGRectInset(rect, 5.0, 5.0);
    CGContextSaveGState(context);
    CGContextSetShadowWithColor(context, CGSizeMake(0, 1), 2.0, [[UIColor colorWithWhite:0 alpha:0.9] CGColor]);
    CGContextSetFillColorWithColor(context, [[UIColor colorWithRed:0.27 green:0.28 blue:0.29 alpha:1] CGColor]);
    CGContextFillEllipseInRect(context, ring);
    CGContextRestoreGState(context);

    CGContextSetLineWidth(context, 2.0);
    CGContextSetStrokeColorWithColor(context, [[UIColor colorWithWhite:0.78 alpha:1] CGColor]);
    CGContextStrokeEllipseInRect(context, CGRectInset(ring, 1.0, 1.0));

    CGRect face = CGRectInset(ring, 8.0, 8.0);
    CGFloat white = !self.enabled ? 0.48 : (self.highlighted || self.isCapturing ? 0.66 : 0.92);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = [NSArray arrayWithObjects:(id)[UIColor colorWithWhite:MIN(1.0, white + 0.08) alpha:1].CGColor,
                       (id)[UIColor colorWithWhite:MAX(0.0, white - 0.12) alpha:1].CGColor, nil];
    CGGradientRef gradient = CGGradientCreateWithColors(colorSpace, (__bridge CFArrayRef)colors, NULL);
    CGContextSaveGState(context);
    CGContextAddEllipseInRect(context, face);
    CGContextClip(context);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, CGRectGetMinY(face)), CGPointMake(0, CGRectGetMaxY(face)), 0);
    CGContextRestoreGState(context);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);
    CGContextSetStrokeColorWithColor(context, [[UIColor whiteColor] CGColor]);
    CGContextSetLineWidth(context, 1.0);
    CGContextStrokeEllipseInRect(context, CGRectInset(face, 0.5, 0.5));
}

- (void)drawCompactCameraButtonInRect:(CGRect)rect
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect buttonRect = CGRectInset(rect, 2.0, 7.0);
    CGFloat radius = CGRectGetHeight(buttonRect) * 0.5;
    UIBezierPath *buttonPath = [UIBezierPath bezierPathWithRoundedRect:buttonRect cornerRadius:radius];

    CGContextSaveGState(context);
    CGContextSetShadowWithColor(context, CGSizeMake(0.0, 1.0), 2.0,
        [UIColor colorWithWhite:0.0 alpha:0.85].CGColor);
    [[UIColor colorWithWhite:0.20 alpha:1.0] setFill];
    [buttonPath fill];
    CGContextRestoreGState(context);

    CGFloat white = !self.enabled ? 0.48 : (self.highlighted || self.isCapturing ? 0.62 : 0.88);
    CGRect faceRect = CGRectInset(buttonRect, 2.0, 2.0);
    UIBezierPath *facePath = [UIBezierPath bezierPathWithRoundedRect:faceRect
        cornerRadius:CGRectGetHeight(faceRect) * 0.5];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = [NSArray arrayWithObjects:
        (id)[UIColor colorWithWhite:MIN(1.0, white + 0.10) alpha:1.0].CGColor,
        (id)[UIColor colorWithWhite:MAX(0.0, white - 0.16) alpha:1.0].CGColor, nil];
    CGGradientRef gradient = CGGradientCreateWithColors(colorSpace, (__bridge CFArrayRef)colors, NULL);
    CGContextSaveGState(context);
    [facePath addClip];
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0.0, CGRectGetMinY(faceRect)),
        CGPointMake(0.0, CGRectGetMaxY(faceRect)), 0);
    CGContextRestoreGState(context);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);

    [[UIColor colorWithWhite:0.96 alpha:0.9] setStroke];
    facePath.lineWidth = 1.0;
    [facePath stroke];

    UIColor *iconColor = self.enabled ? [UIColor colorWithWhite:0.15 alpha:1.0]
                                      : [UIColor colorWithWhite:0.34 alpha:1.0];
    [iconColor setFill];
    CGFloat centerX = CGRectGetMidX(rect);
    CGFloat centerY = CGRectGetMidY(rect) + 1.0;
    UIBezierPath *cameraBody = [UIBezierPath bezierPathWithRoundedRect:
        CGRectMake(centerX - 11.0, centerY - 6.0, 22.0, 13.0) cornerRadius:2.5];
    [cameraBody fill];
    UIRectFill(CGRectMake(centerX - 5.0, centerY - 9.0, 10.0, 4.0));
    [[UIColor colorWithWhite:0.72 alpha:1.0] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(centerX - 4.0, centerY - 4.0, 8.0, 8.0)] fill];
    [iconColor setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(centerX - 2.5, centerY - 2.5, 5.0, 5.0)] fill];
}

@end

@implementation RLVClassicShutterButton

- (void)drawRect:(CGRect)rect
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect outer = CGRectInset(rect, 3.0, 3.0);
    UIColor *ringColor = self.enabled ? [UIColor whiteColor] : [UIColor colorWithWhite:0.55 alpha:1];
    CGContextSetStrokeColorWithColor(context, ringColor.CGColor);
    CGContextSetLineWidth(context, 4.0);
    CGContextStrokeEllipseInRect(context, CGRectInset(outer, 2.0, 2.0));
    CGFloat alpha = (self.highlighted || self.isCapturing) ? 0.68 : 1.0;
    CGContextSetFillColorWithColor(context, [[UIColor colorWithWhite:0.96 alpha:alpha] CGColor]);
    CGContextFillEllipseInRect(context, CGRectInset(outer, 9.0, 9.0));
}

@end
