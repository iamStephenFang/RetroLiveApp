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
#import <unistd.h>

NSString * const RLVTransferServiceDidChangeNotification = @"RLVTransferServiceDidChangeNotification";
static NSString * const RLVTransferServiceErrorDomain = @"com.retrolive.transfer-service";

@interface RLVTransferService () {
    int _listenSocket;
    dispatch_source_t _acceptSource;
    dispatch_queue_t _acceptQueue;
}
@property (nonatomic, assign, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, assign, readwrite) NSUInteger port;
@property (nonatomic, copy, readwrite) NSString *pairingCode;
@property (nonatomic, copy, readwrite) NSString *localAddress;
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
    if (listener < 0) return [self failWithCode:1 description:@"Unable to create the transfer socket." error:error];
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
            return [self failWithCode:2 description:@"Unable to bind a local transfer port." error:error];
        }
    }
    if (listen(listener, 8) != 0) {
        close(listener);
        return [self failWithCode:3 description:@"Unable to listen for transfer clients." error:error];
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
    self.router = nil;
    self.pairingCode = nil;
    self.localAddress = nil;
    self.port = 0;
    self.running = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:RLVTransferServiceDidChangeNotification object:self];
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
                    expectedLength = headerRange.location + 4 + [[headers objectForKey:@"content-length"] integerValue];
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
    NSUInteger declaredLength = [[headers objectForKey:@"content-length"] integerValue];
    if (bodyStart + declaredLength > [data length]) {
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
        if (key && value) [headers setObject:value forKey:key];
    }
    return headers;
}

- (void)writeResponse:(RLVHTTPResponse *)response toSocket:(int)client
{
    unsigned long long length = response.fileURL ? response.fileLength : [response.body length];
    NSMutableString *head = [NSMutableString stringWithFormat:@"HTTP/1.1 %ld %@\r\n", (long)response.statusCode, [self reasonForStatus:response.statusCode]];
    for (NSString *key in response.headers) [head appendFormat:@"%@: %@\r\n", key, [response.headers objectForKey:key]];
    [head appendFormat:@"Content-Length: %llu\r\nConnection: close\r\n\r\n", length];
    if (![self sendData:[head dataUsingEncoding:NSISOLatin1StringEncoding] socket:client]) return;
    if (response.fileURL) {
        int file = open([[response.fileURL path] fileSystemRepresentation], O_RDONLY);
        if (file < 0) return;
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
        ssize_t count = send(client, (const unsigned char *)bytes + sent, length - sent, MSG_NOSIGNAL);
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
@synthesize netService = _netService;
@synthesize router = _router;

@end
