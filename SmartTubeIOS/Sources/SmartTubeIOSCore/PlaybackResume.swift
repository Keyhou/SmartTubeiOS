import Foundation

// MARK: - Watch progress

/// Interprets an InnerTube `percentDurationWatched` value.
///
/// Numbers greater than 1 are percents (`45`, `45.0` → 0.45). Numbers in 0...1 are
/// already fractions. A raw `1` stays 1.0 (100%) and is then dropped by the resume cutoff.
public func parsePercentDurationWatched(_ raw: Any?) -> Double? {
    let number: Double
    if let value = raw as? Double {
        number = value
    } else if let value = raw as? Int {
        number = Double(value)
    } else if let value = raw as? NSNumber {
        number = value.doubleValue
    } else {
        return nil
    }
    if number > 1 {
        return number / 100
    }
    return number
}

/// The further of the local playhead and YouTube's watched fraction, when that
/// position is already past 5 seconds. `nil` starts playback at the beginning.
public func playbackResumePosition(
    localSeconds: TimeInterval?,
    youtubeFraction: Double?,
    duration: TimeInterval
) -> TimeInterval? {
    var best: TimeInterval = 0
    if let localSeconds, localSeconds > 5 {
        best = localSeconds
    }
    if let youtubeFraction, youtubeFraction > 0.02, youtubeFraction < 0.95, duration > 0 {
        let fromYouTube = youtubeFraction * duration
        if fromYouTube > 5 {
            best = max(best, fromYouTube)
        }
    }
    return best > 5 ? best : nil
}
