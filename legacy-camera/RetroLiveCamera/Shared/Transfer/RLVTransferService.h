#import <Foundation/Foundation.h>

extern NSString * const RLVTransferServiceDidChangeNotification;

@interface RLVTransferService : NSObject

@property (nonatomic, assign, readonly, getter=isRunning) BOOL running;
@property (nonatomic, assign, readonly) NSUInteger port;
@property (nonatomic, copy, readonly) NSString *pairingCode;
@property (nonatomic, copy, readonly) NSString *localAddress;
@property (nonatomic, copy, readonly) NSString *pairedClientName;

+ (RLVTransferService *)sharedService;
- (BOOL)start:(NSError **)error;
- (void)stop;

@end
