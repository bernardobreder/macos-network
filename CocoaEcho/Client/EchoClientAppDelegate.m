
#import "EchoClientAppDelegate.h"

@interface NSNetService (QNetworkAdditions)

- (BOOL)qNetworkAdditions_getInputStream:(out NSInputStream **)inputStreamPtr 
    outputStream:(out NSOutputStream **)outputStreamPtr;

@end

@implementation NSNetService (QNetworkAdditions)

- (BOOL)qNetworkAdditions_getInputStream:(out NSInputStream **)inputStreamPtr 
    outputStream:(out NSOutputStream **)outputStreamPtr
{
    BOOL                result;
    CFReadStreamRef     readStream;
    CFWriteStreamRef    writeStream;

    result = NO;
    
    readStream = NULL;
    writeStream = NULL;
    
    if ( (inputStreamPtr != NULL) || (outputStreamPtr != NULL) ) {
        CFNetServiceRef     netService;

        netService = CFNetServiceCreate(
            NULL, 
            (__bridge CFStringRef) [self domain], 
            (__bridge CFStringRef) [self type], 
            (__bridge CFStringRef) [self name], 
            0
        );
        if (netService != NULL) {
            CFStreamCreatePairWithSocketToNetService(
                NULL, 
                netService, 
                ((inputStreamPtr  != nil) ? &readStream  : NULL), 
                ((outputStreamPtr != nil) ? &writeStream : NULL)
            );
            CFRelease(netService);
        }

        result = ! ((( inputStreamPtr != NULL) && ( readStream == NULL)) ||
                    ((outputStreamPtr != NULL) && (writeStream == NULL)));
    }
    if (inputStreamPtr != NULL) {
        *inputStreamPtr  = CFBridgingRelease(readStream);
    }
    if (outputStreamPtr != NULL) {
        *outputStreamPtr = CFBridgingRelease(writeStream);
    }
    
    return result;
}

@end

#pragma mark -
#pragma mark EchoClientAppDelegate class

@interface EchoClientAppDelegate () <NSApplicationDelegate, NSNetServiceBrowserDelegate, NSStreamDelegate>

// stuff for IB

@property (nonatomic, assign, readwrite) IBOutlet NSTextField * responseField;

- (IBAction)requestTextFieldReturnAction:(id)sender;

// stuff for bindings

@property (nonatomic, strong, readwrite) NSMutableArray *       services;           // of NSNetService

// private properties

@property (nonatomic, strong, readwrite) NSNetServiceBrowser *  serviceBrowser;
@property (nonatomic, strong, readwrite) NSInputStream *        inputStream;
@property (nonatomic, strong, readwrite) NSOutputStream *       outputStream;
@property (nonatomic, strong, readwrite) NSMutableData *        inputBuffer;
@property (nonatomic, strong, readwrite) NSMutableData *        outputBuffer;

// forward declarations

- (void)closeStreams;

@end

@implementation EchoClientAppDelegate

@synthesize responseField = _responseField;
@synthesize services = _serviceList;

@synthesize serviceBrowser = _serviceBrowser;
@synthesize inputStream  = _inputStream;
@synthesize outputStream = _outputStream;
@synthesize inputBuffer  = _inputBuffer;
@synthesize outputBuffer = _outputBuffer;

- (void)awakeFromNib {
    self.serviceBrowser = [[NSNetServiceBrowser alloc] init];
    self.services = [[NSMutableArray alloc] init];
    [self.serviceBrowser setDelegate:self];
    [self.serviceBrowser searchForServicesOfType:@"_cocoaecho._tcp." inDomain:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

#pragma mark -
#pragma mark NSNetServiceBrowser delegate methods

// We broadcast the willChangeValueForKey: and didChangeValueForKey: for the NSTableView binding to work.

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreComing {
    if (![self.services containsObject:aNetService]) {
        [self willChangeValueForKey:@"services"];
        [self.services addObject:aNetService];
        [self didChangeValueForKey:@"services"];
    }
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveService:(NSNetService *)aNetService moreComing:(BOOL)moreComing {
    if ([self.services containsObject:aNetService]) {
        [self willChangeValueForKey:@"services"];
        [self.services removeObject:aNetService];
        [self didChangeValueForKey:@"services"];
    }
}

#pragma mark -
#pragma mark Stream methods

- (void)openStreamsToNetService:(NSNetService *)netService {
    NSInputStream * istream;
    NSOutputStream * ostream;

    [self closeStreams];

    if ([netService qNetworkAdditions_getInputStream:&istream outputStream:&ostream]) {
        self.inputStream = istream;
        self.outputStream = ostream;
        [self.inputStream  setDelegate:self];
        [self.outputStream setDelegate:self];
        [self.inputStream  scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [self.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [self.inputStream  open];
        [self.outputStream open];
    }
}

- (void)closeStreams {
    [self.inputStream  setDelegate:nil];
    [self.outputStream setDelegate:nil];
    [self.inputStream  close];
    [self.outputStream close];
    [self.inputStream  removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    self.inputStream  = nil;
    self.outputStream = nil;
    self.inputBuffer  = nil;
    self.outputBuffer = nil;
}

- (void)startOutput
{
    NSInteger actuallyWritten = [self.outputStream write:[self.outputBuffer bytes] maxLength:[self.outputBuffer length]];
    if (actuallyWritten > 0) {
        [self.outputBuffer replaceBytesInRange:NSMakeRange(0, (NSUInteger) actuallyWritten) withBytes:NULL length:0];
    } else {
        [self closeStreams];
    }
}

- (void)outputText:(NSString *)text
{
    NSData * dataToSend = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (self.outputBuffer != nil) {
        BOOL wasEmpty = ([self.outputBuffer length] == 0);
        [self.outputBuffer appendData:dataToSend];
        if (wasEmpty) {
            [self startOutput];
        }
    }
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)streamEvent {
    switch(streamEvent) {
        case NSStreamEventOpenCompleted: {
            if (aStream == self.inputStream) {
                self.inputBuffer = [[NSMutableData alloc] init];
            } else {
                self.outputBuffer = [[NSMutableData alloc] init];
            }
        } break;
        case NSStreamEventHasSpaceAvailable: {
            if ([self.outputBuffer length] != 0) {
                [self startOutput];
            }
        } break;
        case NSStreamEventHasBytesAvailable: {
            uint8_t buffer[2048];
            NSInteger actuallyRead = [self.inputStream read:buffer maxLength:sizeof(buffer)];
            if (actuallyRead > 0) {
                [self.inputBuffer appendBytes:buffer length:(NSUInteger)actuallyRead];
                if ([self.inputBuffer length] >= 2 && memcmp((const char *) [self.inputBuffer bytes] + [self.inputBuffer length] - 2, "\r\n", 2) == 0) {
                    NSString * string = [[NSString alloc] initWithData:self.inputBuffer encoding:NSUTF8StringEncoding];
                    if (string == nil) {
                        [self.responseField setStringValue:@"response not UTF-8"];
                    } else {
                        [self.responseField setStringValue:string];
                    }
                    [self.inputBuffer setLength:0];
                }
            }
        } break;
        case NSStreamEventErrorOccurred:
        case NSStreamEventEndEncountered: {
            [self closeStreams];
        } break;
        default:
            break;
    }
}

#pragma mark -
#pragma mark User interface action methods

- (IBAction)requestTextFieldReturnAction:(id)sender {
    [self outputText:[NSString stringWithFormat:@"%@\r\n", [sender stringValue]]];
}

- (IBAction)serviceTableClickedAction:(id)sender {
    NSTableView * table = (NSTableView *) sender;
    NSInteger selectedRow = [table selectedRow];
    
    if (selectedRow >= 0) {
        NSNetService * selectedService = [self.services objectAtIndex:(NSUInteger) selectedRow];
        [self openStreamsToNetService:selectedService];
    }
}

@end
