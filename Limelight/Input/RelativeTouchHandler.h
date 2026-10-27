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

// Scale both axes by the view's width so a short, wide trackpad moves the cursor
// equally in every direction. Stream views keep the 1280x720 reference instead.
@property (nonatomic) BOOL uniformScaling;

@end

NS_ASSUME_NONNULL_END
