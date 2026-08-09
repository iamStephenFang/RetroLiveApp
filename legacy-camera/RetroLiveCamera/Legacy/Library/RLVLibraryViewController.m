#import "RLVLibraryViewController.h"
#import "RLVAssetDetailViewController.h"
#import "RLVAssetStore.h"
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
        _imageView = [[UIImageView alloc] initWithFrame:self.contentView.bounds];
        _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        [self.contentView addSubview:_imageView];
    }
    return self;
}
- (void)prepareForReuse { [super prepareForReuse]; self.imageView.image = nil; }
@synthesize imageView = _imageView;
@end

@interface RLVLibraryViewController ()
@property (nonatomic, strong) NSArray *assets;
@end

@implementation RLVLibraryViewController

- (id)init
{
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 2.0;
    layout.minimumLineSpacing = 2.0;
    layout.sectionInset = UIEdgeInsetsMake(2, 2, 2, 2);
    return [super initWithCollectionViewLayout:layout];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"RetroLive";
    self.collectionView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    [self.collectionView registerClass:[RLVAssetCell class] forCellWithReuseIdentifier:@"AssetCell"];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"transfer.title", nil)
        style:UIBarButtonItemStylePlain target:self action:@selector(showTransfer:)];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadAssets)
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
    [self.navigationController setNavigationBarHidden:NO animated:YES];
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
    self.assets = [[RLVAssetStore sharedStore] loadAssets:NULL] ?: [NSArray array];
    [self.collectionView reloadData];
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
    cell.imageView.image = [self thumbnailAtURL:asset.photoURL maximumSize:240];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    (void)collectionView;
    RLVAssetDetailViewController *detail = [[RLVAssetDetailViewController alloc] initWithAsset:[self.assets objectAtIndex:indexPath.item]];
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

@end
