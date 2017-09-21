

#import "EchoConnection.h"

NSString * EchoConnectionDidCloseNotification = @"EchoConnectionDidCloseNotification";

@interface EchoConnection () <NSStreamDelegate>
@end

@implementation EchoConnection

@synthesize inputStream  = _inputStream;
@synthesize outputStream = _outputStream;

- (id)initWithInputStream:(NSInputStream *)inputStream outputStream:(NSOutputStream *)outputStream
{
    self = [super init];
    if (self != nil) {
        self->_inputStream = inputStream;
        self->_outputStream = outputStream;
    }
    return self;
}

- (BOOL)open {
    [self.inputStream  setDelegate:self];
    [self.outputStream setDelegate:self];
    [self.inputStream  scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.inputStream  open];
    [self.outputStream open];
    return YES;
}

- (void)close {
    [self.inputStream  setDelegate:nil];
    [self.outputStream setDelegate:nil];
    [self.inputStream  close];
    [self.outputStream close];
    [self.inputStream  removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [(NSNotificationCenter *)[NSNotificationCenter defaultCenter] postNotificationName:EchoConnectionDidCloseNotification object:self];
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)streamEvent {
    assert(aStream == self.inputStream || aStream == self.outputStream);
    #pragma unused(aStream)
    
    switch(streamEvent) {
        case NSStreamEventHasBytesAvailable: {
            uint8_t buffer[2048];
            NSInteger actuallyRead = [self.inputStream read:(uint8_t *)buffer maxLength:sizeof(buffer)];
            if (actuallyRead > 0) {
                NSInteger actuallyWritten = [self.outputStream write:buffer maxLength:(NSUInteger)actuallyRead];
                if (actuallyWritten != actuallyRead) {
                    // -write:maxLength: may return -1 to indicate an error or a non-negative 
                    // value less than maxLength to indicate a 'short write'.  In the case of an 
                    // error we just shut down the connection.  The short write case is more 
                    // interesting.  A short write means that the client has sent us data to echo but 
                    // isn't reading the data that we send back to it, thus causing its socket receive 
                    // buffer to fill up, thus causing our socket send buffer to fill up.  Again, our 
                    // response to this situation is that we simply drop the connection.
                    [self close];
                } else {
                    NSLog(@"Echoed %zd bytes.", (ssize_t) actuallyWritten);
                }
            } else {
                // A non-positive value from -read:maxLength: indicates either end of file (0) or 
                // an error (-1).  In either case we just wait for the corresponding stream event 
                // to come through.
            }
        } break;
        case NSStreamEventEndEncountered:
        case NSStreamEventErrorOccurred: {
            [self close];
        } break;
        case NSStreamEventHasSpaceAvailable:
        case NSStreamEventOpenCompleted:
        default: {
            // do nothing
        } break;
    }
}

@end
