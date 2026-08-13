#import "RLVOnboardingViewController.h"
#import "RLVLayout.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

@interface RLVOnboardingBackgroundView : UIView
@end

@implementation RLVOnboardingBackgroundView

- (void)drawRect:(CGRect)rect
{
#if RLV_CLASSIC
    [[UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1.0] setFill];
    UIRectFill(rect);
#else
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = [NSArray arrayWithObjects:
        (id)[UIColor colorWithRed:0.20 green:0.21 blue:0.23 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.055 green:0.06 blue:0.07 alpha:1.0].CGColor, nil];
    CGGradientRef gradient = CGGradientCreateWithColors(colorSpace, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0.0, 0.0),
        CGPointMake(0.0, CGRectGetHeight(rect)), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);
#endif
}

@end

@interface RLVOnboardingViewController ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) NSArray *featureViews;
@property (nonatomic, strong) UILabel *permissionLabel;
@property (nonatomic, strong) UIButton *continueButton;
@property (nonatomic, assign) BOOL requestingPermissions;
- (UIView *)featureViewWithNumber:(NSString *)number titleKey:(NSString *)titleKey detailKey:(NSString *)detailKey;
- (void)continuePressed:(id)sender;
- (void)requestMicrophoneAndFinish;
- (void)finishOnboarding;
@end

@implementation RLVOnboardingViewController

- (void)loadView
{
    RLVOnboardingBackgroundView *root = [[RLVOnboardingBackgroundView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.backgroundColor = [UIColor clearColor];
    self.titleLabel.text = @"RetroLive";
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.isAccessibilityElement = YES;

    self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.subtitleLabel.backgroundColor = [UIColor clearColor];
    self.subtitleLabel.text = NSLocalizedString(@"onboarding.subtitle", nil);
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.numberOfLines = 2;

    UIView *liveFeature = [self featureViewWithNumber:@"1" titleKey:@"onboarding.feature.live.title"
        detailKey:@"onboarding.feature.live.detail"];
    UIView *localFeature = [self featureViewWithNumber:@"2" titleKey:@"onboarding.feature.local.title"
        detailKey:@"onboarding.feature.local.detail"];
    UIView *transferFeature = [self featureViewWithNumber:@"3" titleKey:@"onboarding.feature.transfer.title"
        detailKey:@"onboarding.feature.transfer.detail"];
    self.featureViews = [NSArray arrayWithObjects:liveFeature, localFeature, transferFeature, nil];

    if ([AVCaptureDevice respondsToSelector:@selector(requestAccessForMediaType:completionHandler:)]) {
        self.permissionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.permissionLabel.backgroundColor = [UIColor clearColor];
        self.permissionLabel.text = NSLocalizedString(@"onboarding.permission.ios7", nil);
        self.permissionLabel.textAlignment = NSTextAlignmentCenter;
        self.permissionLabel.numberOfLines = 2;
    }

#if RLV_CLASSIC
    self.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Light" size:36.0] ?: [UIFont systemFontOfSize:36.0];
    self.titleLabel.textColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.subtitleLabel.font = [UIFont systemFontOfSize:15.0];
    self.subtitleLabel.textColor = [UIColor colorWithWhite:0.38 alpha:1.0];
    self.permissionLabel.font = [UIFont systemFontOfSize:10.0];
    self.permissionLabel.textColor = [UIColor colorWithWhite:0.52 alpha:1.0];
    self.continueButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.continueButton.backgroundColor = [UIColor colorWithRed:0.05 green:0.51 blue:0.78 alpha:1.0];
    self.continueButton.layer.cornerRadius = 5.0;
    [self.continueButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.continueButton setTitle:NSLocalizedString(@"onboarding.continue.ios7", nil) forState:UIControlStateNormal];
#else
    self.titleLabel.font = [UIFont boldSystemFontOfSize:34.0];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.shadowColor = [UIColor blackColor];
    self.titleLabel.shadowOffset = CGSizeMake(0.0, -1.0);
    self.subtitleLabel.font = [UIFont systemFontOfSize:15.0];
    self.subtitleLabel.textColor = [UIColor colorWithWhite:0.82 alpha:1.0];
    self.permissionLabel.font = [UIFont systemFontOfSize:10.0];
    self.permissionLabel.textColor = [UIColor colorWithWhite:0.58 alpha:1.0];
    self.continueButton = RLVCreateMetalButton();
    [self.continueButton setTitle:NSLocalizedString(@"onboarding.continue.ios6", nil) forState:UIControlStateNormal];
#endif
    self.continueButton.accessibilityHint = NSLocalizedString(@"onboarding.continue.hint", nil);
    [self.continueButton addTarget:self action:@selector(continuePressed:) forControlEvents:UIControlEventTouchUpInside];

    [root addSubview:self.titleLabel];
    [root addSubview:self.subtitleLabel];
    for (UIView *featureView in self.featureViews) [root addSubview:featureView];
    if (self.permissionLabel) [root addSubview:self.permissionLabel];
    [root addSubview:self.continueButton];
}

- (UIView *)featureViewWithNumber:(NSString *)number titleKey:(NSString *)titleKey detailKey:(NSString *)detailKey
{
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
#if RLV_CLASSIC
    view.backgroundColor = [UIColor whiteColor];
    view.layer.borderColor = [UIColor colorWithWhite:0.86 alpha:1.0].CGColor;
    view.layer.borderWidth = 0.5;
#else
    view.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    view.layer.borderWidth = 1.0;
    view.layer.cornerRadius = 6.0;
    view.layer.shadowColor = [UIColor blackColor].CGColor;
    view.layer.shadowOpacity = 0.35;
    view.layer.shadowOffset = CGSizeMake(0.0, 1.0);
    view.layer.shadowRadius = 1.0;
#endif

    UILabel *badge = [[UILabel alloc] initWithFrame:CGRectZero];
    badge.tag = 101;
    badge.backgroundColor = [UIColor colorWithRed:0.05 green:0.51 blue:0.78 alpha:1.0];
    badge.text = number;
    badge.textColor = [UIColor whiteColor];
    badge.font = [UIFont boldSystemFontOfSize:14.0];
    badge.textAlignment = NSTextAlignmentCenter;
    badge.layer.cornerRadius = 15.0;
    badge.clipsToBounds = YES;
    badge.isAccessibilityElement = NO;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.tag = 102;
    title.backgroundColor = [UIColor clearColor];
    title.text = NSLocalizedString(titleKey, nil);
    title.font = [UIFont boldSystemFontOfSize:14.0];
#if RLV_CLASSIC
    title.textColor = [UIColor colorWithWhite:0.16 alpha:1.0];
#else
    title.textColor = [UIColor whiteColor];
#endif

    UILabel *detail = [[UILabel alloc] initWithFrame:CGRectZero];
    detail.tag = 103;
    detail.backgroundColor = [UIColor clearColor];
    detail.text = NSLocalizedString(detailKey, nil);
    detail.font = [UIFont systemFontOfSize:11.0];
#if RLV_CLASSIC
    detail.textColor = [UIColor colorWithWhite:0.43 alpha:1.0];
#else
    detail.textColor = [UIColor colorWithWhite:0.74 alpha:1.0];
#endif
    detail.numberOfLines = 2;

    view.isAccessibilityElement = YES;
    view.accessibilityLabel = [NSString stringWithFormat:@"%@. %@", title.text, detail.text];
    [view addSubview:badge];
    [view addSubview:title];
    [view addSubview:detail];
    return view;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    BOOL compact = height <= 480.0;
    CGFloat horizontalMargin = 20.0;
    CGFloat featureHeight = compact ? 60.0 : 64.0;
    CGFloat featureGap = compact ? 7.0 : 10.0;
    CGFloat top = compact ? 20.0 : 38.0;

    self.titleLabel.frame = CGRectMake(horizontalMargin, top, width - horizontalMargin * 2.0, 42.0);
    self.subtitleLabel.frame = CGRectMake(horizontalMargin, CGRectGetMaxY(self.titleLabel.frame) + (compact ? 7.0 : 8.0),
        width - horizontalMargin * 2.0, compact ? 34.0 : 40.0);

    CGFloat featureY = CGRectGetMaxY(self.subtitleLabel.frame) + (compact ? 14.0 : 18.0);
    for (UIView *featureView in self.featureViews) {
        featureView.frame = CGRectMake(horizontalMargin, featureY, width - horizontalMargin * 2.0, featureHeight);
        UILabel *badge = (UILabel *)[featureView viewWithTag:101];
        UILabel *title = (UILabel *)[featureView viewWithTag:102];
        UILabel *detail = (UILabel *)[featureView viewWithTag:103];
        badge.frame = CGRectMake(12.0, (featureHeight - 30.0) * 0.5, 30.0, 30.0);
        title.frame = CGRectMake(54.0, 8.0, CGRectGetWidth(featureView.bounds) - 64.0, 18.0);
        detail.frame = CGRectMake(54.0, 29.0, CGRectGetWidth(featureView.bounds) - 64.0, featureHeight - 33.0);
        featureY = CGRectGetMaxY(featureView.frame) + featureGap;
    }

    CGFloat buttonHeight = 46.0;
    CGFloat buttonY = height - buttonHeight - (compact ? 16.0 : 24.0);
    self.continueButton.frame = CGRectMake(horizontalMargin, buttonY, width - horizontalMargin * 2.0, buttonHeight);
    if (self.permissionLabel) {
        self.permissionLabel.frame = CGRectMake(horizontalMargin, buttonY - 28.0,
            width - horizontalMargin * 2.0, 24.0);
    }
}

- (BOOL)shouldAutorotate
{
    return NO;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
    return UIInterfaceOrientationPortrait;
}

- (void)continuePressed:(id)sender
{
    (void)sender;
    if (self.requestingPermissions) return;
    self.requestingPermissions = YES;
    self.continueButton.enabled = NO;

    if (![AVCaptureDevice respondsToSelector:@selector(requestAccessForMediaType:completionHandler:)]) {
        [self finishOnboarding];
        return;
    }

    AVAuthorizationStatus cameraStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (cameraStatus == AVAuthorizationStatusDenied || cameraStatus == AVAuthorizationStatusRestricted) {
        self.requestingPermissions = NO;
        self.continueButton.enabled = YES;
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"onboarding.camera.denied.title", nil)
            message:NSLocalizedString(@"onboarding.camera.denied.message", nil) delegate:nil
            cancelButtonTitle:NSLocalizedString(@"common.ok", nil) otherButtonTitles:nil];
        [alert show];
        return;
    }

    if (cameraStatus == AVAuthorizationStatusAuthorized) {
        [self requestMicrophoneAndFinish];
        return;
    }

    __weak RLVOnboardingViewController *controller = self;
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (granted) {
                [controller requestMicrophoneAndFinish];
            } else {
                controller.requestingPermissions = NO;
                controller.continueButton.enabled = YES;
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"onboarding.camera.denied.title", nil)
                    message:NSLocalizedString(@"onboarding.camera.denied.message", nil) delegate:nil
                    cancelButtonTitle:NSLocalizedString(@"common.ok", nil) otherButtonTitles:nil];
                [alert show];
            }
        });
    }];
}

- (void)requestMicrophoneAndFinish
{
    AVAuthorizationStatus microphoneStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (microphoneStatus != AVAuthorizationStatusNotDetermined) {
        [self finishOnboarding];
        return;
    }

    __weak RLVOnboardingViewController *controller = self;
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
        (void)granted;
        dispatch_async(dispatch_get_main_queue(), ^{ [controller finishOnboarding]; });
    }];
}

- (void)finishOnboarding
{
    self.requestingPermissions = NO;
    self.continueButton.enabled = YES;
    [self.delegate onboardingViewControllerDidFinish:self];
}

@synthesize delegate = _delegate;

@end
