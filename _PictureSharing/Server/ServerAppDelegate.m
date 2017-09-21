
#import "ServerAppDelegate.h"
#import "FileSendOperation.h"
#include <sys/socket.h>
#include <netinet/in.h>

@interface ServerAppDelegate () <NSNetServiceDelegate, NSApplicationDelegate>

enum {
    kDebugMenuTag = 0x64626720          // == 'dbg ' == 1684170528
};

enum {
    kDebugOptionMaskStallSend        = 0x01,
    kDebugOptionMaskSendBadChecksum  = 0x02,
    kDebugOptionMaskForceIPv4        = 0x04,
    kDebugOptionMaskAutoAdvanceImage = 0x08
};

- (IBAction)startStopAction:(id)sender;

- (IBAction)toggleDebugOptionAction:(id)sender;

@property (nonatomic, copy,   readonly ) NSArray *          pictureNames;
@property (nonatomic, assign, readwrite) NSUInteger         selectedPictureIndex;
@property (nonatomic, copy,   readonly ) NSString *         selectedImagePath;
@property (nonatomic, copy,   readonly ) NSString *         startStopButtonTitle;
@property (nonatomic, copy,   readonly ) NSString *         shortStatus;
@property (nonatomic, copy,   readwrite) NSString *         longStatus;
@property (nonatomic, assign, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, copy,   readwrite) NSString *         serviceName;
@property (nonatomic, assign, readonly, getter=isSending)  BOOL sending;
@property (nonatomic, assign, readwrite) NSUInteger         inProgressSendCount;
@property (nonatomic, assign, readwrite) NSUInteger         successfulSendCount;
@property (nonatomic, assign, readwrite) NSUInteger         failedSendCount;

@property (nonatomic, copy,   readonly ) NSString *         defaultServiceName;
@property (nonatomic, strong, readwrite) NSNetService *     netService;
@property (nonatomic, strong, readonly ) NSOperationQueue * queue;
@property (nonatomic, assign, readwrite) NSUInteger         debugOptions;

@end

@implementation ServerAppDelegate {
    CFSocketRef _listeningSocket;
}

- (id)init
{
    if (!(self = [super init])) return nil;
    self->_queue = [[NSOperationQueue alloc] init];
    return self;
}

#pragma mark * Application delegate callbacks

- (void)applicationWillTerminate:(NSNotification *)sender
{
    [self stopWithStatus:nil];
}

#pragma mark * Bound properties

- (NSArray *)pictureNames
{
    return @[@"Yosemite 2", @"Yosemite 3", @"Yosemite 4", @"Yosemite 5"];
}

+ (NSSet *)keyPathsForValuesAffectingSelectedImagePath
{
    return [NSSet setWithObject:@"selectedPictureIndex"];
}

- (NSString *)selectedImagePath
{
    return [NSString stringWithFormat:@"/Library/Desktop Pictures/%@.jpg", self.pictureNames[self.selectedPictureIndex]];
}

+ (NSSet *)keyPathsForValuesAffectingStartStopButtonTitle
{
    return [NSSet setWithObject:@"running"];
}

- (NSString *)startStopButtonTitle
{
    NSString *  result;
    if (self.isRunning) {
        result = @"Stop";
    } else {
        result = @"Start";
    }
    return result;
}

+ (NSSet *)keyPathsForValuesAffectingShortStatus
{
    return [NSSet setWithObject:@"running"];
}

- (NSString *)shortStatus
{
    NSString *  result;
    if (self.isRunning) {
        result = @"Picture Sharing is on.";
    } else {
        result = @"Picture Sharing is off.";
    }
    return result;
}

- (NSString *)longStatus
{
    NSString *  result;
    if (self->_longStatus == nil) {
        result = @"Click Start to turn on Picture Sharing and allow other users to see a thumbnail of the picture below.";
    } else {
        result = self->_longStatus;
    }
    return result;
}

- (NSString *)defaultServiceName
{
    NSString *  result;
    
    result = [[NSUserDefaults standardUserDefaults] stringForKey:@"defaultServiceName"];
    if (result == nil) {
        NSString *  str;
        
        str = NSFullUserName();
        if (str == nil) {
            result = @"Pictures";
            assert(result != nil);
        } else {
            result = [NSString stringWithFormat:@"%@'s Pictures", str];
            assert(result != nil);
        }
    }
    assert(result != nil);
    return result;
}

@synthesize serviceName = _serviceName;

- (NSString *)serviceName
{
    if (self->_serviceName == nil) {
        self->_serviceName = [[self defaultServiceName] copy];
        assert(self->_serviceName != nil);
    }
    return self->_serviceName;
}

- (void)setServiceName:(NSString *)newValue
{
    if (newValue != self->_serviceName) {
        self->_serviceName = [newValue copy];
        
        if (self->_serviceName == nil) {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"defaultServiceName"];
        } else {
            [[NSUserDefaults standardUserDefaults] setObject:self->_serviceName forKey:@"defaultServiceName"];
        }
    }
}

+ (NSSet *)keyPathsForValuesAffectingSending
{
    return [NSSet setWithObject:@"inProgressSendCount"];
}

- (BOOL)isSending
{
    return _inProgressSendCount != 0;
}

#pragma mark * Actions

- (IBAction)startStopAction:(id)sender
{
    if (self.isRunning) {
        [self stopWithStatus:nil];
    } else {
        if ([self start]) {
            self.longStatus = @"Click Stop to turn off Picture Sharing.";
        } else {
            [self stopWithStatus:@"Failed to start up."];
        }
    }
}

- (IBAction)toggleDebugOptionAction:(id)sender
{
    NSMenuItem *    menuItem;
    menuItem = (NSMenuItem *) sender;
    assert([menuItem isKindOfClass:[NSMenuItem class]]);
    assert([menuItem tag] != 0);
    self.debugOptions ^= (NSUInteger) [menuItem tag];
    [menuItem setState: ! [menuItem state]];
}

#pragma mark * Core networking code

- (bool)start
{
    int err, junk, chosenPort = -1;
    socklen_t namelen;
    int fdForListening = socket(AF_INET6, SOCK_STREAM, 0);
    if (fdForListening < 0) return false;
    struct sockaddr_in6 serverAddress6;
    memset(&serverAddress6, 0, sizeof(serverAddress6));
    serverAddress6.sin6_family = AF_INET6;
    serverAddress6.sin6_len    = sizeof(serverAddress6);
    err = bind(fdForListening, (const struct sockaddr *) &serverAddress6, sizeof(serverAddress6));
    if (err < 0) { close(fdForListening); return false; }
    namelen = sizeof(serverAddress6);
    err = getsockname(fdForListening, (struct sockaddr *) &serverAddress6, &namelen);
    if (err < 0) { close(fdForListening); return false; }
    chosenPort = ntohs(serverAddress6.sin6_port);
    err = listen(fdForListening, 5);
    if (err < 0) { close(fdForListening); return false; }
    CFSocketContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};
    _listeningSocket = CFSocketCreateWithNative(NULL, fdForListening, kCFSocketAcceptCallBack, ListeningSocketCallback, &context);
    if (!_listeningSocket) { close(fdForListening); return false; }
    CFRunLoopSourceRef rls = CFSocketCreateRunLoopSource(NULL, _listeningSocket, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);
    CFRelease(rls);
    _netService = [[NSNetService alloc] initWithDomain:@"" type:@"_wwdcpic2._tcp." name:self.serviceName port:chosenPort];
    if (!_netService) { return false; }
    _netService.delegate = self;
    [_netService publish];
    _running = YES;
    return true;
    // Here, create the socket from traditional BSD socket calls, and then set up a CFSocket with that to listen for incoming connections.
    // Start by trying to do everything with IPv6.  This will work for both IPv4 and IPv6 clients via the miracle of mapped IPv4 addresses.
    //    if (self.debugOptions & kDebugOptionMaskForceIPv4) {
    //        // This allows us to test IPv4 support on an IPv6-capable kernel.
    //        fdForListening = -1;
    //        err = EAFNOSUPPORT;
    //    } else {
    //        err = 0;
    //        fdForListening = socket(AF_INET6, SOCK_STREAM, 0);
    //        if (fdForListening < 0) {
    //            err = errno;
    //        }
    //    }
    //    if (err == 0) {
    //        struct sockaddr_in6 serverAddress6;
    //
    //        // If we created an IPv6 socket, bind it to a kernel-assigned port and then use
    //        // getsockname to determine what port we got.
    //
    //        memset(&serverAddress6, 0, sizeof(serverAddress6));
    //        serverAddress6.sin6_family = AF_INET6;
    //        serverAddress6.sin6_len    = sizeof(serverAddress6);
    //
    //        err = bind(fdForListening, (const struct sockaddr *) &serverAddress6, sizeof(serverAddress6));
    //        if (err < 0) {
    //            err = errno;
    //        }
    //        if (err == 0) {
    //            namelen = sizeof(serverAddress6);
    //            err = getsockname(fdForListening, (struct sockaddr *) &serverAddress6, &namelen);
    //            if (err < 0) {
    //                err = errno;
    //                assert(err != 0);       // quietens static analyser
    //            } else {
    //                chosenPort = ntohs(serverAddress6.sin6_port);
    //            }
    //        }
    //    } else if (err == EAFNOSUPPORT) {
    //        struct sockaddr_in  serverAddress;
    //
    //        // IPv6 is not available (this can happen, for example, on early versions of iOS).
    //        // Let's fall back to IPv4.  Create an IPv4 socket, bind it to a kernel-assigned port
    //        // and then use getsockname to determine what port we got.
    //
    //        err = 0;
    //        fdForListening = socket(AF_INET, SOCK_STREAM, 0);
    //        if (fdForListening < 0) {
    //            err = errno;
    //        }
    //
    //        if (err == 0) {
    //            memset(&serverAddress, 0, sizeof(serverAddress));
    //            serverAddress.sin_family = AF_INET;
    //            serverAddress.sin_len    = sizeof(serverAddress);
    //
    //            err = bind(fdForListening, (const struct sockaddr *) &serverAddress, sizeof(serverAddress));
    //            if (err < 0) {
    //                err = errno;
    //            }
    //        }
    //        if (err == 0) {
    //            namelen = sizeof(serverAddress);
    //            err = getsockname(fdForListening, (struct sockaddr *) &serverAddress, &namelen);
    //            if (err < 0) {
    //                err = errno;
    //                assert(err != 0);       // quietens static analyser
    //            } else {
    //                chosenPort = ntohs(serverAddress.sin_port);
    //            }
    //        }
    //    }
    //
    //    // Listen for connections on our socket, then create a CFSocket to route any connections
    //    // to a run loop based callback.
    //
    //    if (err == 0) {
    //        err = listen(fdForListening, 5);
    //        if (err < 0) {
    //            err = errno;
    //        } else {
    //            CFSocketContext     context = {0, (__bridge void *)(self), NULL, NULL, NULL};
    //            CFRunLoopSourceRef  rls;
    //
    //            self->_listeningSocket = CFSocketCreateWithNative(NULL, fdForListening, kCFSocketAcceptCallBack, ListeningSocketCallback, &context);
    //            if (self->_listeningSocket != NULL) {
    //                assert( CFSocketGetSocketFlags(self->_listeningSocket) & kCFSocketCloseOnInvalidate );
    //                fdForListening = -1;        // so that the clean up code doesn't close it
    //
    //                rls = CFSocketCreateRunLoopSource(NULL, self->_listeningSocket, 0);
    //                assert(rls != NULL);
    //
    //                CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);
    //
    //                CFRelease(rls);
    //            }
    //        }
    //    }
    //
    //    // Register our service with Bonjour.
    //
    //    if (err == 0) {
    //        NSLog(@"chosenPort = %d", chosenPort);
    //
    //        self.netService = [[NSNetService alloc] initWithDomain:@"" type:@"_wwdcpic2._tcp." name:self.serviceName port:chosenPort];
    //        if (self.netService != nil) {
    //            [self.netService setDelegate:self];
    //            [self.netService publish];
    //        }
    //    }
    //
    //    // Clean up.
    //
    //    if ( (self->_listeningSocket != NULL) && (self.netService != nil) ) {
    //        self.longStatus = @"Click Stop to turn off Picture Sharing.";
    //        self.running = YES;
    //    } else {
    //        [self stopWithStatus:@"Failed to start up."];
    //    }
    //    if (fdForListening >= 0) {
    //        junk = close(fdForListening);
    //        assert(junk == 0);
    //    }
}

- (void)stopWithStatus:(NSString *)newStatus
{
    self.longStatus = newStatus;
    
    if (self.netService != nil) {
        [self.netService setDelegate:nil];
        [self.netService stop];
        self.netService = nil;
    }
    if (self->_listeningSocket != NULL) {
        CFSocketInvalidate(self->_listeningSocket);
        CFRelease(self->_listeningSocket);
        self->_listeningSocket = NULL;
    }
    
    [self.queue cancelAllOperations];
    
    self.running = NO;
}

- (void)netServiceDidPublish:(NSNetService *)sender
// An NSNetService delegate callback that's called when the service is successfully
// registered on the network.  We set our service name to the name of the service
// because the service might be been automatically renamed by Bonjour to avoid
// conflicts.
{
    assert(sender == self.netService);
    self.serviceName = [sender name];
}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict
// An NSNetService delegate callback that's called when the service fails to
// register on the network.  We respond by shutting down our entire network
// service.
{
    assert(sender == self.netService);
#pragma unused(sender)
#pragma unused(errorDict)
    [self stopWithStatus:@"Failed to registered service."];
}

- (void)netServiceDidStop:(NSNetService *)sender
// An NSNetService delegate callback that's called when the service spontaneously
// stops.  This rarely happens on OS X but, regardless, we respond by shutting
// down our entire network service.
{
    assert(sender == self.netService);
#pragma unused(sender)
    [self stopWithStatus:@"Network service stopped."];
}

static void ListeningSocketCallback(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
// The CFSocket callback associated with _listeningSocket.  This is called when
// a new connection arrives.  It routes the connection to the -connectionReceived:
// method.
{
    ServerAppDelegate *   obj;
    int             fd;
    
    obj = (__bridge ServerAppDelegate *) info;
    assert([obj isKindOfClass:[ServerAppDelegate class]]);
    
    assert(s == obj->_listeningSocket);
#pragma unused(s)
    assert(type == kCFSocketAcceptCallBack);
#pragma unused(type)
    assert(address != NULL);
#pragma unused(address)
    assert(data != nil);
    
    fd = * (const int *) data;
    assert(fd >= 0);
    [obj connectionReceived:fd];
}

- (void)connectionReceived:(int)fd
// Called when a connection is received.  We respond by creating and running a
// FileSendOperation that sends the current picture down the connection.
{
    CFWriteStreamRef    writeStream;
    FileSendOperation * op;
    Boolean             success;
    
    assert(fd >= 0);
    
    // Create a CFStream from the connection socket.
    
    CFStreamCreatePairWithSocket(NULL, fd, NULL, &writeStream);
    assert(writeStream != nil);
    
    success = CFWriteStreamSetProperty(writeStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    assert(success);
    
    // Create a FileSendOperation to run the connection.
    
    op = [[FileSendOperation alloc] initWithFilePath:self.selectedImagePath outputStream:(__bridge NSOutputStream *) writeStream];
    assert(op != nil);
    
    // Configure that operation.
    
#if ! defined(NDEBUG)
    if (self.debugOptions & kDebugOptionMaskStallSend) {
        op.debugStallSend = YES;
    }
    if (self.debugOptions & kDebugOptionMaskSendBadChecksum) {
        op.debugSendBadChecksum = YES;
    }
#endif
    
    // Watch for the operation finishing.  In a real application I'd probably use something more
    // sophisticated (like the QWatchedOperationQueue class from the LinkedImageFetcher sample code),
    // but in this small sample I just use KVO directly.
    
    [op addObserver:self forKeyPath:@"isFinished" options:0 context:&self->_queue];
    self.inProgressSendCount += 1;
    
    // Enqueue the operation and then clean up.
    
    assert(self.queue != nil);
    [self.queue addOperation:op];
    
    CFRelease(writeStream);
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == &self->_queue) {
        assert([keyPath isEqual:@"isFinished"]);
        assert([object isKindOfClass:[FileSendOperation class]]);
        
        // This notification is delivered when a FileSendOperation's "isFinished" property
        // changes.  We respond by calling the -didFinishOperation: operation on the main
        // thread to clean up that operation.
        
        assert( [(FileSendOperation *) object isFinished] );
        
        // IMPORTANT
        // ---------
        // KVO notifications arrive on the thread that sets the property.  In this case that's
        // always going to be the main thread (because FileSendOperation is a concurrent operation
        // that runs off the main thread run loop), but I take no chances and force us to the
        // main thread.  There's no worries about race conditions here (one of the things that
        // QWatchedOperationQueue solves nicely) because AppDelegate lives for the lifetime of
        // the application.
        
        [self performSelectorOnMainThread:@selector(didFinishOperation:) withObject:object waitUntilDone:NO];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)didFinishOperation:(FileSendOperation *)op
// Called when a FileSendOperation finishes.  It simply updates our statistics.
{
    assert([op isKindOfClass:[FileSendOperation class]]);
    
    [op removeObserver:self forKeyPath:@"isFinished"];
    
    if (op.error == nil) {
        self.successfulSendCount += 1;
    } else {
        self.failedSendCount += 1;
    }
    assert(self.inProgressSendCount != 0);
    self.inProgressSendCount -= 1;
    
    if (self.debugOptions & kDebugOptionMaskAutoAdvanceImage) {
        NSUInteger  newPictureIndex;
        
        newPictureIndex = self.selectedPictureIndex + 1;
        if (newPictureIndex == [self.pictureNames count]) {
            newPictureIndex = 0;
        }
        self.selectedPictureIndex = newPictureIndex;
    }
}

@end
