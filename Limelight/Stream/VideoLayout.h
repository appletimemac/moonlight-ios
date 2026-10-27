//
//  VideoLayout.h
//  Moonlight
//

#import <CoreGraphics/CoreGraphics.h>

// The largest rect with the stream's aspect ratio, centered in a view's bounds.
// The renderer, touch mapping and pointer region must agree on it exactly, so all
// of them use this. It mimics AVLayerVideoGravityResizeAspect without honoring
// the PAR in the SPS, which would skew video-relative touch locations.
static inline CGRect VideoRectInBounds(CGRect bounds, float streamAspectRatio) {
    CGSize size;
    if (bounds.size.width > bounds.size.height * streamAspectRatio) {
        size = CGSizeMake(bounds.size.height * streamAspectRatio, bounds.size.height);
    } else {
        size = CGSizeMake(bounds.size.width, bounds.size.width / streamAspectRatio);
    }
    return CGRectMake(bounds.size.width / 2 - size.width / 2,
                      bounds.size.height / 2 - size.height / 2,
                      size.width, size.height);
}
