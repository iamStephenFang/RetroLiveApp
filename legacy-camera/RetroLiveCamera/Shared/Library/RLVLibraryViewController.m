#import "RLVLibraryViewController.h"
#import "RLVAssetStore.h"
#import "RLVLayout.h"
#import "RLVSettingsViewController.h"
#import <ImageIO/ImageIO.h>

@interface RLVAssetCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *selectionIndicator;
@end

@implementation RLVAssetCell
- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        [self.contentView addSubview:_imageView];
        RLVPinViewToEdges(_imageView, self.contentView);

        _selectionIndicator = [[UILabel alloc] initWithFrame:CGRectZero];
        _selectionIndicator.backgroundColor = [UIColor colorWithRed:0.08 green:0.48 blue:0.96 alpha:1.0];
        _selectionIndicator.text = @"\u2713";
        _selectionIndicator.textColor = [UIColor whiteColor];
        _selectionIndicator.textAlignment = NSTextAlignmentCenter;
        _selectionIndicator.font = [UIFont boldSystemFontOfSize:16.0];
        _selectionIndicator.layer.cornerRadius = 12.0;
        _selectionIndicator.layer.borderWidth = 1.5;
        _selectionIndicator.layer.borderColor = [UIColor whiteColor].CGColor;
        _selectionIndicator.clipsToBounds = YES;
        _selectionIndicator.hidden = YES;
        [self.contentView addSubview:_selectionIndicator];
        RLVPrepareViewsForAutoLayout(@[_selectionIndicator]);
        RLVAddVisualConstraints(self.contentView, @{ @"selection": _selectionIndicator },
            @[@"H:[selection(24)]-6-|", @"V:|-6-[selection(24)]"]);
    }
    return self;
}
- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    self.selectionIndicator.hidden = !selected;
}
- (void)prepareForReuse
{
    [super prepareForReuse];
    self.imageView.image = nil;
    self.selectionIndicator.hidden = !self.selected;
}
@synthesize imageView = _imageView;
@synthesize selectionIndicator = _selectionIndicator;
@end

@interface RLVLibraryViewController () <UIAlertViewDelegate>
@property (nonatomic, strong) UICollectionViewFlowLayout *flowLayout;
@property (nonatomic, strong) NSArray *assets;
@property (nonatomic, strong) NSCache *thumbnailCache;
@property (nonatomic, strong) NSOperationQueue *thumbnailQueue;
@property (nonatomic, assign) NSUInteger reloadGeneration;
@property (nonatomic, assign, getter=isSelectingAssets) BOOL selectingAssets;
@property (nonatomic, strong) UIBarButtonItem *shareButton;
@property (nonatomic, strong) UIBarButtonItem *deleteButton;
@property (nonatomic, strong) UIToolbar *selectionToolbar;
@property (nonatomic, assign) UIEdgeInsets normalContentInset;
@end

static NSInteger const RLVBatchDeleteConfirmationAlertTag = 920;

@implementation RLVLibraryViewController

- (id)init
{
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 2.0;
    layout.minimumLineSpacing = 2.0;
    layout.sectionInset = UIEdgeInsetsMake(2, 2, 2, 2);
    self = [super initWithCollectionViewLayout:layout];
    if (self) {
        _flowLayout = layout;
        self.title = NSLocalizedString(@"library.title", nil);
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.title = NSLocalizedString(@"library.title", nil);
    self.thumbnailCache = [[NSCache alloc] init];
    self.thumbnailCache.countLimit = 60;
    self.thumbnailCache.totalCostLimit = 8 * 1024 * 1024;
    self.thumbnailQueue = [[NSOperationQueue alloc] init];
    self.thumbnailQueue.maxConcurrentOperationCount = 2;
    self.collectionView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    [self.collectionView registerClass:[RLVAssetCell class] forCellWithReuseIdentifier:@"AssetCell"];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:NSLocalizedString(@"library.select", nil) style:UIBarButtonItemStylePlain
        target:self action:@selector(toggleAssetSelection:)];
    self.shareButton = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareSelectedAssets:)];
    self.shareButton.accessibilityLabel = NSLocalizedString(@"asset.share", nil);
    self.deleteButton = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(confirmDeleteSelectedAssets:)];
    self.deleteButton.accessibilityLabel = NSLocalizedString(@"asset.delete", nil);
    UIBarButtonItem *space = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    self.selectionToolbar = [[UIToolbar alloc] initWithFrame:CGRectZero];
    self.selectionToolbar.barStyle = UIBarStyleBlack;
    if ([self.selectionToolbar respondsToSelector:@selector(setTranslucent:)]) {
        self.selectionToolbar.translucent = [self.selectionToolbar respondsToSelector:@selector(setBarTintColor:)];
    }
    self.selectionToolbar.items = @[self.shareButton, space, self.deleteButton];
    self.selectionToolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    self.selectionToolbar.hidden = YES;
    UIView *toolbarContainer = self.tabBarController.view ?: self.navigationController.view;
    [toolbarContainer addSubview:self.selectionToolbar];
    [self updateSelectionActions];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(assetStoreDidChange:)
                                                 name:RLVAssetStoreDidChangeNotification object:nil];
}

- (void)toggleAssetSelection:(id)sender
{
    (void)sender;
    if (!self.isSelectingAssets) self.normalContentInset = self.collectionView.contentInset;
    self.selectingAssets = !self.isSelectingAssets;
    self.collectionView.allowsMultipleSelection = self.isSelectingAssets;
    self.navigationItem.rightBarButtonItem.title = self.isSelectingAssets
        ? NSLocalizedString(@"common.cancel", nil) : NSLocalizedString(@"library.select", nil);
    if (!self.isSelectingAssets) {
        for (NSIndexPath *indexPath in [self.collectionView indexPathsForSelectedItems]) {
            [self.collectionView deselectItemAtIndexPath:indexPath animated:NO];
        }
    }
    [self.delegate libraryViewController:self didChangeSelectingAssets:self.isSelectingAssets];
    [self updateSelectionToolbarAnimated:YES];
    [self updateSelectionActions];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (self.navigationController.navigationBarHidden) {
        [self.navigationController setNavigationBarHidden:NO animated:animated];
    }
    if (!self.isSelectingAssets) self.normalContentInset = self.collectionView.contentInset;
    [self updateSelectionToolbarAnimated:NO];
    [self reloadAssets];
}

- (void)updateSelectionToolbarAnimated:(BOOL)animated
{
    UIView *toolbarContainer = self.tabBarController.view ?: self.navigationController.view;
    if (self.selectionToolbar.superview != toolbarContainer) {
        [self.selectionToolbar removeFromSuperview];
        [toolbarContainer addSubview:self.selectionToolbar];
    }
    CGFloat height = CGRectGetHeight(self.tabBarController.tabBar.frame);
    if (height <= 0.0) height = 49.0;
    CGRect bounds = toolbarContainer.bounds;
    self.selectionToolbar.frame = CGRectMake(CGRectGetMinX(bounds), CGRectGetMaxY(bounds) - height,
        CGRectGetWidth(bounds), height);
    [toolbarContainer bringSubviewToFront:self.selectionToolbar];
    UIEdgeInsets contentInset = self.normalContentInset;
    if (self.isSelectingAssets) contentInset.bottom = height;
    if (!UIEdgeInsetsEqualToEdgeInsets(self.collectionView.contentInset, contentInset)) {
        self.collectionView.contentInset = contentInset;
        self.collectionView.scrollIndicatorInsets = contentInset;
    }

    if (self.isSelectingAssets) {
        self.selectionToolbar.hidden = NO;
        if (!animated) {
            self.selectionToolbar.alpha = 1.0;
            return;
        }
        self.selectionToolbar.alpha = 0.0;
        [UIView animateWithDuration:0.2 animations:^{ self.selectionToolbar.alpha = 1.0; }];
    } else if (animated && !self.selectionToolbar.hidden) {
        [UIView animateWithDuration:0.2 animations:^{ self.selectionToolbar.alpha = 0.0; }
            completion:^(BOOL finished) {
                if (finished) self.selectionToolbar.hidden = YES;
            }];
    } else {
        self.selectionToolbar.alpha = 0.0;
        self.selectionToolbar.hidden = YES;
    }
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.collectionView.bounds);
    CGFloat item = floor((width - 8.0) / 3.0);
    self.flowLayout.itemSize = CGSizeMake(item, item);
    if (self.isSelectingAssets) [self updateSelectionToolbarAnimated:NO];
}

- (void)reloadAssets
{
    NSUInteger generation = ++self.reloadGeneration;
    __weak RLVLibraryViewController *controller = self;
    [[RLVAssetStore sharedStore] loadAssetsWithCompletion:^(NSArray *assets, NSError *error) {
        (void)error;
        if (!controller || generation != controller.reloadGeneration) return;
        controller.assets = assets ?: [NSArray array];
        [controller.collectionView reloadData];
        controller.navigationItem.rightBarButtonItem.enabled = [controller.assets count] > 0;
        [controller updateSelectionActions];
    }];
}

- (void)assetStoreDidChange:(NSNotification *)notification
{
    (void)notification;
    [self reloadAssets];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    (void)collectionView; (void)section;
    return [self.assets count];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    RLVAssetCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"AssetCell" forIndexPath:indexPath];
    RLVAsset *asset = [self.assets objectAtIndex:indexPath.item];
    BOOL preservesAspectRatio = RLVLibraryPreservesThumbnailAspectRatio();
    cell.imageView.contentMode = preservesAspectRatio ? UIViewContentModeScaleAspectFit : UIViewContentModeScaleAspectFill;
    cell.imageView.backgroundColor = preservesAspectRatio ? [UIColor blackColor] : [UIColor clearColor];
    UIImage *cachedImage = [self.thumbnailCache objectForKey:asset.assetId];
    cell.imageView.image = cachedImage;
    if (!cachedImage) {
        NSString *assetId = [asset.assetId copy];
        NSURL *photoURL = asset.photoURL;
        __weak RLVLibraryViewController *controller = self;
        [self.thumbnailQueue addOperationWithBlock:^{
            UIImage *image = [controller thumbnailAtURL:photoURL maximumSize:240];
            if (image) {
                CGImageRef imageRef = image.CGImage;
                NSUInteger cost = imageRef ? CGImageGetBytesPerRow(imageRef) * CGImageGetHeight(imageRef) : 0;
                [controller.thumbnailCache setObject:image forKey:assetId cost:cost];
            }
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if (!controller || indexPath.item >= [controller.assets count]) return;
                RLVAsset *currentAsset = [controller.assets objectAtIndex:indexPath.item];
                if (![currentAsset.assetId isEqualToString:assetId]) return;
                RLVAssetCell *visibleCell = (RLVAssetCell *)[controller.collectionView cellForItemAtIndexPath:indexPath];
                visibleCell.imageView.image = image;
            }];
        }];
    }
    return cell;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    [self.thumbnailQueue cancelAllOperations];
    [self.thumbnailCache removeAllObjects];
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.isSelectingAssets) {
        [self updateSelectionActions];
        return;
    }
    [collectionView deselectItemAtIndexPath:indexPath animated:NO];
    [self.delegate libraryViewController:self didSelectAssets:self.assets selectedIndex:indexPath.item];
}

- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath
{
    (void)collectionView;
    (void)indexPath;
    if (self.isSelectingAssets) [self updateSelectionActions];
}

- (NSArray *)selectedAssets
{
    NSArray *indexPaths = [[self.collectionView indexPathsForSelectedItems]
        sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *selectedAssets = [NSMutableArray arrayWithCapacity:[indexPaths count]];
    for (NSIndexPath *indexPath in indexPaths) {
        if (indexPath.item < [self.assets count]) [selectedAssets addObject:[self.assets objectAtIndex:indexPath.item]];
    }
    return selectedAssets;
}

- (void)updateSelectionActions
{
    NSUInteger count = [[self selectedAssets] count];
    self.shareButton.enabled = count > 0;
    self.deleteButton.enabled = count > 0;
    self.title = self.isSelectingAssets
        ? [NSString stringWithFormat:NSLocalizedString(@"library.selected_count", nil), (unsigned long)count]
        : NSLocalizedString(@"library.title", nil);
}

- (void)shareSelectedAssets:(id)sender
{
    (void)sender;
    NSMutableArray *items = [NSMutableArray array];
    for (RLVAsset *asset in [self selectedAssets]) {
        if (asset.photoURL) [items addObject:asset.photoURL];
    }
    if ([items count] == 0) return;
    UIActivityViewController *activity = [[UIActivityViewController alloc]
        initWithActivityItems:items applicationActivities:nil];
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)confirmDeleteSelectedAssets:(id)sender
{
    (void)sender;
    NSUInteger count = [[self selectedAssets] count];
    if (count == 0) return;
    UIAlertView *alert = [[UIAlertView alloc]
        initWithTitle:NSLocalizedString(@"library.delete.title", nil)
        message:[NSString stringWithFormat:NSLocalizedString(@"library.delete.message", nil), (unsigned long)count]
        delegate:self cancelButtonTitle:NSLocalizedString(@"common.cancel", nil)
        otherButtonTitles:NSLocalizedString(@"asset.delete", nil), nil];
    alert.tag = RLVBatchDeleteConfirmationAlertTag;
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (alertView.tag != RLVBatchDeleteConfirmationAlertTag || buttonIndex == alertView.cancelButtonIndex) return;
    NSError *firstError = nil;
    for (RLVAsset *asset in [self selectedAssets]) {
        NSError *error = nil;
        if (![[RLVAssetStore sharedStore] deleteAsset:asset error:&error] && !firstError) firstError = error;
    }
    [self toggleAssetSelection:nil];
    [self reloadAssets];
    if (firstError) {
        UIAlertView *failure = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"asset.delete.failed", nil)
            message:[firstError localizedDescription] delegate:nil cancelButtonTitle:NSLocalizedString(@"common.ok", nil)
            otherButtonTitles:nil];
        [failure show];
    }
}

- (UIImage *)thumbnailAtURL:(NSURL *)url maximumSize:(CGFloat)size
{
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return nil;
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
        (id)kCFBooleanTrue, (id)kCGImageSourceCreateThumbnailFromImageAlways,
        [NSNumber numberWithFloat:size], (id)kCGImageSourceThumbnailMaxPixelSize,
        (id)kCFBooleanTrue, (id)kCGImageSourceCreateThumbnailWithTransform, nil];
    CGImageRef imageRef = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    UIImage *image = imageRef ? [UIImage imageWithCGImage:imageRef] : nil;
    if (imageRef) CGImageRelease(imageRef);
    CFRelease(source);
    return image;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@synthesize assets = _assets;
@synthesize flowLayout = _flowLayout;
@synthesize thumbnailCache = _thumbnailCache;
@synthesize thumbnailQueue = _thumbnailQueue;
@synthesize reloadGeneration = _reloadGeneration;
@synthesize selectingAssets = _selectingAssets;
@synthesize shareButton = _shareButton;
@synthesize deleteButton = _deleteButton;
@synthesize selectionToolbar = _selectionToolbar;
@synthesize normalContentInset = _normalContentInset;
@synthesize delegate = _delegate;

@end
