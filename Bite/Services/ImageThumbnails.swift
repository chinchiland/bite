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

    // No working color space: the room is worked out on the numbers the photo is stored in,
    // so `RoomTone`'s brightness means what the eye sees, not light in linear units.
    private static let roomContext = CIContext(options: [.workingColorSpace: NSNull()])

    private static let rooms: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 24
        return cache
    }()

    /// A photo as a room to stand in: its colors richer, blurred until only the color is left,
    /// and dimmed to the one depth every room shares. Small, and scaled up on screen, so it
    /// costs nothing behind a page that scrolls. Cached by photo.
    static func room(_ data: Data) -> UIImage? {
        var hasher = Hasher()
        hasher.combine(data.count)
        hasher.combine(data.prefix(96))
        hasher.combine(data.suffix(96))
        let key = "\(hasher.finalize())" as NSString
        if let cached = rooms.object(forKey: key) { return cached }
        guard let small = downsample(data, maxPixel: 180), let room = room(from: small) else { return nil }
        rooms.setObject(room, forKey: key)
        return room
    }

    /// The same, for a photo that is not on file yet.
    static func room(from image: UIImage) -> UIImage? {
        guard let cgImage = fitted(image, maxPixel: 180).cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)
        let level = RoomTone.level(meanBrightness: meanBrightness(of: input))
        let rich = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.7])
        let blurred = rich.clampedToExtent().applyingGaussianBlur(sigma: 16).cropped(to: input.extent)
        let dimmed = blurred.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: level, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: level, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: level, w: 0),
        ])
        guard let output = roomContext.createCGImage(dimmed, from: input.extent) else { return nil }
        return UIImage(cgImage: output)
    }

    /// The photo's mean brightness from 0 to 1.
    private static func meanBrightness(of image: CIImage) -> Double {
        let average = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)])
        var pixel = [UInt8](repeating: 0, count: 4)
        roomContext.render(
            average,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        return RoomTone.brightness(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
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
