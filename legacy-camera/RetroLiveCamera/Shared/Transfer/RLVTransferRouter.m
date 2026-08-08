#import "RLVTransferRouter.h"
#import "RLVAsset.h"
#import "RLVAssetStore.h"
#import "RLVHTTPResponse.h"

@interface RLVTransferRouter ()
@property (nonatomic, strong) RLVAssetStore *assetStore;
@property (nonatomic, copy) NSDictionary *deviceInfo;
@property (nonatomic, copy, readwrite) NSString *pairingCode;
@property (nonatomic, copy) NSString *sessionToken;
@property (nonatomic, strong) NSDate *sessionExpiration;
@property (nonatomic, assign) NSUInteger failedPairingAttempts;
@property (nonatomic, strong) NSDate *pairingLockoutUntil;
@end

@implementation RLVTransferRouter

- (id)initWithAssetStore:(RLVAssetStore *)assetStore deviceInfo:(NSDictionary *)deviceInfo pairingCode:(NSString *)pairingCode
{
    self = [super init];
    if (self) {
        _assetStore = assetStore;
        _deviceInfo = [deviceInfo copy];
        _pairingCode = [pairingCode copy];
    }
    return self;
}

- (RLVHTTPResponse *)responseForMethod:(NSString *)method path:(NSString *)path headers:(NSDictionary *)headers body:(NSData *)body
{
    NSRange queryMark = [path rangeOfString:@"?"];
    NSString *route = queryMark.location == NSNotFound ? path : [path substringToIndex:queryMark.location];
    NSString *query = queryMark.location == NSNotFound ? nil : [path substringFromIndex:queryMark.location + 1];
    route = [route stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    if ([method isEqualToString:@"GET"] && [route isEqualToString:@"/api/v1/health"]) {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfFileSystemForPath:[self.assetStore.rootURL path] error:NULL];
        return [RLVHTTPResponse JSONResponseWithStatusCode:200 object:[NSDictionary dictionaryWithObjectsAndKeys:
            @"ok", @"status", [self ISO8601StringForDate:[NSDate date]], @"serverTime",
            [attributes objectForKey:NSFileSystemFreeSize] ?: [NSNumber numberWithUnsignedLongLong:0], @"freeDiskBytes", nil]];
    }
    if ([method isEqualToString:@"POST"] && [route isEqualToString:@"/api/v1/session"]) {
        return [self pairingResponseForBody:body];
    }
    if (![self isAuthorizedWithHeaders:headers]) {
        return [self errorResponseWithStatus:401 message:@"Missing, expired, or invalid bearer token."];
    }
    if ([method isEqualToString:@"GET"] && [route isEqualToString:@"/api/v1/device"]) {
        NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:self.deviceInfo];
        [info setObject:[NSNumber numberWithUnsignedInteger:[[self.assetStore loadAssets:NULL] count]] forKey:@"assetCount"];
        return [RLVHTTPResponse JSONResponseWithStatusCode:200 object:info];
    }
    if ([method isEqualToString:@"GET"] && [route isEqualToString:@"/api/v1/assets"]) {
        return [self assetListResponseWithQuery:[self queryDictionary:query]];
    }
    if ([method isEqualToString:@"GET"] && [route hasPrefix:@"/api/v1/assets/"]) {
        return [self assetResponseForRoute:route headers:headers];
    }
    return [self errorResponseWithStatus:404 message:@"Route not found."];
}

- (RLVHTTPResponse *)pairingResponseForBody:(NSData *)body
{
    @synchronized(self) {
        if ([self.pairingLockoutUntil compare:[NSDate date]] == NSOrderedDescending) {
            return [self errorResponseWithStatus:429 message:@"Too many pairing attempts. Try again shortly."];
        }
    }
    NSDictionary *request = body ? [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL] : nil;
    NSString *code = [request isKindOfClass:[NSDictionary class]] ? [request objectForKey:@"pairingCode"] : nil;
    NSString *clientName = [request isKindOfClass:[NSDictionary class]] ? [request objectForKey:@"clientName"] : nil;
    if (![code isKindOfClass:[NSString class]] || ![code isEqualToString:self.pairingCode] ||
        ![clientName isKindOfClass:[NSString class]] || [clientName length] == 0 || [clientName length] > 100) {
        @synchronized(self) {
            self.failedPairingAttempts += 1;
            if (self.failedPairingAttempts >= 5) {
                self.failedPairingAttempts = 0;
                self.pairingLockoutUntil = [NSDate dateWithTimeIntervalSinceNow:30.0];
            }
        }
        return [self errorResponseWithStatus:401 message:@"Invalid pairing code or client name."];
    }
    @synchronized(self) {
        self.failedPairingAttempts = 0;
        self.pairingLockoutUntil = nil;
        self.sessionToken = [NSString stringWithFormat:@"%@%@", [[NSUUID UUID] UUIDString], [[NSUUID UUID] UUIDString]];
        self.sessionExpiration = [NSDate dateWithTimeIntervalSinceNow:900.0];
    }
    return [RLVHTTPResponse JSONResponseWithStatusCode:200 object:[NSDictionary dictionaryWithObjectsAndKeys:
        self.sessionToken, @"token", [NSNumber numberWithInteger:900], @"expiresInSeconds", nil]];
}

- (BOOL)isAuthorizedWithHeaders:(NSDictionary *)headers
{
    NSString *authorization = [headers objectForKey:@"authorization"];
    if (![authorization hasPrefix:@"Bearer "]) return NO;
    NSString *token = [authorization substringFromIndex:7];
    @synchronized(self) {
        return self.sessionToken != nil && [token isEqualToString:self.sessionToken] &&
            [self.sessionExpiration compare:[NSDate date]] == NSOrderedDescending;
    }
}

- (RLVHTTPResponse *)assetListResponseWithQuery:(NSDictionary *)query
{
    NSInteger limit = [query objectForKey:@"limit"] ? [[query objectForKey:@"limit"] integerValue] : 50;
    NSString *cursor = [query objectForKey:@"cursor"];
    if (limit < 1 || limit > 100) return [self errorResponseWithStatus:400 message:@"limit must be between 1 and 100."];
    NSArray *assets = [self.assetStore loadAssets:NULL] ?: [NSArray array];
    NSUInteger start = 0;
    if ([cursor length] > 0) {
        BOOL found = NO;
        for (NSUInteger index = 0; index < [assets count]; index++) {
            if ([[[assets objectAtIndex:index] assetId] isEqualToString:cursor]) {
                start = index + 1;
                found = YES;
                break;
            }
        }
        if (!found) return [self errorResponseWithStatus:400 message:@"cursor does not identify a committed asset."];
    }
    NSUInteger end = MIN([assets count], start + (NSUInteger)limit);
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger index = start; index < end; index++) {
        RLVAsset *asset = [assets objectAtIndex:index];
        NSData *manifestData = [NSData dataWithContentsOfURL:asset.manifestURL];
        NSDictionary *manifest = manifestData ? [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:NULL] : nil;
        NSString *base = [NSString stringWithFormat:@"/api/v1/assets/%@", asset.assetId];
        [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:asset.assetId, @"assetId",
            [manifest objectForKey:@"createdAt"] ?: [self ISO8601StringForDate:asset.createdAt], @"createdAt",
            [base stringByAppendingString:@"/thumbnail"], @"thumbnailURL",
            [base stringByAppendingString:@"/manifest"], @"manifestURL", nil]];
    }
    id nextCursor = end < [assets count] && end > 0 ? [[assets objectAtIndex:end - 1] assetId] : [NSNull null];
    return [RLVHTTPResponse JSONResponseWithStatusCode:200 object:[NSDictionary dictionaryWithObjectsAndKeys:items, @"items", nextCursor, @"nextCursor", nil]];
}

- (RLVHTTPResponse *)assetResponseForRoute:(NSString *)route headers:(NSDictionary *)headers
{
    NSArray *parts = [route componentsSeparatedByString:@"/"];
    if ([parts count] != 6) return [self errorResponseWithStatus:404 message:@"Asset route not found."];
    NSString *assetId = [parts objectAtIndex:4];
    NSString *resource = [parts objectAtIndex:5];
    if ([[NSUUID alloc] initWithUUIDString:assetId] == nil) {
        return [self errorResponseWithStatus:404 message:@"Asset not found."];
    }
    RLVAsset *asset = [self.assetStore loadAssetWithIdentifier:assetId error:NULL];
    if (!asset) return [self errorResponseWithStatus:404 message:@"Asset not found."];
    NSURL *fileURL = nil;
    NSString *contentType = @"application/octet-stream";
    BOOL supportsRange = NO;
    if ([resource isEqualToString:@"manifest"]) {
        fileURL = asset.manifestURL;
        contentType = @"application/json; charset=utf-8";
    } else if ([resource isEqualToString:@"photo"] || [resource isEqualToString:@"thumbnail"]) {
        fileURL = asset.photoURL;
        contentType = @"image/jpeg";
        supportsRange = YES;
    } else if ([resource isEqualToString:@"motion"]) {
        fileURL = asset.motionURL;
        contentType = @"video/quicktime";
        supportsRange = YES;
    }
    if (!fileURL || ![[NSFileManager defaultManager] fileExistsAtPath:[fileURL path]]) {
        return [self errorResponseWithStatus:404 message:@"Asset resource not found."];
    }
    unsigned long long size = [[[[NSFileManager defaultManager] attributesOfItemAtPath:[fileURL path] error:NULL] objectForKey:NSFileSize] unsignedLongLongValue];
    unsigned long long offset = 0;
    unsigned long long length = size;
    BOOL partial = NO;
    NSString *range = supportsRange ? [headers objectForKey:@"range"] : nil;
    if (range && ![self parseRange:range size:size offset:&offset length:&length]) {
        RLVHTTPResponse *response = [self errorResponseWithStatus:416 message:@"Requested range is not satisfiable."];
        response.headers = [NSDictionary dictionaryWithObjectsAndKeys:@"application/json; charset=utf-8", @"Content-Type",
            [NSString stringWithFormat:@"bytes */%llu", size], @"Content-Range", nil];
        return response;
    } else if (range) {
        partial = YES;
    }
    RLVHTTPResponse *response = [[RLVHTTPResponse alloc] init];
    response.statusCode = partial ? 206 : 200;
    NSMutableDictionary *responseHeaders = [NSMutableDictionary dictionaryWithObject:contentType forKey:@"Content-Type"];
    if (supportsRange) [responseHeaders setObject:@"bytes" forKey:@"Accept-Ranges"];
    if (partial) [responseHeaders setObject:[NSString stringWithFormat:@"bytes %llu-%llu/%llu", offset, offset + length - 1, size] forKey:@"Content-Range"];
    response.headers = responseHeaders;
    response.fileURL = fileURL;
    response.fileOffset = offset;
    response.fileLength = length;
    return response;
}

- (BOOL)parseRange:(NSString *)range size:(unsigned long long)size offset:(unsigned long long *)offset length:(unsigned long long *)length
{
    if (![range hasPrefix:@"bytes="] || [range rangeOfString:@","].location != NSNotFound || size == 0) return NO;
    NSArray *bounds = [[range substringFromIndex:6] componentsSeparatedByString:@"-"];
    if ([bounds count] != 2) return NO;
    NSString *first = [bounds objectAtIndex:0];
    NSString *second = [bounds objectAtIndex:1];
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    if (([first length] && [[first stringByTrimmingCharactersInSet:digits] length]) ||
        ([second length] && [[second stringByTrimmingCharactersInSet:digits] length])) return NO;
    if ([first length] == 0) {
        unsigned long long suffix = [second longLongValue];
        if (suffix == 0) return NO;
        *length = MIN(suffix, size);
        *offset = size - *length;
        return YES;
    }
    unsigned long long start = [first longLongValue];
    if (start >= size) return NO;
    unsigned long long end = [second length] ? [second longLongValue] : size - 1;
    if (end < start) return NO;
    end = MIN(end, size - 1);
    *offset = start;
    *length = end - start + 1;
    return YES;
}

- (NSDictionary *)queryDictionary:(NSString *)query
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *pair in [query componentsSeparatedByString:@"&"]) {
        NSRange equals = [pair rangeOfString:@"="];
        if (equals.location == NSNotFound) continue;
        NSString *key = [[pair substringToIndex:equals.location] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSString *value = [[pair substringFromIndex:equals.location + 1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        if (key && value) [result setObject:value forKey:key];
    }
    return result;
}

- (RLVHTTPResponse *)errorResponseWithStatus:(NSInteger)status message:(NSString *)message
{
    return [RLVHTTPResponse JSONResponseWithStatusCode:status object:[NSDictionary dictionaryWithObject:message forKey:@"error"]];
}

- (NSString *)ISO8601StringForDate:(NSDate *)date
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    return [formatter stringFromDate:date ?: [NSDate date]];
}

@synthesize assetStore = _assetStore;
@synthesize deviceInfo = _deviceInfo;
@synthesize pairingCode = _pairingCode;
@synthesize sessionToken = _sessionToken;
@synthesize sessionExpiration = _sessionExpiration;
@synthesize failedPairingAttempts = _failedPairingAttempts;
@synthesize pairingLockoutUntil = _pairingLockoutUntil;

@end
