#import "RLVLibraryViewController.h"
#import "RLVAssetDetailViewController.h"
#import "RLVAssetStore.h"
#import "RLVLayout.h"
#import "RLVTransferViewController.h"
#import <ImageIO/ImageIO.h>

@interface RLVAssetCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *imageView;
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
    }
    return self;
}
- (void)prepareForReuse { [super prepareForReuse]; self.imageView.image = nil; }
@synthesize imageView = _imageView;
@end

@interface RLVLibraryViewController ()
@property (nonatomic, strong) NSArray *assets;
@property (nonatomic, strong) NSCache *thumbnailCache;
@property (nonatomic, strong) NSOperationQueue *thumbnailQueue;
@property (nonatomic, assign) NSUInteger reloadGeneration;
@property (nonatomic, copy) RLVLibrarySelectionHandler selectionHandler;
@end

@implementation RLVLibraryViewController

- (id)init
{
    return [self initWithSelectionHandler:nil];
}

- (id)initWithSelectionHandler:(RLVLibrarySelectionHandler)selectionHandler
{
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 2.0;
    layout.minimumLineSpacing = 2.0;
    layout.sectionInset = UIEdgeInsetsMake(2, 2, 2, 2);
    self = [super initWithCollectionViewLayout:layout];
    if (self) {
        _selectionHandler = [selectionHandler copy];
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
        initWithImage:[UIImage imageNamed:@"InterfaceIcons/RLVTransfer"]
        style:UIBarButtonItemStylePlain target:self action:@selector(showTransfer:)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = NSLocalizedString(@"transfer.title", nil);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(assetStoreDidChange:)
                                                 name:RLVAssetStoreDidChangeNotification object:nil];
}

- (void)showTransfer:(id)sender
{
    (void)sender;
    [self.navigationController pushViewController:[[RLVTransferViewController alloc] init] animated:YES];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (self.navigationController.navigationBarHidden) {
        [self.navigationController setNavigationBarHidden:NO animated:animated];
    }
    [self reloadAssets];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.collectionView.bounds);
    CGFloat item = floor((width - 8.0) / 3.0);
    ((UICollectionViewFlowLayout *)self.collectionViewLayout).itemSize = CGSizeMake(item, item);
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
    (void)collectionView;
    if (self.selectionHandler) {
        self.selectionHandler(self.assets, indexPath.item);
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    RLVAssetDetailViewController *detail = [[RLVAssetDetailViewController alloc]
        initWithAssets:self.assets selectedIndex:indexPath.item];
    [self.navigationController pushViewController:detail animated:YES];
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
@synthesize thumbnailCache = _thumbnailCache;
@synthesize thumbnailQueue = _thumbnailQueue;
@synthesize reloadGeneration = _reloadGeneration;
@synthesize selectionHandler = _selectionHandler;

@end
