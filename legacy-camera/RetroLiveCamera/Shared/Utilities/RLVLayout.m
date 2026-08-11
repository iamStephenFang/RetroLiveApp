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
