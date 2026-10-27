//
//  PanelTrackpadView.m
//  Moonlight
//

#import "PanelTrackpadView.h"
#import "RelativeTouchHandler.h"

@implementation PanelTrackpadView {
    RelativeTouchHandler *_touchHandler;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.multipleTouchEnabled = YES;
        _touchHandler = [[RelativeTouchHandler alloc] initWithView:self];
        _touchHandler.uniformScaling = YES;
    }
    return self;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [_touchHandler touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [_touchHandler touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [_touchHandler touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [_touchHandler touchesCancelled:touches withEvent:event];
}

@end
