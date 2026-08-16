#import "RLVTransferService.h"
#import "RLVAssetStore.h"
#import "RLVDeviceCapabilities.h"
#import "RLVHTTPResponse.h"
#import "RLVTransferRouter.h"
#import <UIKit/UIKit.h>
#import <arpa/inet.h>
#import <errno.h>
#import <fcntl.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <unistd.h>

NSString * const RLVTransferServiceDidChangeNotification = @"RLVTransferServiceDidChangeNotification";
static NSString * const RLVTransferServiceErrorDomain = @"com.retrolive.transfer-service";
static const NSUInteger RLVMaximumRequestBodyLength = 65536;

static BOOL RLVContentLengthFromHeaders(NSDictionary *headers, NSUInteger *result)
{
    NSString *value = [headers objectForKey:@"content-length"];
    if (value == nil) {
        if (result) *result = 0;
        return YES;
    }
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) return NO;
    NSUInteger parsed = 0;
    for (NSUInteger index = 0; index < [value length]; index++) {
        unichar character = [value characterAtIndex:index];
        if (character < '0' || character > '9') return NO;
        NSUInteger digit = (NSUInteger)(character - '0');
        if (parsed > (RLVMaximumRequestBodyLength - digit) / 10) return NO;
        parsed = parsed * 10 + digit;
    }
    if (parsed > RLVMaximumRequestBodyLength) return NO;
    if (result) *result = parsed;
    return YES;
}

@interface RLVTransferService () {
    int _listenSocket;
    dispatch_source_t _acceptSource;
    dispatch_queue_t _acceptQueue;
}
@property (nonatomic, assign, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, assign, readwrite) NSUInteger port;
@property (nonatomic, copy, readwrite) NSString *pairingCode;
@property (nonatomic, copy, readwrite) NSString *localAddress;
@property (nonatomic, copy, readwrite) NSString *pairedClientName;
@property (nonatomic, strong) NSNetService *netService;
@property (nonatomic, strong) RLVTransferRouter *router;
@end

@implementation RLVTransferService

+ (RLVTransferService *)sharedService
{
    static RLVTransferService *service = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ service = [[RLVTransferService alloc] init]; });
    return service;
}

- (id)init
{
    self = [super init];
    if (self) {
        _listenSocket = -1;
        _acceptQueue = dispatch_queue_create("com.retrolive.transfer.accept", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)start:(NSError **)error
{
    if (self.running) return YES;
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    if (listener < 0) return [self failWithCode:1 description:NSLocalizedString(@"transfer.error.socket", nil) error:error];
    int enabled = 1;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &enabled, sizeof(enabled));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = htons(8080);
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) != 0) {
        address.sin_port = 0;
        if (bind(listener, (struct sockaddr *)&address, sizeof(address)) != 0) {
            close(listener);
            return [self failWithCode:2 description:NSLocalizedString(@"transfer.error.bind", nil) error:error];
        }
    }
    if (listen(listener, 8) != 0) {
        close(listener);
        return [self failWithCode:3 description:NSLocalizedString(@"transfer.error.listen", nil) error:error];
    }
    fcntl(listener, F_SETFL, fcntl(listener, F_GETFL, 0) | O_NONBLOCK);
    socklen_t addressLength = sizeof(address);
    getsockname(listener, (struct sockaddr *)&address, &addressLength);
    self.port = ntohs(address.sin_port);
    self.pairingCode = [NSString stringWithFormat:@"%06u", arc4random_uniform(1000000)];
    self.localAddress = [self currentWiFiAddress] ?: @"0.0.0.0";
    NSDictionary *deviceInfo = [self deviceInfo];
    self.router = [[RLVTransferRouter alloc] initWithAssetStore:[RLVAssetStore sharedStore]
                                                    deviceInfo:deviceInfo
                                                   pairingCode:self.pairingCode];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(routerDidPair:)
        name:RLVTransferRouterDidPairNotification object:self.router];
    _listenSocket = listener;
    __unsafe_unretained RLVTransferService *service = self;
    _acceptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)listener, 0, _acceptQueue);
    dispatch_source_set_event_handler(_acceptSource, ^{ [service acceptPendingConnections]; });
    dispatch_resume(_acceptSource);
    NSString *deviceId = [deviceInfo objectForKey:@"deviceId"];
    NSString *suffix = [deviceId length] >= 4 ? [deviceId substringFromIndex:[deviceId length] - 4] : @"Camera";
    NSString *serviceName = [@"RetroLive-" stringByAppendingString:suffix];
    self.netService = [[NSNetService alloc] initWithDomain:@"local." type:@"_retrolive._tcp." name:serviceName port:(int)self.port];
    [self.netService publish];
    self.running = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:RLVTransferServiceDidChangeNotification object:self];
    return YES;
}

- (void)stop
{
    if (!self.running) return;
    [self.netService stop];
    self.netService = nil;
    if (_acceptSource) {
        dispatch_source_cancel(_acceptSource);
        _acceptSource = nil;
    }
    if (_listenSocket >= 0) {
        close(_listenSocket);
        _listenSocket = -1;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self name:RLVTransferRouterDidPairNotification object:self.router];
    self.router = nil;
    self.pairingCode = nil;
    self.localAddress = nil;
    self.pairedClientName = nil;
    self.port = 0;
    self.running = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:RLVTransferServiceDidChangeNotification object:self];
}

- (void)routerDidPair:(NSNotification *)notification
{
    NSString *clientName = [[notification userInfo] objectForKey:RLVTransferRouterPairedClientNameKey];
    if (![clientName isKindOfClass:[NSString class]] || [clientName length] == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.running || [notification object] != self.router) return;
        self.pairedClientName = clientName;
        [[NSNotificationCenter defaultCenter] postNotificationName:RLVTransferServiceDidChangeNotification object:self];
    });
}

- (void)acceptPendingConnections
{
    while (_listenSocket >= 0) {
        int client = accept(_listenSocket, NULL, NULL);
        if (client < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) return;
            return;
        }
        fcntl(client, F_SETFL, fcntl(client, F_GETFL, 0) & ~O_NONBLOCK);
        int noSigPipe = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
        struct timeval timeout;
        timeout.tv_sec = 10;
        timeout.tv_usec = 0;
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
        RLVTransferRouter *router = self.router;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self handleClientSocket:client router:router];
        });
    }
}

- (void)handleClientSocket:(int)client router:(RLVTransferRouter *)router
{
    @autoreleasepool {
        NSMutableData *requestData = [NSMutableData data];
        NSRange headerRange = NSMakeRange(NSNotFound, 0);
        NSUInteger expectedLength = NSNotFound;
        unsigned char buffer[4096];
        while ([requestData length] < 131072) {
            ssize_t count = recv(client, buffer, sizeof(buffer), 0);
            if (count <= 0) break;
            [requestData appendBytes:buffer length:(NSUInteger)count];
            if (headerRange.location == NSNotFound) {
                NSData *marker = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
                headerRange = [requestData rangeOfData:marker options:0 range:NSMakeRange(0, [requestData length])];
                if (headerRange.location != NSNotFound) {
                    NSData *headData = [requestData subdataWithRange:NSMakeRange(0, headerRange.location)];
                    NSString *head = [[NSString alloc] initWithData:headData encoding:NSISOLatin1StringEncoding];
                    NSDictionary *headers = [self headersFromLines:[head componentsSeparatedByString:@"\r\n"]];
                    NSUInteger bodyLength = 0;
                    if (!RLVContentLengthFromHeaders(headers, &bodyLength)) {
                        expectedLength = [requestData length];
                    } else {
                        expectedLength = headerRange.location + 4 + bodyLength;
                    }
                }
            }
            if (expectedLength != NSNotFound && [requestData length] >= expectedLength) break;
        }
        RLVHTTPResponse *response = [self responseForRequestData:requestData router:router];
        [self writeResponse:response toSocket:client];
        close(client);
    }
}

- (RLVHTTPResponse *)responseForRequestData:(NSData *)data router:(RLVTransferRouter *)router
{
    NSData *marker = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    NSRange split = [data rangeOfData:marker options:0 range:NSMakeRange(0, [data length])];
    if (split.location == NSNotFound || split.location > 65536) {
        return [RLVHTTPResponse JSONResponseWithStatusCode:400 object:[NSDictionary dictionaryWithObject:@"Malformed request." forKey:@"error"]];
    }
    NSString *head = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, split.location)] encoding:NSISOLatin1StringEncoding];
    NSArray *lines = [head componentsSeparatedByString:@"\r\n"];
    NSArray *requestLine = [[lines count] ? [lines objectAtIndex:0] : @"" componentsSeparatedByString:@" "];
    if ([requestLine count] != 3) {
        return [RLVHTTPResponse JSONResponseWithStatusCode:400 object:[NSDictionary dictionaryWithObject:@"Malformed request line." forKey:@"error"]];
    }
    NSString *method = [requestLine objectAtIndex:0];
    NSString *path = [requestLine objectAtIndex:1];
    NSDictionary *headers = [self headersFromLines:lines];
    NSUInteger bodyStart = split.location + split.length;
    NSUInteger declaredLength = 0;
    if (!RLVContentLengthFromHeaders(headers, &declaredLength)) {
        return [RLVHTTPResponse JSONResponseWithStatusCode:400 object:[NSDictionary dictionaryWithObject:@"Invalid Content-Length." forKey:@"error"]];
    }
    if (declaredLength > [data length] - bodyStart) {
        return [RLVHTTPResponse JSONResponseWithStatusCode:400 object:[NSDictionary dictionaryWithObject:@"Incomplete request body." forKey:@"error"]];
    }
    NSData *body = declaredLength ? [data subdataWithRange:NSMakeRange(bodyStart, declaredLength)] : nil;
    return [router responseForMethod:method path:path headers:headers body:body];
}

- (NSDictionary *)headersFromLines:(NSArray *)lines
{
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    for (NSUInteger index = 1; index < [lines count]; index++) {
        NSString *line = [lines objectAtIndex:index];
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) continue;
        NSString *key = [[[line substringToIndex:colon.location] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *value = [[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([key isEqualToString:@"content-length"] && [headers objectForKey:key] != nil) {
            [headers setObject:@"" forKey:key];
        } else if (key && value) {
            [headers setObject:value forKey:key];
        }
    }
    return headers;
}

- (void)writeResponse:(RLVHTTPResponse *)response toSocket:(int)client
{
    int file = -1;
    if (response.fileURL) {
        file = open([[response.fileURL path] fileSystemRepresentation], O_RDONLY);
        struct stat fileStatus;
        BOOL invalidFile = file < 0 || fstat(file, &fileStatus) != 0 || !S_ISREG(fileStatus.st_mode) || fileStatus.st_size < 0 ||
            response.fileOffset > (unsigned long long)fileStatus.st_size ||
            response.fileLength > (unsigned long long)fileStatus.st_size - response.fileOffset;
        if (invalidFile) {
            if (file >= 0) close(file);
            file = -1;
            response = [RLVHTTPResponse JSONResponseWithStatusCode:404 object:
                [NSDictionary dictionaryWithObject:@"Asset resource is no longer available." forKey:@"error"]];
        }
    }
    unsigned long long length = response.fileURL ? response.fileLength : [response.body length];
    NSMutableString *head = [NSMutableString stringWithFormat:@"HTTP/1.1 %ld %@\r\n", (long)response.statusCode, [self reasonForStatus:response.statusCode]];
    for (NSString *key in response.headers) [head appendFormat:@"%@: %@\r\n", key, [response.headers objectForKey:key]];
    [head appendFormat:@"Content-Length: %llu\r\nConnection: close\r\n\r\n", length];
    if (![self sendData:[head dataUsingEncoding:NSISOLatin1StringEncoding] socket:client]) {
        if (file >= 0) close(file);
        return;
    }
    if (response.fileURL) {
        lseek(file, (off_t)response.fileOffset, SEEK_SET);
        unsigned long long remaining = response.fileLength;
        unsigned char bytes[65536];
        while (remaining > 0) {
            size_t requested = (size_t)MIN((unsigned long long)sizeof(bytes), remaining);
            ssize_t count = read(file, bytes, requested);
            if (count <= 0 || ![self sendBytes:bytes length:(NSUInteger)count socket:client]) break;
            remaining -= (unsigned long long)count;
        }
        close(file);
    } else if (response.body) {
        [self sendData:response.body socket:client];
    }
}

- (BOOL)sendData:(NSData *)data socket:(int)client
{
    return [self sendBytes:[data bytes] length:[data length] socket:client];
}

- (BOOL)sendBytes:(const void *)bytes length:(NSUInteger)length socket:(int)client
{
    NSUInteger sent = 0;
    while (sent < length) {
        ssize_t count = send(client, (const unsigned char *)bytes + sent, length - sent, 0);
        if (count <= 0) return NO;
        sent += (NSUInteger)count;
    }
    return YES;
}

- (NSString *)reasonForStatus:(NSInteger)status
{
    if (status == 200) return @"OK";
    if (status == 206) return @"Partial Content";
    if (status == 400) return @"Bad Request";
    if (status == 401) return @"Unauthorized";
    if (status == 404) return @"Not Found";
    if (status == 416) return @"Range Not Satisfiable";
    if (status == 429) return @"Too Many Requests";
    return @"Error";
}

- (NSDictionary *)deviceInfo
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *deviceId = [defaults stringForKey:@"RLVDeviceIdentifier"];
    if (!deviceId) {
        deviceId = [[[NSUUID UUID] UUIDString] uppercaseString];
        [defaults setObject:deviceId forKey:@"RLVDeviceIdentifier"];
        [defaults synchronize];
    }
    RLVDeviceCapabilities *capabilities = [RLVDeviceCapabilities currentCapabilities];
    NSDictionary *transferCapabilities = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool:YES], @"rangeDownload", [NSNumber numberWithBool:NO], @"batchExport",
        [NSNumber numberWithBool:NO], @"delete", nil];
    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ?: @"1.0";
    return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:1], @"protocolVersion",
        deviceId, @"deviceId", [[UIDevice currentDevice] name] ?: @"RetroLive Camera", @"deviceName",
        capabilities.modelIdentifier ?: @"unknown", @"modelIdentifier",
        capabilities.systemVersion ?: @"unknown", @"systemVersion", version, @"appVersion",
        transferCapabilities, @"capabilities", nil];
}

- (NSString *)currentWiFiAddress
{
    struct ifaddrs *interfaces = NULL;
    NSString *result = nil;
    if (getifaddrs(&interfaces) != 0) return nil;
    for (struct ifaddrs *item = interfaces; item != NULL; item = item->ifa_next) {
        if (!item->ifa_addr || item->ifa_addr->sa_family != AF_INET) continue;
        if ((item->ifa_flags & IFF_LOOPBACK) != 0) continue;
        char address[INET_ADDRSTRLEN];
        struct sockaddr_in *internetAddress = (struct sockaddr_in *)item->ifa_addr;
        if (inet_ntop(AF_INET, &internetAddress->sin_addr, address, sizeof(address))) {
            result = [NSString stringWithUTF8String:address];
            if (strcmp(item->ifa_name, "en0") == 0) break;
        }
    }
    freeifaddrs(interfaces);
    return result;
}

- (BOOL)failWithCode:(NSInteger)code description:(NSString *)description error:(NSError **)error
{
    if (error) *error = [NSError errorWithDomain:RLVTransferServiceErrorDomain code:code
        userInfo:[NSDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey]];
    return NO;
}

@synthesize running = _running;
@synthesize port = _port;
@synthesize pairingCode = _pairingCode;
@synthesize localAddress = _localAddress;
@synthesize pairedClientName = _pairedClientName;
@synthesize netService = _netService;
@synthesize router = _router;

@end
