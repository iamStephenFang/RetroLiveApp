#import <Foundation/Foundation.h>

/// Posted on the main thread whenever running, address, pairing, or client state changes.
extern NSString * const RLVTransferServiceDidChangeNotification;

/// Owns the local HTTP listener, Bonjour advertisement, and active transfer connections.
@interface RLVTransferService : NSObject

@property (nonatomic, assign, readonly, getter=isRunning) BOOL running;
@property (nonatomic, assign, readonly) NSUInteger port;
@property (nonatomic, copy, readonly) NSString *pairingCode;
@property (nonatomic, copy, readonly) NSString *localAddress;
@property (nonatomic, copy, readonly) NSString *pairedClientName;

+ (RLVTransferService *)sharedService;
/// Starts listening and advertising. Returns NO and sets error when no listener can be created.
- (BOOL)start:(NSError **)error;
/// Stops advertising and connections and clears all externally visible connection state.
- (void)stop;

@end
