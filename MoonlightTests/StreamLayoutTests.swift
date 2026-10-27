import CoreGraphics
import Testing
@testable import Moonlight

struct StreamLayoutTests {
    @Test func landscapeUsesTheWholeView() {
        let bounds = CGRect(x: 0, y: 0, width: 951, height: 669)
        let layout = StreamLayout.layout(bounds: bounds, crease: .null)
        #expect(layout.videoFrame == bounds)
        #expect(!layout.isSplit)
    }

    @Test func landscapeIgnoresTheCrease() {
        // Book posture: the crease runs top to bottom through a landscape view
        let bounds = CGRect(x: 0, y: 0, width: 951, height: 669)
        let crease = CGRect(x: 467, y: 0, width: 17, height: 669)
        #expect(!StreamLayout.layout(bounds: bounds, crease: crease).isSplit)
    }

    @Test func portraitWithoutACreaseSplitsAtTheMidline() {
        let layout = StreamLayout.layout(bounds: CGRect(x: 0, y: 0, width: 669, height: 951), crease: .null)
        #expect(layout.videoFrame == CGRect(x: 0, y: 0, width: 669, height: 475))
        #expect(layout.panelFrame == CGRect(x: 0, y: 475, width: 669, height: 476))
    }

    @Test func halfFoldedKeepsBothHalvesOffTheCrease() {
        let crease = CGRect(x: 0, y: 465, width: 669, height: 21)
        let layout = StreamLayout.layout(bounds: CGRect(x: 0, y: 0, width: 669, height: 951), crease: crease)
        #expect(layout.videoFrame.maxY == crease.minY)
        #expect(layout.panelFrame.minY == crease.maxY)
        #expect(layout.panelFrame.maxY == 951)
    }

    @Test func flatCreaseWithNoThicknessStillPlacesTheSplit() {
        let crease = CGRect(x: 0, y: 470, width: 669, height: 0)
        let layout = StreamLayout.layout(bounds: CGRect(x: 0, y: 0, width: 669, height: 951), crease: crease)
        #expect(layout.videoFrame.height == 470)
        #expect(layout.panelFrame.minY == 470)
    }

    @Test func creaseAtTheEdgeCannotCollapseTheVideo() {
        let crease = CGRect(x: 0, y: 0, width: 669, height: 40)
        let layout = StreamLayout.layout(bounds: CGRect(x: 0, y: 0, width: 669, height: 951), crease: crease)
        #expect(layout.videoFrame.height == 475)
    }

    @Test func implausibleCreaseFallsBackToTheMidline() {
        // A region that doesn't span the view's width is not a crease to split at
        let crease = CGRect(x: 0, y: 100, width: 120, height: 40)
        let layout = StreamLayout.layout(bounds: CGRect(x: 0, y: 0, width: 669, height: 951), crease: crease)
        #expect(layout.videoFrame.height == 475)
    }
}

struct StreamResolutionTests {
    @Test func duoOuterDisplayInPortraitStreamsLandscape() {
        let size = StreamResolution.matchingDisplay(points: CGSize(width: 466, height: 678), scale: 3, landscapeOnly: true, maxDimension: 8192)
        #expect(size == PixelSize(width: 2034, height: 1398))
    }

    @Test func dimensionsAreRoundedDownToEvenNumbers() {
        let size = StreamResolution.matchingDisplay(points: CGSize(width: 951, height: 669), scale: 3, landscapeOnly: true, maxDimension: 8192)
        #expect(size == PixelSize(width: 2852, height: 2006))
    }

    @Test func portraitWithoutTheLandscapeLockMatchesTheTopHalf() {
        let size = StreamResolution.matchingDisplay(points: CGSize(width: 834, height: 1194), scale: 2, landscapeOnly: false, maxDimension: 8192)
        #expect(size == PixelSize(width: 1668, height: 1194))
    }

    @Test func oversizedDisplaysScaleDownToTheDecoderLimit() {
        let size = StreamResolution.matchingDisplay(points: CGSize(width: 2560, height: 1440), scale: 2, landscapeOnly: true, maxDimension: 4096)
        #expect(size == PixelSize(width: 4096, height: 2304))
    }
}

struct ApolloAccessTests {
    @Test func laterPairedClientsGetViewAndListOnly() {
        // Apollo's default for every client after the first
        let access = ApolloAccess(mask: 0x3000000)
        #expect(access.missing.map(\.title) == ["Launch Apps", "Controller Input", "Touch Input", "Mouse Input", "Keyboard Input"])
        #expect(access.hasNoInput)
        #expect(!access.canUseClipboard)
    }

    @Test func theFirstPairedClientGetsEverything() {
        let access = ApolloAccess(mask: 0x71F1F00)
        #expect(access.missing.isEmpty)
        #expect(!access.hasNoInput)
        #expect(access.canUseClipboard)
    }

    @Test func clipboardNeedsBothDirections() {
        let readOnly = ApolloAccess(mask: 0x3000000 | 0x20000)
        #expect(!readOnly.canUseClipboard)
    }
}

struct AppPreferencesTests {
    @Test func deviceNameKeyIsTheOneUtilsReads() {
        // Utils.m reads the pairing name under this Objective-C constant
        #expect(AppPreferences.deviceNameKey == "PairingDeviceName")
    }
}
