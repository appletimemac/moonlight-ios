//
//  PanelGamepadView.m
//  Moonlight
//

#import "PanelGamepadView.h"
#import "OnScreenControls.h"

@implementation PanelGamepadView {
    OnScreenControls *_controls;
    CGSize _laidOutSize;
}

- (instancetype)initWithControllerSupport:(ControllerSupport *)controllerSupport
                             streamConfig:(StreamConfiguration *)streamConfig {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.multipleTouchEnabled = YES;
        _controls = [[OnScreenControls alloc] initWithView:self controllerSup:controllerSupport streamConfig:streamConfig];
        _controls.usesFullArea = YES;
        [_controls setLevel:OnScreenControlsLevelFull];
        [_controls show];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!CGSizeEqualToSize(self.bounds.size, _laidOutSize)) {
        _laidOutSize = self.bounds.size;
        [_controls updateLayout];
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [_controls handleTouchDownEvent:touches];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [_controls handleTouchMovedEvent:touches];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [_controls handleTouchUpEvent:touches];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [_controls handleTouchUpEvent:touches];
}

@end
