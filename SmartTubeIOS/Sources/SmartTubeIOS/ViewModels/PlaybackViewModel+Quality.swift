import AVFoundation
import SmartTubeIOSCore
import os

private let qualityLog = CrashlyticsLogger(category: "Quality")

// MARK: - Stream Format / HLS Quality Selection (thin wrapper — logic lives in PlaybackQualityManager)

extension PlaybackViewModel {

    public func selectFormat(_ format: VideoFormat?) {
        if let fmt = format {
            qualityLog.notice(
                "[quality] selectFormat → \(fmt.qualityLabel) (\(fmt.codecShortLabel)) \(fmt.width)×\(fmt.height)@\(fmt.fps)fps"
            )
        } else {
            qualityLog.notice("[quality] selectFormat → Auto (clearing selectedFormat)")
        }
        qualityManager.selectFormat(format)
        // Refresh Stats for Nerds immediately so the overlay shows the new quality
        // without waiting for the next periodic-observer tick (which may not fire
        // while the player is loading the replacement item).
        if statsForNerdsVisible { updateStatsSnapshot() }
    }

    /// Quality cap for recovery/stream-selection paths: the per-video pick when
    /// one exists, otherwise the persisted default (`settings.preferredQuality`).
    var effectiveQuality: AppSettings.VideoQuality {
        qualityManager.effectiveQuality
    }

    func reloadHLSItem(seekTo time: TimeInterval, quality: AppSettings.VideoQuality) async {
        await qualityManager.reloadHLSItem(seekTo: time, quality: quality)
    }

    func fetchHLSVariantURLs(url: URL) async -> [Int: URL] {
        await qualityManager.fetchHLSVariantURLs(url: url)
    }

    static func deduplicatedVideoFormats(_ formats: [VideoFormat]) -> [VideoFormat] {
        PlaybackQualityManager.deduplicatedVideoFormats(formats)
    }

    func peakBitRate(for height: Int) -> Double {
        qualityManager.peakBitRate(for: height)
    }

    func reloadHLSItemH264Capped(seekTo time: TimeInterval) async {
        await qualityManager.reloadHLSItemH264Capped(seekTo: time)
    }

    /// After visionOS H.264 HLS (capped at 1080p) is already playing, add rqh-free
    /// 1440p/2160p MP4 rows from Android VR without replacing the current item.
    func enrichPickerWithUHDFormats(for videoId: String) async {
        do {
            let info = try await api.fetchPlayerInfoAndroidVR(videoId: videoId)
            guard currentVideo?.id == videoId else { return }
            let extras = info.formats.filter { format in
                guard format.isUHDPlayableOutsideHLS, let url = format.url else { return false }
                return !PlaybackQualityManager.urlHasRqhEnforcement(url)
            }
            guard !extras.isEmpty else { return }
            let heights = Set(hlsVariantURLs.keys).union(availableFormats.map(\.height))
            availableFormats = qualityPickerFormats(formats: availableFormats + extras, hlsHeights: heights)
            qualityLog.notice("[uhd] picker enriched with \(extras.count) Android VR formats")
        } catch {
            qualityLog.notice("[uhd] Android VR picker enrichment failed — leaving the picker unchanged")
        }
    }
}
