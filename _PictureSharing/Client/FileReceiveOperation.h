
#import "QRunLoopOperation.h"

@interface FileReceiveOperation : QRunLoopOperation

- (id)initWithInputStream:(NSInputStream *)inputStream;
    // The operation opens /and/ closes the input stream.

// set up by init method

@property (atomic, strong, readonly ) NSInputStream *   inputStream;

// can be changed before operation started

@property (atomic, copy,   readwrite) NSString *        filePath;
    // defaults to nil, which means the data is written to a temporary file

#if ! defined(NDEBUG)

@property (atomic, assign, readwrite) BOOL              debugStallReceive;
@property (atomic, assign, readwrite) BOOL              debugReceiveBadChecksum;

#endif

// valid after operation finished

// error is inherited
@property (atomic, copy,   readonly ) NSString *        finalFilePath;

@end
