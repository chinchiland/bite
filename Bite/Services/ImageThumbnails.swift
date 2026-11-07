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

    /// A photo as a room to stand in: its colors, blurred and made richer, then dimmed to the
    /// depth every room shares. Small, and scaled up on screen, so it costs nothing behind a page
    /// that scrolls. Cached by photo.
    static func room(_ data: Data) -> UIImage? {
        var hasher = Hasher()
        hasher.combine(data.count)
        hasher.combine(data.prefix(96))
        hasher.combine(data.suffix(96))
        let key = "\(hasher.finalize())" as NSString
        if let cached = rooms.object(forKey: key) { return cached }
        guard let small = downsample(data, maxPixel: 360), let room = room(from: small) else { return nil }
        rooms.setObject(room, forKey: key)
        return room
    }

    /// The same, for a photo that is not on file yet.
    static func room(from image: UIImage) -> UIImage? {
        guard let cgImage = fitted(image, maxPixel: 360).cgImage else { return nil }
        let photo = CIImage(cgImage: cgImage)
        // The plate is in the middle: the table around it would only gray the room.
        let plate = photo.extent.insetBy(dx: photo.extent.width * 0.14, dy: photo.extent.height * 0.14)
        // Stretched to the shape of a phone before the blur, so every color on the plate gets
        // a place in the room, not only the ones in the middle of it.
        let size = CGSize(width: 130, height: 282)
        let frame = CGRect(origin: .zero, size: size)
        let stretched = photo.cropped(to: plate)
            .transformed(by: CGAffineTransform(translationX: -plate.minX, y: -plate.minY))
            .transformed(by: CGAffineTransform(scaleX: size.width / plate.width, y: size.height / plate.height))
        // Richer after the blur: what the blur left is the color of the meal, and that is what
        // the room should say.
        let rich = stretched.clampedToExtent()
            .applyingGaussianBlur(sigma: 24)
            .cropped(to: frame)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 3])
        let level = roomLevel(of: rich, in: frame)
        let dimmed = rich.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: level, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: level, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: level, w: 0),
        ])
        guard let output = roomContext.createCGImage(dimmed, from: frame) else { return nil }
        return UIImage(cgImage: output)
    }

    /// How far to dim an image, read from its own pixels.
    private static func roomLevel(of image: CIImage, in frame: CGRect) -> Double {
        let width = Int(frame.width)
        let height = Int(frame.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        roomContext.render(image, toBitmap: &pixels, rowBytes: width * 4, bounds: frame, format: .RGBA8, colorSpace: nil)
        // Every fourth pixel across and down is plenty for something this blurred.
        var values: [Double] = []
        values.reserveCapacity(width * height / 16)
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                let at = (y * width + x) * 4
                values.append(RoomTone.brightness(
                    red: Double(pixels[at]) / 255,
                    green: Double(pixels[at + 1]) / 255,
                    blue: Double(pixels[at + 2]) / 255
                ))
            }
        }
        let mean = values.reduce(0, +) / Double(max(values.count, 1))
        return RoomTone.level(mean: mean, peak: RoomTone.peak(of: values))
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
