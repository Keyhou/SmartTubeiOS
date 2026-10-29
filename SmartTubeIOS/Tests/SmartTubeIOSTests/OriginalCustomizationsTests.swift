import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("Original customizations")
struct OriginalCustomizationsTests {

    @Test func availableSpeedsIncludes16And185() {
        #expect(AppSettings.availableSpeeds == [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.6, 1.75, 1.85, 2.0])
        #expect(!AppSettings.availableSpeeds.contains(1.7))
    }

    @Test func playbackSpeed17MigratesTo16() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"playbackSpeed":1.7}"#.utf8))
        #expect(abs(decoded.playbackSpeed - 1.6) < 0.001)
        let channelOnly = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(
                #"{"playbackSpeed":1.0,"channelPlaybackPreferences":{"UC1":{"speed":1.7}}}"#.utf8))
        #expect(abs((channelOnly.channelPlaybackPreferences["UC1"]?.speed ?? 0) - 1.7) < 0.001)
    }

    @Test func qualityPickerKeepsAV1FourKWhenHLSStopsAt1080() {
        let av1 = format(height: 2160, mime: #"video/mp4; codecs="av01.0.12M.08""#, url: "https://example.com/av1.mp4")
        let hd = format(height: 1080, mime: #"video/mp4; codecs="avc1.640028""#, url: "https://example.com/hd.mp4")
        let rows = qualityPickerFormats(formats: [hd, av1], hlsHeights: [1080, 720])
        #expect(rows.contains { $0.height == 2160 && $0.mimeType.contains("av01") })
    }

    @Test func qualityPickerSynthesizesHLSFourKRow() {
        let hd = format(height: 1080, mime: "application/vnd.apple.mpegurl", url: nil)
        let rows = qualityPickerFormats(formats: [hd], hlsHeights: [2160, 1080])
        #expect(
            rows.contains {
                $0.height == 2160 && $0.mimeType == "application/vnd.apple.mpegurl" && $0.url == nil
            })
    }

    @Test func qualityPickerKeepsPlainMP4FourK() {
        let plain = format(height: 2160, mime: "video/mp4", url: "https://example.com/plain.mp4")
        let rows = qualityPickerFormats(formats: [plain], hlsHeights: [1080])
        #expect(rows.contains { $0.height == 2160 && $0.mimeType == "video/mp4" })
        #expect(shouldReloadUHDOutsideHLS(plain, hlsHeights: [1080]))
    }

    @Test func appendingFormatsMergesNewURLs() {
        let first = format(height: 1080, mime: "video/mp4", url: "https://example.com/a.mp4")
        let duplicate = format(height: 720, mime: "video/mp4", url: "https://example.com/a.mp4")
        let added = format(height: 2160, mime: "video/mp4", url: "https://example.com/b.mp4")
        let info = PlayerInfo(
            video: Video(id: "vid", title: "Title", channelTitle: "Channel"),
            formats: [first],
            hlsURL: nil,
            dashURL: nil,
            captionTracks: [],
            trackingURLs: nil,
            endCards: []
        )
        let merged = info.appendingFormats([duplicate, added])
        #expect(merged.formats.count == 2)
        #expect(merged.formats.contains { $0.url?.absoluteString == "https://example.com/b.mp4" })
    }

    @Test func percentDurationWatchedParsesJSONNumbers() throws {
        let object = try jsonObject(#"{"int":45,"double":45.0,"fraction":0.45,"full":1}"#)
        #expect(parsePercentDurationWatched(object["int"]) == 0.45)
        #expect(parsePercentDurationWatched(object["double"]) == 0.45)
        #expect(parsePercentDurationWatched(object["fraction"]) == 0.45)
        #expect(parsePercentDurationWatched(object["full"]) == 1)
    }

    @Test func resumePositionPrefersFurtherProgress() {
        #expect(playbackResumePosition(localSeconds: 30, youtubeFraction: 0.5, duration: 200) == 100)
        #expect(playbackResumePosition(localSeconds: 80, youtubeFraction: 0.2, duration: 200) == 80)
        #expect(playbackResumePosition(localSeconds: 3, youtubeFraction: 0.01, duration: 200) == nil)
        #expect(playbackResumePosition(localSeconds: nil, youtubeFraction: 1, duration: 200) == nil)
    }

    @Test func tileRendererParsesIntegerPercentWatched() async throws {
        let payload = try jsonObject(
            """
            {
              "contents": {
                "sectionListRenderer": {
                  "contents": [{
                    "itemSectionRenderer": {
                      "contents": [{
                        "tileRenderer": {
                          "contentType": "TILE_CONTENT_TYPE_VIDEO",
                          "onSelectCommand": {"watchEndpoint": {"videoId": "abcdefghijk"}},
                          "metadata": {"tileMetadataRenderer": {"title": {"simpleText": "Watched"}}},
                          "header": {
                            "tileHeaderRenderer": {
                              "thumbnailOverlays": [{
                                "thumbnailOverlayResumePlaybackRenderer": {"percentDurationWatched": 45}
                              }]
                            }
                          }
                        }
                      }]
                    }
                  }]
                }
              }
            }
            """)
        let group = try await InnerTubeAPI().parseVideoGroupForTesting(payload, title: "Home")
        #expect(group.videos.first?.watchProgress == 0.45)
    }

    @Test func channelPlaybackPreferencesOverrideGlobal() {
        var settings = AppSettings()
        settings.playbackSpeed = 1.25
        settings.setPlaybackSpeed(1.6, forChannel: "UC1")
        #expect(settings.playbackSpeed == 1.25)
        #expect(settings.resolvedPlaybackSpeed(for: "UC1") == 1.6)
        #expect(settings.resolvedPlaybackSpeed(for: "other") == 1.25)
        #expect(settings.resolvedPlaybackSpeed(for: nil) == 1.25)
    }

    @Test func channelCaptionsOffDoesNotInheritGlobal() {
        var settings = AppSettings()
        settings.preferredCaptionLanguage = "en"
        settings.setCaptionLanguage(nil, forChannel: "UC1")
        #expect(settings.resolvedCaptionLanguage(for: "UC1") == nil)
        #expect(settings.preferredCaptionLanguage == "en")
        #expect(settings.resolvedCaptionLanguage(for: "other") == "en")
    }

    @Test func channelPlaybackPreferencesRoundTrip() throws {
        var settings = AppSettings()
        settings.setPlaybackSpeed(1.85, forChannel: "UC1")
        settings.setCaptionLanguage("fr", forChannel: "UC1")
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.channelPlaybackPreferences["UC1"]?.speed == 1.85)
        #expect(decoded.channelPlaybackPreferences["UC1"]?.captionLanguage == "fr")
        #expect(decoded.channelPlaybackPreferences["UC1"]?.captionsOff == false)
        #expect(decoded.resolvedPlaybackSpeed(for: "UC1") == 1.85)
        #expect(decoded.resolvedCaptionLanguage(for: "UC1") == "fr")
    }

    @Test func visionOSPickerKeepsUHDMP4() {
        let policy = HLSPlaybackPolicy.resolve(label: "VisionOS/HLS", isHLS: true)
        let uhd = format(height: 2160, mime: #"video/mp4; codecs="av01.0.13M.08""#, url: "https://example.com/uhd.mp4")
        let rows = qualityPickerFormats(formats: [uhd], hlsHeights: [1080])
        #expect(rows.contains { $0.height == 2160 })
        #expect(!policy.allowsFormat(height: 2160, mimeType: uhd.mimeType))
        #expect(policy.maximumHeight == 1080)
        #expect(policy.requiresH264)
    }
}

@MainActor
@Suite("Play/pause debounce")
struct TogglePlayPauseDebounceTests {

    @Test func secondCallWithinWindowIsIgnored() {
        let vm = PlaybackViewModel()
        vm.togglePlayPause()
        let playing = vm.isPlaying
        vm.togglePlayPause()
        #expect(vm.isPlaying == playing)
    }

    @Test func callAfterWindowApplies() {
        let vm = PlaybackViewModel()
        vm.togglePlayPause()
        let playing = vm.isPlaying
        vm.lastTogglePlayPauseTime = .distantPast
        vm.togglePlayPause()
        #expect(vm.isPlaying != playing)
    }
}

private func format(height: Int, mime: String, url: String?) -> VideoFormat {
    VideoFormat(
        label: "\(height)p",
        width: height * 16 / 9,
        height: height,
        fps: 30,
        mimeType: mime,
        url: url.flatMap { URL(string: $0) }
    )
}

private func jsonObject(_ text: String) throws -> [String: Any] {
    let data = Data(text.utf8)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}
