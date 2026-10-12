import Foundation
import ImageIO

extension ImageTools {
    /// When a photo was taken, from its own record (EXIF), within the last day and a half;
    /// nil for older photos or ones without it, which log at the time you add them.
    static func captureDate(of data: Data, now: Date = .now) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let stamp = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let date = formatter.date(from: stamp), date <= now, now.timeIntervalSince(date) < 36 * 3600 else { return nil }
        return date
    }
}
