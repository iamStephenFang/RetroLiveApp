#import "RLVLayout.h"

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
