#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <math.h>

/// Pure zoom arithmetic shared by UIKit gesture handling and capture clamping.
/// Invalid factors preserve the lower bound instead of reaching AVFoundation.
static inline CGFloat RLVClampZoomFactor(CGFloat factor, CGFloat maximumFactor)
{
    CGFloat maximum = isfinite(maximumFactor) ? fmax(1.0, maximumFactor) : 1.0;
    if (!isfinite(factor) || factor <= 0.0) return 1.0;
    return fmax(1.0, fmin(factor, maximum));
}

static inline CGFloat RLVZoomFactorForGesture(CGFloat startingFactor,
                                               CGFloat gestureScale,
                                               CGFloat maximumFactor)
{
    if (!isfinite(startingFactor) || startingFactor <= 0.0 ||
        !isfinite(gestureScale) || gestureScale <= 0.0) return 1.0;
    return RLVClampZoomFactor(startingFactor * gestureScale, maximumFactor);
}

static inline CGFloat RLVZoomFactorForDoubleTap(CGFloat currentFactor,
                                                CGFloat maximumFactor)
{
    if (!isfinite(currentFactor) || currentFactor <= 0.0) currentFactor = 1.0;
    return currentFactor > 1.05 ? 1.0 : RLVClampZoomFactor(2.0, maximumFactor);
}

static inline BOOL RLVZoomRequestGenerationIsCurrent(NSUInteger requestGeneration,
                                                      NSUInteger currentGeneration)
{
    return requestGeneration == 0 || requestGeneration == currentGeneration;
}

/// Treat only floating-point noise around the optical baseline as 1.0x.
static inline BOOL RLVZoomFactorRequiresPersistentFeedback(CGFloat factor)
{
    return isfinite(factor) && fabs(factor - 1.0) > 0.0001;
}
