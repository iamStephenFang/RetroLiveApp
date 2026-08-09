#import "RLVTransferViewController.h"
#import "RLVTransferService.h"

@interface RLVTransferViewController ()
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *addressLabel;
@property (nonatomic, strong) UILabel *codeLabel;
@property (nonatomic, strong) UILabel *noteLabel;
@property (nonatomic, strong) UIButton *actionButton;
@end

@implementation RLVTransferViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = NSLocalizedString(@"transfer.title", nil);
    self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    self.statusLabel = [self labelWithFontSize:18.0];
    self.addressLabel = [self labelWithFontSize:15.0];
    self.codeLabel = [self labelWithFontSize:42.0];
    self.codeLabel.font = [UIFont boldSystemFontOfSize:42.0];
    self.noteLabel = [self labelWithFontSize:14.0];
    self.noteLabel.numberOfLines = 0;
    self.noteLabel.textColor = [UIColor colorWithWhite:0.72 alpha:1.0];
    self.actionButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.actionButton.titleLabel.font = [UIFont boldSystemFontOfSize:18.0];
    [self.actionButton addTarget:self action:@selector(actionPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.statusLabel];
    [self.view addSubview:self.addressLabel];
    [self.view addSubview:self.codeLabel];
    [self.view addSubview:self.noteLabel];
    [self.view addSubview:self.actionButton];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateContent)
        name:RLVTransferServiceDidChangeNotification object:nil];
    [self updateContent];
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

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat contentWidth = width - 32.0;
    CGFloat top = 34.0;
    self.statusLabel.frame = CGRectMake(16.0, top, contentWidth, 28.0);
    self.addressLabel.frame = CGRectMake(16.0, top + 42.0, contentWidth, 24.0);
    self.codeLabel.frame = CGRectMake(16.0, top + 86.0, contentWidth, 58.0);
    self.noteLabel.frame = CGRectMake(24.0, top + 164.0, width - 48.0, 82.0);
    self.actionButton.frame = CGRectMake(40.0, top + 264.0, width - 80.0, 48.0);
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

@end
