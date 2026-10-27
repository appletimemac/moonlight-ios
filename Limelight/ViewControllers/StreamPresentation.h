//
//  StreamPresentation.h
//  Moonlight
//

#import <UIKit/UIKit.h>

@class StreamConfiguration;

NS_ASSUME_NONNULL_BEGIN

// Lets Swift create the stream screen without importing StreamFrameViewController.h,
// which pulls in the generated Swift header and would form an import cycle.
@interface StreamPresentation : NSObject

+ (UIViewController *)streamViewControllerWithConfiguration:(StreamConfiguration *)configuration
                                                exitHandler:(void (^)(void))exitHandler;

@end

NS_ASSUME_NONNULL_END
