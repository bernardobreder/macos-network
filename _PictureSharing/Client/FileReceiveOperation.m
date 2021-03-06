
#import "FileReceiveOperation.h"

#include <zlib.h>

enum {
    kFileReceiveOperationStateStart, 
    kFileReceiveOperationStateHeader, 
    kFileReceiveOperationStateBody, 
    kFileReceiveOperationStateTrailer
};

enum {
    kFileReceiveOperationBufferSize = 32768
};

@interface FileReceiveOperation () <NSStreamDelegate>

// read/write variants of public properties

@property (atomic, copy,   readwrite) NSString *        finalFilePath;

// internal properties

@property (atomic, assign, readwrite) NSInteger         receiveState;
@property (atomic, strong, readwrite) NSOutputStream *  fileStream;
@property (atomic, strong, readwrite) NSMutableData *   buffer;
@property (atomic, assign, readwrite) NSUInteger        bufferOffset;
@property (atomic, assign, readwrite) off_t             fileLength;
@property (atomic, assign, readwrite) off_t             fileOffset;
@property (atomic, assign, readwrite) uLong             crc;

@end

@implementation FileReceiveOperation

- (id)initWithInputStream:(NSInputStream *)inputStream
{
    assert(inputStream != nil);

    self = [super init];
    if (self != nil) {
        self->_inputStream = inputStream;
    }
    return self;
}

- (void)dealloc
{
    assert(self->_buffer == nil);
    assert(self->_fileStream == nil);
}

#pragma mark * Start and stop

- (void)operationDidStart
    // Our superclass calls this on the actual run loop thread to give us an opportunity 
    // to install our run loop sources (and do various other bits of initialisation).
{
    assert(self.isActualRunLoopThread);
    assert(self.state == kQRunLoopOperationStateExecuting);

    // Decide where we're going to download to, and remember that in finalFilePath.
    // Note that, if the download fails, -operationWillFinish will nix finalFilePath 
    // so that the final result seen by our client is nil.
    
    if (self.filePath != nil) {
        self.finalFilePath = self.filePath;
    } else {
        self.finalFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"PictureSharing-%.9f.tmp", [NSDate timeIntervalSinceReferenceDate]]];
        assert(self.finalFilePath != nil);
        assert( ! [[NSFileManager defaultManager] fileExistsAtPath:self.finalFilePath] );
    }

    // Create and open our output file stream.
    
    self.fileStream = [NSOutputStream outputStreamToFileAtPath:self.finalFilePath append:NO];
    if (self.fileStream == nil) {
        [self finishWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:nil]];
    } else {
        [self.fileStream open];

        // Create a transfer buffer and set it up for the initial read of the header.
        
        self.buffer = [NSMutableData dataWithCapacity:kFileReceiveOperationBufferSize];
        assert(self.buffer != nil);
        
        // Open our input TCP stream.
        
        [self.inputStream setDelegate:self];
        for (NSString * mode in self.actualRunLoopModes) {
            [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:mode];
        }
        [self.inputStream open];

        assert(self.receiveState == kFileReceiveOperationStateStart);
        assert(self.bufferOffset == 0);
        assert(self.fileOffset == 0);
        assert(self.crc == 0);
    }
}

- (void)operationWillFinish
    // Our superclass calls this on the actual run loop thread to give us an opportunity 
    // to remove our run loop sources (and do various other bits of clean up).
{
    BOOL    failed;

    assert(self.isActualRunLoopThread);
    
    failed = (self.error != nil);
    
    if (self.fileStream != nil) {
        [self.fileStream close];
        self.fileStream = nil;
        
        // If we failed, we delete any file we created.
        
        if ( failed && (self.finalFilePath != nil) ) {
            (void) [[NSFileManager defaultManager] removeItemAtPath:self.finalFilePath error:NULL];
        }
    }
    if (failed) {
        self.finalFilePath = nil;
    }
    if (self.inputStream != nil) {
        // We want to hold on to our reference to inputStream until -dealloc, but 
        // we don't want to do this teardown twice, so we conditionalise it based on 
        // whether the delegate is still set.
        if ([self.inputStream delegate] != nil) {
            [self.inputStream setDelegate:nil];
            for (NSString * mode in self.actualRunLoopModes) {
                [self.inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:mode];
            }
            [self.inputStream close];
        }
    }
    self.buffer = nil;      // might as well free up the memory now
}

#pragma mark * Stream delegate callbacks

- (void)processHeaderBuffer
    // Called by the stream event handling delegate callback to handle a buffer 
    // containing header data.
{
    // Extract the file length.

    assert([self.buffer length] == sizeof(uint64_t));
    uint64_t tmp = OSSwapBigToHostInt64( * (const uint64_t *) [self.buffer bytes] );
    self.fileLength = (off_t) tmp;
    
    // We really should bounds check the file length to prevent a bogus server from 
    // running us completely out of disk space.  That's beyond the scope of this 
    // sample code though.
    
    assert(self.fileOffset == 0);
}

- (void)processBodyBuffer
    // Called by the stream event handling delegate callback to handle a buffer 
    // containing file body data.
{
    NSError *   error;
    NSUInteger  bytesWrittenTotal;
    NSInteger   bytesWritten;
    
    error = nil;
        
    // We just received a block of file data.  Update our CRC calculation.
    
    self.crc = crc32(self.crc, [self.buffer bytes], (uInt) [self.buffer length]);
    
    // Write buffer to disk.
    
    bytesWrittenTotal = 0;
    do {
        bytesWritten = [self.fileStream write:((const uint8_t *) [self.buffer bytes]) + bytesWrittenTotal maxLength:[self.buffer length] - bytesWrittenTotal];
        if (bytesWritten <= 0) {
            error = [self.fileStream streamError];
            assert(error != nil);
        } else {
            bytesWrittenTotal += (NSUInteger) bytesWritten;
        }
    } while ( (error == nil) && (bytesWrittenTotal != [self.buffer length]) );
    
    // And record that we've written that many bytes to the file.
    
    if (error == nil) {
        self.fileOffset += (off_t) [self.buffer length];
    } else {
        [self finishWithError:error];
    }
}

- (void)processTrailerBuffer
    // Called by the stream event handling delegate callback to handle a buffer 
    // containing trailer data.
{
    uint32_t    crcReceived;
    
    // We've just received the trailer.  Check its CRC.
    
    assert([self.buffer length] == sizeof(uint32_t));
    crcReceived = OSSwapBigToHostInt32( * (const uint32_t *) [self.buffer bytes] );
    #if ! defined(NDEBUG)
        if (self.debugReceiveBadChecksum) {
            crcReceived ^= 1;
        }
    #endif
    if (crcReceived == self.crc) {
        [self finishWithError:nil];
    } else {
        [self finishWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:nil]];
    }
}

- (void)setupNextReceiveBuffer
    // Called by the stream event handling delegate callback after handling a buffer of 
    // header or file body data.  It sets up the next receive buffer based on how 
    // much file body data is left to read.
{
    if (self.fileOffset < self.fileLength) {
        off_t   bytesRemaining;
        
        // More file to read.  Calculate the size of the next buffer.
        
        bytesRemaining = self.fileLength - self.fileOffset;
        if (bytesRemaining > (off_t) kFileReceiveOperationBufferSize) {
            bytesRemaining = kFileReceiveOperationBufferSize;
        }
        [self.buffer setLength:(NSUInteger) bytesRemaining];    // bytesRemaining can't overflow 32-bits because it's bounded by kFileReceiveOperationBufferSize
        self.receiveState = kFileReceiveOperationStateBody;
    } else {
    
        // No more file to read.  Set up the next buffer to receive the trailer.
        
        [self.buffer setLength:sizeof(uint32_t)];
        self.receiveState = kFileReceiveOperationStateTrailer;
    }
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
    // An NSStream delegate callback that's called when events happen on our TCP stream.
{
    // CFSocketStream does not retain its delegate.  It's possible that actions early 
    // in this method can affect the state of the program (typically by setting isFinished 
    // to YES so that all our clients release their references to the operation) such that 
    // all references to this object are released, resulting in code later in the method 
    // accessing a self that's been deallocated <rdar://problem/12682482>.  To avoid this, 
    // we manually retain self across the lifetime of this callback.
    
    CFRetain( (__bridge CFTypeRef) self );

    assert([NSThread isMainThread]);

    assert(aStream == self.inputStream);
    #pragma unused(aStream)

    switch (eventCode) {
        case NSStreamEventOpenCompleted: {
            // do nothing
        } break;
        case NSStreamEventHasBytesAvailable: {
            NSInteger       bytesRead;
            
            #if ! defined(NDEBUG)
                if (self.debugStallReceive) {
                    return;
                }
            #endif

            // If we're just starting out, set up to receive the header.
            
            if (self.receiveState == kFileReceiveOperationStateStart) {
                assert(self.bufferOffset == 0);
                [self.buffer setLength:sizeof(uint64_t)];
                self.receiveState = kFileReceiveOperationStateHeader;
            }

            // Try to read enough bytes to fill out current buffer.
            
            assert(self.bufferOffset < [self.buffer length]);
            bytesRead = [self.inputStream read:((uint8_t *) [self.buffer mutableBytes]) + self.bufferOffset maxLength:[self.buffer length] - self.bufferOffset];
            if (bytesRead < 0) {
                assert([self.inputStream streamError] != nil);
                [self finishWithError:[self.inputStream streamError]];
            } else if (bytesRead == 0) {
                [self finishWithError:[NSError errorWithDomain:NSPOSIXErrorDomain code:EPIPE userInfo:nil]];
            } else {
                assert(bytesRead > 0);
                
                // Update the buffer offset and, if we've filled a buffer, process it.
                
                self.bufferOffset += (NSUInteger) bytesRead;
                if (self.bufferOffset == [self.buffer length]) {
                    self.bufferOffset = 0;

                    switch (self.receiveState) {
                        case kFileReceiveOperationStateStart: {
                            assert(NO);
                        } break;
                        case kFileReceiveOperationStateHeader: {
                            [self processHeaderBuffer];
                            [self setupNextReceiveBuffer];
                        } break;
                        case kFileReceiveOperationStateBody: {
                            [self processBodyBuffer];
                            if ( ! [self isFinished] ) {
                                [self setupNextReceiveBuffer];
                            }
                        } break;
                        case kFileReceiveOperationStateTrailer: {
                            [self processTrailerBuffer];
                        } break;
                    }
                }
            }
        } break;
        case NSStreamEventHasSpaceAvailable: {
            assert(NO);
        } break;
        case NSStreamEventErrorOccurred: {
            assert([self.inputStream streamError] != nil);
            [self finishWithError:[self.inputStream streamError]];
        } break;
        case NSStreamEventEndEncountered: {
            assert(NO);
        } break;
        default: {
            assert(NO);
        } break;
    }

    CFRelease( (__bridge CFTypeRef) self );
}

@end
