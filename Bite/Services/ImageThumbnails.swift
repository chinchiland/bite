import ImageIO
import UIKit

extension ImageTools {
    private static let thumbnails: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        return cache
    }()

    /// A photo decoded at the size it is shown: a 76 point tile needs about 230 pixels, not a
    /// 1000 pixel plate. Cached, so a list never decodes the same photo twice.
    static func thumbnail(_ data: Data, points: CGFloat, scale: CGFloat = 3) -> UIImage? {
        let pixels = (max(points * scale, 1) * aspect(of: data)).rounded()
        var hasher = Hasher()
        hasher.combine(data.count)
        hasher.combine(data.prefix(96))
        hasher.combine(data.suffix(96))
        let key = "\(hasher.finalize())-\(Int(pixels))" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let image = downsample(data, maxPixel: pixels) else { return nil }
        thumbnails.setObject(image, forKey: key)
        return image
    }

    /// Long side over short side, read from the file's header without decoding it. 1 when
    /// the header has no size.
    private static func aspect(of data: Data) -> CGFloat {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return 1 }
        return CGFloat(min(max(width, height) / min(width, height), 3))
    }

    /// Decodes at most `maxPixel` on the long side, turned the right way up.
    static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: image)
    }
}
