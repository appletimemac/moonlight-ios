//
//  CoreUtilities.m
//  Moonlight
//

#import "CoreUtilities.h"
#import "Connection.h"

#include <Limelight.h>

@implementation CoreUtilities

+ (int)audioConfigurationForRequestedChannels:(int)requested availableChannels:(int)available {
    int channels = MIN(requested, available);
    if (channels >= 8) {
        return AUDIO_CONFIGURATION_71_SURROUND;
    }
    else if (channels >= 6) {
        return AUDIO_CONFIGURATION_51_SURROUND;
    }
    return AUDIO_CONFIGURATION_STEREO;
}

+ (unsigned int)testAllPorts {
    return LiTestClientConnectivity(CONN_TEST_SERVER, 443, ML_PORT_FLAG_ALL);
}

+ (BOOL)isInconclusiveTestResult:(unsigned int)result {
    return result == ML_TEST_RESULT_INCONCLUSIVE;
}

+ (NSString *)describePortFlags:(unsigned int)portFlags {
    char ports[512];
    LiStringifyPortFlags(portFlags, "\n", ports, sizeof(ports));
    return [NSString stringWithUTF8String:ports];
}

@end
