//
//  StreamPresentation.h
//  Moonlight
//

#import <UIKit/UIKit.h>

@class StreamConfiguration;

NS_ASSUME_NONNULL_BEGIN

// What the user asked for when leaving the stream screen
typedef NS_ENUM(NSInteger, StreamExitAction) {
    StreamExitActionDisconnect,
    StreamExitActionQuitApp,
    // Quit and relaunch the app so the host matches the display the stream is on now
    StreamExitActionRestartToFit,
};

// Lets Swift create the stream screen without importing StreamFrameViewController.h,
// which pulls in the generated Swift header and would form an import cycle.
@interface StreamPresentation : NSObject

+ (UIViewController *)streamViewControllerWithConfiguration:(StreamConfiguration *)configuration
                                                exitHandler:(void (^)(StreamExitAction action))exitHandler;

@end

NS_ASSUME_NONNULL_END
