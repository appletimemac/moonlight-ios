import AVFoundation
import UIKit
import VideoToolbox

struct PixelSize: Equatable, Sendable {
    var width: Int
    var height: Int
}

enum StreamResolution {
    // The stream size for "Match display": the video area in pixels, rounded down to
    // even numbers (4:2:0 video needs even dimensions) and scaled down to fit the
    // decoder's limit. A portrait window either rotates the stream screen to landscape
    // (landscapeOnly) or splits it with the video in the top half (StreamLayout).
    static func matchingDisplay(points: CGSize, scale: CGFloat, landscapeOnly: Bool, maxDimension: Int) -> PixelSize {
        var width = Double(points.width * scale)
        var height = Double(points.height * scale)
        if height > width {
            if landscapeOnly {
                // The iPhone Duo inner display ignores the lock and splits instead, but
                // each half has the same shape as the rotated window
                swap(&width, &height)
            } else {
                height /= 2
            }
        }
        let longest = max(width, height)
        if longest > Double(maxDimension) {
            let factor = Double(maxDimension) / longest
            width *= factor
            height *= factor
        }
        return PixelSize(width: evenFloor(width), height: evenFloor(height))
    }

    private static func evenFloor(_ value: Double) -> Int {
        max(2, Int(value.rounded(.down)) & ~1)
    }
}

@MainActor
enum StreamConfigurationFactory {
    static func make(app: TemporaryApp, host: TemporaryHost, window: UIWindow?) -> StreamConfiguration {
        let settings = DataManager().getSettings()!
        let config = StreamConfiguration()
        config.host = host.activeAddress
        config.httpsPort = host.httpsPort
        config.appID = app.id
        config.appName = app.name
        config.serverCert = host.serverCert

        // Don't stream more frames than the display this window is on can show
        var frameRate = settings.framerate.intValue
        if let maxFrameRate = window?.windowScene?.screen.maximumFramesPerSecond, frameRate > maxFrameRate {
            appLog.info("Clamping FPS to maximum refresh rate: \(maxFrameRate)")
            frameRate = maxFrameRate
        }
        config.frameRate = Int32(frameRate)

        let hevcDecode = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        let size = resolution(settings: settings, window: window, hevcDecode: hevcDecode)
        config.width = Int32(size.width)
        config.height = Int32(size.height)

        config.bitRate = settings.bitrate.int32Value
        config.optimizeGameSettings = settings.optimizeGames
        config.playAudioOnPC = settings.playAudioOnPC
        config.useFramePacing = settings.useFramePacing
        config.swapABXYButtons = settings.swapABXYButtons

        // multiController must be set before calling getConnectedGamepadMask
        config.multiController = settings.multiController
        config.gamepadMask = ControllerSupport.getConnectedGamepadMask(config)

        let availableChannels = AVAudioSession.sharedInstance().maximumOutputNumberOfChannels
        config.audioConfiguration = CoreUtilities.audioConfiguration(
            forRequestedChannels: settings.audioConfig.int32Value,
            availableChannels: Int32(availableChannels))

        config.serverCodecModeSupport = host.serverCodecModeSupport
        config.supportedVideoFormats = videoFormats(settings: settings, size: size, hevcDecode: hevcDecode)

        config.useVirtualDisplay = AppPreferences.useVirtualDisplay
        config.virtualDisplayScale = Int32(AppPreferences.virtualDisplayScale)
        config.supportsClipboard = HostSnapshot(host).apolloAccess?.canUseClipboard ?? false
        return config
    }

    private static func resolution(settings: TemporarySettings, window: UIWindow?, hevcDecode: Bool) -> PixelSize {
        guard AppPreferences.resolutionMode == .matchDisplay, let window else {
            return PixelSize(width: settings.width.intValue, height: settings.height.intValue)
        }
        return StreamResolution.matchingDisplay(
            points: window.bounds.size,
            scale: window.traitCollection.displayScale,
            // Mirrors StreamFrameViewController's supported orientations
            landscapeOnly: window.traitCollection.userInterfaceIdiom == .phone,
            maxDimension: hevcDecode ? 8192 : 4096)
    }

    private static func videoFormats(settings: TemporarySettings, size: PixelSize, hevcDecode: Bool) -> Int32 {
        let av1Decode = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
        var formats: Int32 = 0

        // Each preference falls through to the codecs below it
        let preference = CodecPreference(rawValue: settings.preferredCodec) ?? .automatic
        if preference == .av1, av1Decode {
            formats |= Int32(VIDEO_FORMAT_AV1_MAIN8)
        }
        if preference != .h264, hevcDecode {
            formats |= Int32(VIDEO_FORMAT_H265)
        }
        formats |= Int32(VIDEO_FORMAT_H264)

        // HEVC is required above 4K and for HDR when the hardware can decode it
        let hdr = settings.enableHdr && AVPlayer.eligibleForHDRPlayback
        if (size.width > 4096 || size.height > 4096 || settings.enableHdr) && hevcDecode {
            formats |= Int32(VIDEO_FORMAT_H265)
            if hdr {
                formats |= Int32(VIDEO_FORMAT_H265_MAIN10)
            }
        }
        if formats & Int32(VIDEO_FORMAT_MASK_AV1) != 0, hdr, av1Decode {
            formats |= Int32(VIDEO_FORMAT_AV1_MAIN10)
        }
        return formats
    }
}
