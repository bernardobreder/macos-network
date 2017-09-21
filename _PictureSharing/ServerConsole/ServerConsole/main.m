//
//  main.m
//  ServerConsole
//
//  Created by Bernardo Breder on 08/06/15.
//  Copyright (c) 2015 PDO. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <sys/socket.h>
#include <netinet/in.h>

@interface Server : NSObject <NSNetServiceDelegate>

@property (strong) NSNetService *netService;

@end

@interface Server () {
    CFSocketRef _listeningSocket;
}

@end

@implementation Server

- (instancetype)init
{
    if (!(self = [super init])) return nil;
    int err, chosenPort = -1;
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
    CFSocketContext context = {0, NULL, NULL, NULL, NULL};
    _listeningSocket = CFSocketCreateWithNative(NULL, fdForListening, kCFSocketAcceptCallBack, nil, &context);
    if (!_listeningSocket) { close(fdForListening); return false; }
    CFRunLoopSourceRef rls = CFSocketCreateRunLoopSource(NULL, _listeningSocket, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);
    CFRelease(rls);
    _netService = [[NSNetService alloc] initWithDomain:@"" type:@"_wwdcpic2._tcp." name:@"ServiceName" port:chosenPort];
    if (!_netService) { return false; }
    _netService.delegate = self;
    [_netService publish];
    return self;
}

@end

int main(int argc, const char * argv[]) {
    Server *server = [[Server alloc] init];
    [NSRunLoop.currentRunLoop run];
    return 0;
}
