#import "RLVSettingsViewController.h"

NSString * const RLVLibraryPreservesThumbnailAspectRatioDefaultsKey =
    @"RLVLibraryPreservesThumbnailAspectRatio";
NSString * const RLVLibraryAutomaticallyPlaysLivePhotosDefaultsKey =
    @"RLVLibraryAutomaticallyPlaysLivePhotos";

BOOL RLVLibraryPreservesThumbnailAspectRatio(void)
{
    return [[NSUserDefaults standardUserDefaults]
        boolForKey:RLVLibraryPreservesThumbnailAspectRatioDefaultsKey];
}

BOOL RLVLibraryAutomaticallyPlaysLivePhotos(void)
{
    return [[NSUserDefaults standardUserDefaults]
        boolForKey:RLVLibraryAutomaticallyPlaysLivePhotosDefaultsKey];
}

typedef NS_ENUM(NSInteger, RLVSettingsSection) {
    RLVSettingsSectionLibrary = 0,
    RLVSettingsSectionLivePhotos,
    RLVSettingsSectionAbout,
    RLVSettingsSectionCount
};

typedef NS_ENUM(NSInteger, RLVAboutRow) {
    RLVAboutRowChanges = 0,
    RLVAboutRowPrivacy,
    RLVAboutRowCount
};

@interface RLVSettingsViewController ()
- (UITableViewCell *)switchCellWithTitle:(NSString *)title enabled:(BOOL)enabled
    action:(SEL)action reuseIdentifier:(NSString *)reuseIdentifier;
- (void)showInformationWithTitle:(NSString *)title message:(NSString *)message;
@end

@implementation RLVSettingsViewController

- (id)init
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) self.title = NSLocalizedString(@"settings.title", nil);
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    UIColor *backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    self.tableView.backgroundColor = backgroundColor;
    // UITableViewStyleGrouped installs a textured background view on iOS 6,
    // which otherwise covers backgroundColor and breaks the dark app theme.
    UIView *backgroundView = [[UIView alloc] initWithFrame:self.tableView.bounds];
    backgroundView.backgroundColor = backgroundColor;
    self.tableView.backgroundView = backgroundView;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    (void)tableView;
    return RLVSettingsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    (void)tableView;
    return section == RLVSettingsSectionAbout ? RLVAboutRowCount : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    (void)tableView;
    if (section == RLVSettingsSectionLibrary) return NSLocalizedString(@"settings.section.library", nil);
    if (section == RLVSettingsSectionLivePhotos) return NSLocalizedString(@"settings.section.live", nil);
    return NSLocalizedString(@"settings.section.about", nil);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    (void)tableView;
    if (section == RLVSettingsSectionLibrary) {
        return NSLocalizedString(@"settings.library.original_ratio.footer", nil);
    }
    if (section == RLVSettingsSectionLivePhotos) {
        return NSLocalizedString(@"settings.live.autoplay.footer", nil);
    }
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"—";
    NSString *build = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey] ?: @"—";
    return [NSString stringWithFormat:NSLocalizedString(@"settings.about.version", nil), version, build];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == RLVSettingsSectionLibrary) {
        return [self switchCellWithTitle:NSLocalizedString(@"settings.library.original_ratio", nil)
            enabled:RLVLibraryPreservesThumbnailAspectRatio() action:@selector(originalRatioChanged:)
            reuseIdentifier:@"OriginalRatioCell"];
    }
    if (indexPath.section == RLVSettingsSectionLivePhotos) {
        return [self switchCellWithTitle:NSLocalizedString(@"settings.live.autoplay", nil)
            enabled:RLVLibraryAutomaticallyPlaysLivePhotos() action:@selector(automaticPlaybackChanged:)
            reuseIdentifier:@"AutomaticPlaybackCell"];
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AboutCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"AboutCell"];
    cell.textLabel.text = indexPath.row == RLVAboutRowChanges
        ? NSLocalizedString(@"settings.about.changes", nil)
        : NSLocalizedString(@"settings.about.privacy", nil);
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)switchCellWithTitle:(NSString *)title enabled:(BOOL)enabled
    action:(SEL)action reuseIdentifier:(NSString *)reuseIdentifier
{
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
            reuseIdentifier:reuseIdentifier];
        UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
        [toggle addTarget:self action:action forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = title;
    UISwitch *toggle = (UISwitch *)cell.accessoryView;
    toggle.on = enabled;
    toggle.accessibilityLabel = title;
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
    forRowAtIndexPath:(NSIndexPath *)indexPath
{
    (void)tableView;
    (void)indexPath;
    // UITableView owns the grouped-cell outline. Changing state here keeps
    // iOS 6's native rounded groups instead of replacing the background view.
    cell.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.textLabel.backgroundColor = [UIColor clearColor];
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view
    forSection:(NSInteger)section
{
    (void)tableView;
    (void)section;
    if (![view isKindOfClass:[UITableViewHeaderFooterView class]]) return;
    UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
    header.textLabel.textColor = [UIColor colorWithWhite:0.78 alpha:1.0];
    header.textLabel.shadowColor = [UIColor clearColor];
    header.textLabel.shadowOffset = CGSizeZero;
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view
    forSection:(NSInteger)section
{
    (void)tableView;
    if (![view isKindOfClass:[UITableViewHeaderFooterView class]]) return;
    UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *)view;
    footer.textLabel.textColor = [UIColor colorWithWhite:0.68 alpha:1.0];
    footer.textLabel.shadowColor = [UIColor clearColor];
    footer.textLabel.shadowOffset = CGSizeZero;
    footer.textLabel.textAlignment = section == RLVSettingsSectionAbout
        ? NSTextAlignmentCenter : NSTextAlignmentLeft;
}

- (void)originalRatioChanged:(UISwitch *)sender
{
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn
        forKey:RLVLibraryPreservesThumbnailAspectRatioDefaultsKey];
}

- (void)automaticPlaybackChanged:(UISwitch *)sender
{
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn
        forKey:RLVLibraryAutomaticallyPlaysLivePhotosDefaultsKey];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != RLVSettingsSectionAbout) return;
    if (indexPath.row == RLVAboutRowChanges) {
        [self showInformationWithTitle:NSLocalizedString(@"settings.about.changes", nil)
            message:NSLocalizedString(@"settings.about.changes.detail", nil)];
    } else {
        [self showInformationWithTitle:NSLocalizedString(@"settings.about.privacy", nil)
            message:NSLocalizedString(@"settings.about.privacy.detail", nil)];
    }
}

- (void)showInformationWithTitle:(NSString *)title message:(NSString *)message
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:message delegate:nil
        cancelButtonTitle:NSLocalizedString(@"common.ok", nil) otherButtonTitles:nil];
    [alert show];
}

@end
