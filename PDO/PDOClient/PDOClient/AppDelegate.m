//
//  AppDelegate.m
//  PDOClient
//
//  Created by Bernardo Breder on 08/06/15.
//  Copyright (c) 2015 PDO. All rights reserved.
//

#import "AppDelegate.h"

@interface AppDelegate ()

@property (strong) IBOutlet NSWindow *window;

@property (strong) NSNetServiceBrowser *serviceBrowser;

@property (strong) NSMutableArray *peers;

@property (strong) NSOperationQueue *queue;

@property (strong, readonly) NSMutableSet *pendingServices;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    _peers = [[NSMutableArray alloc] init];
    _pendingServices = [[NSMutableSet alloc] init];
    _queue = [[NSOperationQueue alloc] init];
    _serviceBrowser = [[NSNetServiceBrowser alloc] init];
    _serviceBrowser.delegate = self;
    [_serviceBrowser searchForServicesOfType:@"_localpdo._tcp." inDomain:@""];
//    [_queue addOperationWithBlock:^() {
//        [NSThread sleepForTimeInterval:5];
//        [self sendMessage:@"Hello"];
//        [NSOperationQueue.mainQueue addOperationWithBlock:^() {
//            NSAlert *alert = [[NSAlert alloc] init];
//            alert.messageText = @"Sended";
//            [alert runModal];
//        }];
//    }];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    [_pendingServices removeAllObjects];
    _serviceBrowser.delegate = nil;
    [_serviceBrowser stop];
    _serviceBrowser = nil;
}

#pragma mark NSNetServiceBrowser

/* Sent to the NSNetServiceBrowser instance's delegate before the instance begins a search. The delegate will not receive this message if the instance is unable to begin a search. Instead, the delegate will receive the -netServiceBrowser:didNotSearch: message.
 */
- (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)aNetServiceBrowser
{
    NSLog(@"%@", NSStringFromSelector(@selector(netServiceBrowserWillSearch:)));
}

/* Sent to the NSNetServiceBrowser instance's delegate when the instance's previous running search request has stopped.
 */
- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)aNetServiceBrowser
{
    NSLog(@"%@", NSStringFromSelector(@selector(netServiceBrowserDidStopSearch:)));
}

/* Sent to the NSNetServiceBrowser instance's delegate when an error in searching for domains or services has occurred. The error dictionary will contain two key/value pairs representing the error domain and code (see the NSNetServicesError enumeration above for error code constants). It is possible for an error to occur after a search has been started successfully.
 */
- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didNotSearch:(NSDictionary *)errorDict
{
    NSLog(@"%@", NSStringFromSelector(@selector(netServiceBrowser:didNotSearch:)));
}

/* Sent to the NSNetServiceBrowser instance's delegate for each domain discovered. If there are more domains, moreComing will be YES. If for some reason handling discovered domains requires significant processing, accumulating domains until moreComing is NO and then doing the processing in bulk fashion may be desirable.
 */
- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindDomain:(NSString *)domainString moreComing:(BOOL)moreComing
{
    NSLog(@"%@", NSStringFromSelector(@selector(netServiceBrowser:didFindDomain:moreComing:)));
}

/* Sent to the NSNetServiceBrowser instance's delegate for each service discovered. If there are more services, moreComing will be YES. If for some reason handling discovered services requires significant processing, accumulating services until moreComing is NO and then doing the processing in bulk fashion may be desirable.
 */
- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreComing
{
    NSLog(@"%@", NSStringFromSelector(@selector(netServiceBrowser:didFindService:moreComing:)));
    aNetService.delegate = self;
    [aNetService resolveWithTimeout:10];
    [_pendingServices addObject:aNetService];
}

/* Sent to the NSNetServiceBrowser instance's delegate when a previously discovered domain is no longer available.
 */
- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveDomain:(NSString *)domainString moreComing:(BOOL)moreComing
{
    NSLog(@"%@", NSStringFromSelector(@selector(netServiceBrowser:didRemoveDomain:moreComing:)));
}

/* Sent to the NSNetServiceBrowser instance's delegate when a previously discovered service is no longer published.
 */
- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveService:(NSNetService *)aNetService moreComing:(BOOL)moreComing
{
    NSLog(@"%@", NSStringFromSelector(@selector(netServiceBrowser:didRemoveService:moreComing:)));
    [_pendingServices removeObject:aNetService];
}

#pragma mark NSNetServiceDelegate

/* Sent to the NSNetService instance's delegate prior to advertising the service on the network. If for some reason the service cannot be published, the delegate will not receive this message, and an error will be delivered to the delegate via the delegate's -netService:didNotPublish: method.
 */
- (void)netServiceWillPublish:(NSNetService *)sender
{
    NSLog(@"%@", NSStringFromSelector(@selector(netServiceWillPublish:)));
}

/* Sent to the NSNetService instance's delegate when the publication of the instance is complete and successful.
 */
- (void)netServiceDidPublish:(NSNetService *)sender
{
    NSLog(@"%@", NSStringFromSelector(@selector(netServiceDidPublish:)));
}

/* Sent to the NSNetService instance's delegate when an error in publishing the instance occurs. The error dictionary will contain two key/value pairs representing the error domain and code (see the NSNetServicesError enumeration above for error code constants). It is possible for an error to occur after a successful publication.
 */
- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict
{
    NSLog(@"%@", NSStringFromSelector(@selector(netService:didNotPublish:)));
}

/* Sent to the NSNetService instance's delegate prior to resolving a service on the network. If for some reason the resolution cannot occur, the delegate will not receive this message, and an error will be delivered to the delegate via the delegate's -netService:didNotResolve: method.
 */
- (void)netServiceWillResolve:(NSNetService *)netService
{
    NSLog(@"%@", NSStringFromSelector(@selector(netServiceWillResolve:)));
}

/* Sent to the NSNetService instance's delegate when one or more addresses have been resolved for an NSNetService instance. Some NSNetService methods will return different results before and after a successful resolution. An NSNetService instance may get resolved more than once; truly robust clients may wish to resolve again after an error, or to resolve more than once.
 */
- (void)netServiceDidResolveAddress:(NSNetService *)netService
{
    NSLog(@"%@", NSStringFromSelector(@selector(netServiceDidResolveAddress:)));
    NSString *host = netService.hostName;
    NSString *serviceName = netService.name;
    NSSocketPortNameServer *nameServer = NSSocketPortNameServer.sharedInstance;
    id peer = [NSConnection rootProxyForConnectionWithRegisteredName:serviceName host:host usingNameServer:nameServer];
    if (peer) {
        [peer setProtocolForProxy:@protocol(ChatPeerProtocol)];
        [_peers addObject:[NSDictionary dictionaryWithObjectsAndKeys:peer, @"peer", [peer name], @"name", nil]];
        [[peer connectionForProxy] setReplyTimeout:5];
    }
}

/* Sent to the NSNetService instance's delegate when an error in resolving the instance occurs. The error dictionary will contain two key/value pairs representing the error domain and code (see the NSNetServicesError enumeration above for error code constants).
 */
- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict
{
    NSLog(@"%@", NSStringFromSelector(@selector(netService:didNotResolve:)));
}

/* Sent to the NSNetService instance's delegate when the instance's previously running publication or resolution request has stopped.
 */
- (void)netServiceDidStop:(NSNetService *)sender
{
    NSLog(@"%@", NSStringFromSelector(@selector(netServiceDidStop:)));
}

- (void)sendMessage:(NSString*)message
{
    if ([@"" isEqualToString:message]) return;
    if (_peers.count == 0) return;
    NSMutableIndexSet *failedPeers = [[NSMutableIndexSet alloc] init];
    for (NSInteger i = 0 ; i < _peers.count ; i++) {
        NSDictionary *dict = _peers[i];
        id<ChatPeerProtocol> peer = dict[@"peer"];
        @try {
            [peer handleMessage:message from:NSFullUserName()];
        } @catch (NSException *e) {
            [failedPeers addIndex:i];
        }
    }
    if (failedPeers.count > 0) {
        [_peers removeObjectsAtIndexes:failedPeers];
    }
}


@end
