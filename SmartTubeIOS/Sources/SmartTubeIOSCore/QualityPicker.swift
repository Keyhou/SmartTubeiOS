import Foundation

extension VideoFormat {
    /// 1440p+ MP4 with a direct URL. These stay in the quality picker when the HLS
    /// master does not list that height, and play through DASH instead of HLS.
    public var isUHDPlayableOutsideHLS: Bool {
        height >= 1440 && url != nil && mimeType.hasPrefix("video/mp4") && !mimeType.contains(", ")
    }
}

/// Quality-picker rows after an HLS master has been parsed.
///
/// Keeps formats whose height the master lists, keeps 1440p+ MP4 rows that have a URL,
/// and synthesizes a row for any master height the adaptive formats omitted. Highest first.
/// Duplicate height + MIME pairs are dropped.
public func qualityPickerFormats(formats: [VideoFormat], hlsHeights: Set<Int>) -> [VideoFormat] {
    var kept: [VideoFormat] = []
    var seen = Set<String>()

    func add(_ format: VideoFormat) {
        let key = "\(format.height)|\(format.mimeType)"
        guard seen.insert(key).inserted else { return }
        kept.append(format)
    }

    for format in formats where hlsHeights.contains(format.height) || format.isUHDPlayableOutsideHLS {
        add(format)
    }

    let presentHeights = Set(kept.map(\.height))
    for height in hlsHeights where !presentHeights.contains(height) {
        add(
            VideoFormat(
                label: "\(height)p",
                width: height * 16 / 9,
                height: height,
                fps: 30,
                mimeType: "application/vnd.apple.mpegurl",
                url: nil
            ))
    }

    return kept.sorted { $0.height > $1.height }
}

/// True when choosing this row must reload a DASH/MP4 item instead of steering HLS ABR.
public func shouldReloadUHDOutsideHLS(_ format: VideoFormat, hlsHeights: Set<Int>) -> Bool {
    !hlsHeights.contains(format.height) && format.isUHDPlayableOutsideHLS
}
