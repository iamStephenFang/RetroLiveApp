#import "RLVShutterButton.h"
#import <QuartzCore/QuartzCore.h>

@implementation RLVShutterButton

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.accessibilityLabel = @"Shutter";
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

@implementation RLVLegacyShutterButton

- (void)drawRect:(CGRect)rect
{
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
