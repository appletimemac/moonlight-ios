//
//  StreamPresentation.m
//  Moonlight
//

#import "StreamPresentation.h"
#import "StreamFrameViewController.h"

@implementation StreamPresentation

+ (UIViewController *)streamViewControllerWithConfiguration:(StreamConfiguration *)configuration
                                                exitHandler:(void (^)(StreamExitAction action))exitHandler {
    StreamFrameViewController *streamFrame = [[StreamFrameViewController alloc] init];
    streamFrame.streamConfig = configuration;
    streamFrame.exitHandler = exitHandler;
    streamFrame.modalPresentationStyle = UIModalPresentationFullScreen;
    streamFrame.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    return streamFrame;
}

@end
