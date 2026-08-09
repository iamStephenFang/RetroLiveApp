#import "RLVAssetDetailViewController.h"

@interface RLVAssetDetailViewController ()
@property (nonatomic, strong) RLVAsset *asset;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *metadataLabel;
@end

@implementation RLVAssetDetailViewController

- (id)initWithAsset:(RLVAsset *)asset
{
    self = [super init];
    if (self) _asset = asset;
    return self;
}

- (void)loadView
{
    UIView *root = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    root.backgroundColor = [UIColor blackColor];
    self.imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.image = [UIImage imageWithContentsOfFile:[self.asset.photoURL path]];
    [root addSubview:self.imageView];
    self.metadataLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.metadataLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.82];
    self.metadataLabel.textColor = [UIColor whiteColor];
    self.metadataLabel.font = [UIFont systemFontOfSize:12.0];
    self.metadataLabel.numberOfLines = 3;
    self.metadataLabel.textAlignment = NSTextAlignmentCenter;
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterMediumStyle;
    self.metadataLabel.text = [NSString stringWithFormat:@"%@\n%lu × %lu\n%@",
        [formatter stringFromDate:self.asset.captureTimestamp], (unsigned long)self.asset.width,
        (unsigned long)self.asset.height, self.asset.captureDevice ?: @"Unknown device"];
    [root addSubview:self.metadataLabel];
    self.view = root;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGFloat height = CGRectGetHeight(self.view.bounds);
    self.imageView.frame = self.view.bounds;
    self.metadataLabel.frame = CGRectMake(0, height - 82, CGRectGetWidth(self.view.bounds), 82);
}

@synthesize asset = _asset;
@synthesize imageView = _imageView;
@synthesize metadataLabel = _metadataLabel;

@end
