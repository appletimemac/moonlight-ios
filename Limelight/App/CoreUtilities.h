//
//  CoreUtilities.h
//  Moonlight
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Wraps moonlight-common-c macros that Swift cannot import.
@interface CoreUtilities : NSObject

// The richest audio configuration that fits the requested and available channel counts
+ (int)audioConfigurationForRequestedChannels:(int)requested availableChannels:(int)available;

// Blocks while it tests every port against Moonlight's connection test server
+ (unsigned int)testAllPorts;

+ (BOOL)isInconclusiveTestResult:(unsigned int)result;

+ (NSString *)describePortFlags:(unsigned int)portFlags;

@end

NS_ASSUME_NONNULL_END
