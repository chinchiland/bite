import CoreImage
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
        var hasher = Hasher()
        hasher.combine(data.count)
        hasher.combine(data.prefix(96))
        hasher.combine(data.suffix(96))
        let key = "\(hasher.finalize())-\(Int(points * scale))" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        let pixels = (max(points * scale, 1) * aspect(of: data)).rounded()
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

    private static let softener = CIContext()

    /// A small copy, already blurred, for where a photo melts into the page: drawn scaled up it
    /// looks the same as blurring the full photo, and costs nothing while you scroll.
    static func softened(_ data: Data, maxPixel: CGFloat = 140, sigma: Double = 3) -> UIImage? {
        guard let small = downsample(data, maxPixel: maxPixel), let cgImage = small.cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: input.extent)
        guard let output = softener.createCGImage(blurred, from: input.extent) else { return small }
        return UIImage(cgImage: output)
    }

    /// An image already in memory, brought down to at most `maxPixel` on the long side.
    static func fitted(_ image: UIImage, maxPixel: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height) * image.scale
        guard longest > maxPixel, longest > 0 else { return image }
        let factor = maxPixel / longest
        let size = CGSize(width: image.size.width * image.scale * factor, height: image.size.height * image.scale * factor)
        return image.preparingThumbnail(of: size) ?? image
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
