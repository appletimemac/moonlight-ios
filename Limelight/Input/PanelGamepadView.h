//
//  PanelGamepadView.h
//  Moonlight
//

#import <UIKit/UIKit.h>

@class ControllerSupport;
@class StreamConfiguration;

NS_ASSUME_NONNULL_BEGIN

// The iPhone Duo panel's gamepad: a full set of on-screen controls filling the view
@interface PanelGamepadView : UIView

- (instancetype)initWithControllerSupport:(ControllerSupport *)controllerSupport
                             streamConfig:(StreamConfiguration *)streamConfig;

@end

NS_ASSUME_NONNULL_END
