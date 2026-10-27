//
//  RelativeTouchHandler.h
//  Moonlight
//
//  Created by Cameron Gutman on 11/1/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//

#import "StreamView.h"

NS_ASSUME_NONNULL_BEGIN

@interface RelativeTouchHandler : UIResponder

-(id)initWithView:(UIView*)view;

// For a trackpad that shares the screen with other controls: both axes scale by the
// view's width (a short, wide pad moves the cursor equally in every direction) and only
// fingers on this view count toward gestures. Stream views keep the 1280x720 reference
// and every touch in the event, as before.
@property (nonatomic) BOOL trackpadSurface;

@end

NS_ASSUME_NONNULL_END
