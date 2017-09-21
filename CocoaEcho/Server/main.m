

#import "EchoServer.h"

int main(const int argc, const char **argv) {
    #pragma unused(argc)
    #pragma unused(argv)
    @autoreleasepool {
        EchoServer * server = [[EchoServer alloc] init];
        if ( [server start] ) {
            NSLog(@"Started server on port %zu.", (size_t) [server port]);
            [[NSRunLoop currentRunLoop] run];
        } else {
            NSLog(@"Error starting server");
        }
    }
    return EXIT_SUCCESS;
}
