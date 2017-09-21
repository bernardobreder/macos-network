
#import <Foundation/Foundation.h>

@interface EchoServer : NSObject

@property (nonatomic, assign, readonly ) NSUInteger     port;   // the actual port bound to, valid after -start

- (BOOL)start;
- (void)stop;

@end
