//
//  main.m
//  PDOServer
//
//  Created by Bernardo Breder on 08/06/15.
//  Copyright (c) 2015 PDO. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol ChatPeerProtocol

- (void)handleMessage:(NSString*)message from:(NSString*)user;

- (NSString*)name;

- (void)timeout:(NSInteger)timeout;

@end

@interface PDOServer : NSObject <ChatPeerProtocol, NSNetServiceDelegate>

@property (nonatomic, strong, readonly) NSString *name;

- (void)start;

@end

@interface PDOServer ()

@property (strong) NSNetService *service;

@end

@implementation PDOServer

- (void)start
{
    NSString *serviceName = @"LocalNetChat/PDO";
    _name = NSFullUserName();
    NSPort *port = [[NSSocketPort alloc] init];
    NSConnection *conn = [NSConnection connectionWithReceivePort:port sendPort:nil];
    conn.rootObject = self;
    if ([conn registerName:serviceName withNameServer:NSSocketPortNameServer.sharedInstance]) {
        _service = [[NSNetService alloc] initWithDomain:@"" type:@"_localpdo._tcp." name:serviceName port:52638];
        _service.delegate = self;
        [_service publish];
    }
}

/* Sent to the NSNetService instance's delegate prior to advertising the service on the network. If for some reason the service cannot be published, the delegate will not receive this message, and an error will be delivered to the delegate via the delegate's -netService:didNotPublish: method.
 */
- (void)netServiceWillPublish:(NSNetService *)sender
{
    NSLog(@"netServiceWillPublish");
}

/* Sent to the NSNetService instance's delegate when the publication of the instance is complete and successful.
 */
- (void)netServiceDidPublish:(NSNetService *)sender
{
    NSLog(@"netServiceDidPublish");
}

/* Sent to the NSNetService instance's delegate when an error in publishing the instance occurs. The error dictionary will contain two key/value pairs representing the error domain and code (see the NSNetServicesError enumeration above for error code constants). It is possible for an error to occur after a successful publication.
 */
- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict
{
    NSLog(@"netServiceDidNotPublish");
}

/* Sent to the NSNetService instance's delegate prior to resolving a service on the network. If for some reason the resolution cannot occur, the delegate will not receive this message, and an error will be delivered to the delegate via the delegate's -netService:didNotResolve: method.
 */
- (void)netServiceWillResolve:(NSNetService *)sender
{
    NSLog(@"netServiceWillResolve");
}

/* Sent to the NSNetService instance's delegate when one or more addresses have been resolved for an NSNetService instance. Some NSNetService methods will return different results before and after a successful resolution. An NSNetService instance may get resolved more than once; truly robust clients may wish to resolve again after an error, or to resolve more than once.
 */
- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
    NSLog(@"netServiceDidResolveAddress");
}

/* Sent to the NSNetService instance's delegate when an error in resolving the instance occurs. The error dictionary will contain two key/value pairs representing the error domain and code (see the NSNetServicesError enumeration above for error code constants).
 */
- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict
{
    NSLog(@"netServiceDidNotResolve");
}

/* Sent to the NSNetService instance's delegate when the instance's previously running publication or resolution request has stopped.
 */
- (void)netServiceDidStop:(NSNetService *)sender
{
    NSLog(@"netServiceDidStop");
}

- (void)handleMessage:(NSString*)message from:(NSString*)user
{
    NSLog(@"handleMessage:from:");
}

- (void)timeout:(NSInteger)timeout
{
    NSLog(@"timeout:");
}

@end

int main(int argc, const char * argv[]) {
    PDOServer *server = [[PDOServer alloc] init];
    [server start];
    [[NSRunLoop currentRunLoop] run];
    return 0;
}
