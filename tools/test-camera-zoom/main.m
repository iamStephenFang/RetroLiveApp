#import "RLVZoomMath.h"
#import <Foundation/Foundation.h>

static void RLVAssertClose(CGFloat actual, CGFloat expected, NSString *name)
{
    if (fabs(actual - expected) > 0.0001) {
        NSLog(@"FAIL %@: expected %.3f, got %.3f", name, expected, actual);
        exit(1);
    }
}

int main(void)
{
    @autoreleasepool {
        RLVAssertClose(RLVClampZoomFactor(0.5, 3.0), 1.0, @"lower clamp");
        RLVAssertClose(RLVClampZoomFactor(4.0, 3.0), 3.0, @"upper clamp");
        RLVAssertClose(RLVClampZoomFactor(NAN, 3.0), 1.0, @"invalid request");
        RLVAssertClose(RLVClampZoomFactor(2.0, 1.0), 1.0, @"unsupported device");
        RLVAssertClose(RLVZoomFactorForGesture(1.5, 1.4, 3.0), 2.1,
                       @"gesture multiplication");
        RLVAssertClose(RLVZoomFactorForGesture(2.5, 0.5, 3.0), 1.25,
                       @"gesture reversal");
        RLVAssertClose(RLVZoomFactorForDoubleTap(1.0, 3.0), 2.0,
                       @"double tap zoom in");
        RLVAssertClose(RLVZoomFactorForDoubleTap(2.0, 3.0), 1.0,
                       @"double tap zoom out");
        RLVAssertClose(RLVZoomFactorForDoubleTap(1.0, 1.5), 1.5,
                       @"double tap device limit");
        RLVAssertClose(RLVZoomFactorForGesture(3.0, 1.2, 3.0), 3.0,
                       @"outward pinch stays at maximum");
        RLVAssertClose(RLVZoomFactorForGesture(3.0, 0.98, 3.0), 2.94,
                       @"reverse immediately from maximum");
        NSCAssert(RLVZoomRequestGenerationIsCurrent(7, 7), @"latest generation resolves");
        NSCAssert(!RLVZoomRequestGenerationIsCurrent(6, 7), @"stale generation is ignored");
        NSCAssert(RLVZoomRequestGenerationIsCurrent(0, 7), @"lifecycle update resolves");
        NSCAssert(!RLVZoomFactorRequiresPersistentFeedback(1.0), @"1x feedback is transient");
        NSCAssert(!RLVZoomFactorRequiresPersistentFeedback(1.00001), @"1x noise is transient");
        NSCAssert(RLVZoomFactorRequiresPersistentFeedback(1.01), @"non-1x feedback persists");
        NSCAssert(!RLVZoomFactorRequiresPersistentFeedback(NAN), @"invalid feedback is transient");
        NSLog(@"Camera zoom math/state: 18 checks passed");
    }
    return 0;
}
