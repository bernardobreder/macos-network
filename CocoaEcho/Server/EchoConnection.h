

#import <Foundation/Foundation.h>

@interface EchoConnection : NSObject

- (id)initWithInputStream:(NSInputStream *)inputStream outputStream:(NSOutputStream *)outputStream;

@property (nonatomic, strong, readonly ) NSInputStream *    inputStream;
@property (nonatomic, strong, readonly ) NSOutputStream *   outputStream;

- (BOOL)open;
- (void)close;

extern NSString * EchoConnectionDidCloseNotification;
    // This notification is posted when the connection closes, either because you called 
    // -close or because of on-the-wire events (the client closing the connection, a network 
    // error, and so on).

@end
