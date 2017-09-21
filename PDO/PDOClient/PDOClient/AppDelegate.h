//
//  AppDelegate.h
//  PDOClient
//
//  Created by Bernardo Breder on 08/06/15.
//  Copyright (c) 2015 PDO. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@protocol ChatPeerProtocol

- (void)handleMessage:(NSString*)message from:(NSString*)user;

- (NSString*)name;

- (void)timeout:(NSInteger)timeout;

@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSNetServiceBrowserDelegate, NSNetServiceDelegate>


@end

