#import "RLVTransferViewController.h"
#import "RLVLayout.h"
#import "RLVTransferService.h"

@interface RLVTransferViewController ()
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *addressLabel;
@property (nonatomic, strong) UILabel *codeLabel;
@property (nonatomic, strong) UILabel *noteLabel;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIScrollView *scrollView;
@end

@implementation RLVTransferViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.title = NSLocalizedString(@"transfer.title", nil);
    self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    self.statusLabel = [self labelWithFontSize:18.0];
    self.addressLabel = [self labelWithFontSize:15.0];
    self.codeLabel = [self labelWithFontSize:42.0];
    self.codeLabel.font = [UIFont boldSystemFontOfSize:42.0];
    self.noteLabel = [self labelWithFontSize:14.0];
    self.noteLabel.numberOfLines = 0;
    self.noteLabel.textColor = [UIColor colorWithWhite:0.72 alpha:1.0];
#if RLV_CLASSIC
    self.actionButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
#else
    self.actionButton = RLVCreateMetalButton();
#endif
    self.actionButton.titleLabel.font = [UIFont boldSystemFontOfSize:18.0];
    [self.actionButton addTarget:self action:@selector(actionPressed:) forControlEvents:UIControlEventTouchUpInside];
    self.contentView = [[UIView alloc] initWithFrame:CGRectZero];
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.scrollView.alwaysBounceVertical = NO;
    [self.view addSubview:self.scrollView];
    [self.scrollView addSubview:self.contentView];
    [self.contentView addSubview:self.statusLabel];
    [self.contentView addSubview:self.addressLabel];
    [self.contentView addSubview:self.codeLabel];
    [self.contentView addSubview:self.noteLabel];
    [self.contentView addSubview:self.actionButton];

    RLVPrepareViewsForAutoLayout(@[self.scrollView, self.contentView, self.statusLabel, self.addressLabel,
        self.codeLabel, self.noteLabel, self.actionButton]);
    RLVPinViewToEdges(self.scrollView, self.view);
    RLVAddVisualConstraints(self.scrollView, @{@"content": self.contentView},
        @[@"H:|-16-[content]-16-|", @"V:|-20-[content]-20-|"]);
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.contentView
        attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:self.view
        attribute:NSLayoutAttributeWidth multiplier:1.0 constant:-32.0]];
    RLVAddVisualConstraints(self.contentView,
        @{@"status": self.statusLabel, @"address": self.addressLabel, @"code": self.codeLabel,
          @"note": self.noteLabel, @"action": self.actionButton},
        @[@"H:|[status]|", @"H:|[address]|", @"H:|[code]|", @"H:|-8-[note]-8-|",
          @"H:|-24-[action]-24-|",
          @"V:|[status(28)]-14-[address(24)]-20-[code(58)]-20-[note(82)]-18-[action(48)]|"]);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateContent)
        name:RLVTransferServiceDidChangeNotification object:nil];
    [self updateContent];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGFloat extra = MAX(0.0, (CGRectGetHeight(self.scrollView.bounds) - self.scrollView.contentSize.height) / 2.0);
    self.scrollView.contentInset = UIEdgeInsetsMake(extra, 0.0, extra, 0.0);
}

- (UILabel *)labelWithFontSize:(CGFloat)fontSize
{
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = [UIColor whiteColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:fontSize];
    return label;
}

- (void)actionPressed:(id)sender
{
    (void)sender;
    RLVTransferService *service = [RLVTransferService sharedService];
    if (service.running) {
        [service stop];
    } else {
        NSError *error = nil;
        if (![service start:&error]) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"transfer.error.title", nil)
                message:[error localizedDescription] delegate:nil cancelButtonTitle:NSLocalizedString(@"common.ok", nil)
                otherButtonTitles:nil];
            [alert show];
        }
    }
}

- (void)updateContent
{
    RLVTransferService *service = [RLVTransferService sharedService];
    if (service.running) {
        self.statusLabel.text = NSLocalizedString(@"transfer.status.on", nil);
        self.addressLabel.text = [NSString stringWithFormat:@"http://%@:%lu", service.localAddress, (unsigned long)service.port];
        self.codeLabel.text = service.pairingCode;
        self.noteLabel.text = NSLocalizedString(@"transfer.note.on", nil);
        [self.actionButton setTitle:NSLocalizedString(@"transfer.stop", nil) forState:UIControlStateNormal];
    } else {
        self.statusLabel.text = NSLocalizedString(@"transfer.status.off", nil);
        self.addressLabel.text = NSLocalizedString(@"transfer.no_server", nil);
        self.codeLabel.text = @"------";
        self.noteLabel.text = NSLocalizedString(@"transfer.note.off", nil);
        [self.actionButton setTitle:NSLocalizedString(@"transfer.start", nil) forState:UIControlStateNormal];
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@synthesize statusLabel = _statusLabel;
@synthesize addressLabel = _addressLabel;
@synthesize codeLabel = _codeLabel;
@synthesize noteLabel = _noteLabel;
@synthesize actionButton = _actionButton;
@synthesize contentView = _contentView;
@synthesize scrollView = _scrollView;

@end
