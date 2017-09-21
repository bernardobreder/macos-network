
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
    CFSocketRef         _listeningSocket;
}

- (id)init
{
    if (!(self = [super init])) return nil;
    self->_queue = [[NSOperationQueue alloc] init];
    return self;
}

#pragma mark * Application delegate callbacks

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
}

- (void)applicationWillTerminate:(NSNotification *)sender
{
#pragma unused(sender)
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
    return self.inProgressSendCount != 0;
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
    int fdForListening = socket(AF_INET6, SOCK_STREAM, 0);
    if (fdForListening < 0) return false;
    struct sockaddr_in6 serverAddress6;
    memset(&serverAddress6, 0, sizeof(serverAddress6));
    serverAddress6.sin6_family = AF_INET6;
    serverAddress6.sin6_len    = sizeof(serverAddress6);
    if (bind(fdForListening, (const struct sockaddr *) &serverAddress6, sizeof(serverAddress6)) < 0) { close(fdForListening); return false; }
    socklen_t namelen = sizeof(serverAddress6);
    if (getsockname(fdForListening, (struct sockaddr *) &serverAddress6, &namelen) < 0) { close(fdForListening); return false; }
    int chosenPort = ntohs(serverAddress6.sin6_port);
    if (listen(fdForListening, 5) < 0) { close(fdForListening); return false; }
    CFSocketContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};
    _listeningSocket = CFSocketCreateWithNative(NULL, fdForListening, kCFSocketAcceptCallBack, ListeningSocketCallback, &context);
    if (!_listeningSocket) { close(fdForListening); return false; }
    CFRunLoopSourceRef rls = CFSocketCreateRunLoopSource(NULL, _listeningSocket, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);
    CFRelease(rls);
    
    _netService = [[NSNetService alloc] initWithDomain:@"" type:@"_wwdcpic2._tcp." name:@"Teste" port:chosenPort];
    _netService.delegate = self;
    [_netService publish];
    self.running = YES;
    return true;
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
{
    self.serviceName = [sender name];
}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict
{
    [self stopWithStatus:@"Failed to registered service."];
}

- (void)netServiceDidStop:(NSNetService *)sender
{
    assert(sender == self.netService);
#pragma unused(sender)
    [self stopWithStatus:@"Network service stopped."];
}

static void ListeningSocketCallback(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
    ServerAppDelegate *obj = (__bridge ServerAppDelegate *) info;
    int fd = *(const int *) data;
    [obj connectionReceived:fd];
}

- (void)connectionReceived:(int)fd
// Called when a connection is received.  We respond by creating and running a
// FileSendOperation that sends the current picture down the connection.
{
    CFWriteStreamRef    writeStream;
    FileSendOperation * op;
    Boolean             success;
    // Create a CFStream from the connection socket.
    CFStreamCreatePairWithSocket(NULL, fd, NULL, &writeStream);
    success = CFWriteStreamSetProperty(writeStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    // Create a FileSendOperation to run the connection.
    op = [[FileSendOperation alloc] initWithFilePath:self.selectedImagePath outputStream:(__bridge NSOutputStream *) writeStream];
    [op addObserver:self forKeyPath:@"isFinished" options:0 context:&self->_queue];
    self.inProgressSendCount += 1;
    [self.queue addOperation:op];
    CFRelease(writeStream);
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == &self->_queue) {
        [self performSelectorOnMainThread:@selector(didFinishOperation:) withObject:object waitUntilDone:NO];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)didFinishOperation:(FileSendOperation *)op
{
    [op removeObserver:self forKeyPath:@"isFinished"];
    if (op.error == nil) {
        self.successfulSendCount += 1;
    } else {
        self.failedSendCount += 1;
    }
    self.inProgressSendCount -= 1;
}

@end
