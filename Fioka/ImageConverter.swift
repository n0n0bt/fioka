import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Output formats for image conversion. Each is offered only when ImageIO can
/// actually encode it on this system (WebP and AVIF depend on the macOS
/// version); PDF goes through PDFKit instead.
enum ImageExportFormat: CaseIterable {
  case png, jpeg, heic, webp, tiff, avif, bmp, pdf

  var title: String {
    switch self {
    case .png: return "PNG"
    case .jpeg: return "JPEG"
    case .heic: return "HEIC"
    case .webp: return "WebP"
    case .tiff: return "TIFF"
    case .avif: return "AVIF"
    case .bmp: return "BMP"
    case .pdf: return "PDF"
    }
  }

  var type: UTType {
    switch self {
    case .png: return .png
    case .jpeg: return .jpeg
    case .heic: return .heic
    case .webp: return .webP
    case .tiff: return .tiff
    case .avif: return UTType("public.avif") ?? .image
    case .bmp: return .bmp
    case .pdf: return .pdf
    }
  }

  var isAvailable: Bool {
    guard self != .pdf else { return true }
    let encodable = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
    return encodable.contains(type.identifier)
  }

  static var available: [ImageExportFormat] { allCases.filter(\.isAvailable) }

  init?(fileURL url: URL) {
    guard let type = UTType(filenameExtension: url.pathExtension),
          let match = Self.allCases.first(where: { type.conforms(to: $0.type) }) else {
      return nil
    }
    self = match
  }
}

/// Image conversion with ImageIO, shared by the card actions and the drop
/// wheel. No UI here: callers decide where results go and how to report them.
enum ImageConverter {
  static func isImageFile(_ url: URL) -> Bool {
    UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
  }

  /// Decodes the first image in `source`, applies `scale`, and encodes it.
  /// Re-encoding without copying properties also drops EXIF and GPS metadata.
  static func data(
    from source: CGImageSource,
    as format: ImageExportFormat,
    quality: Double = 0.9,
    scale: Double = 1
  ) throws -> Data {
    guard var image = orientedImage(from: source) else {
      throw ConversionError.unreadable
    }

    if scale != 1 {
      image = try resized(image, by: scale)
    }
    // JPEG and BMP have no alpha; without flattening, transparency turns black.
    if format == .jpeg || format == .bmp {
      image = try flattened(image)
    }
    return try encode(image, as: format, quality: quality)
  }

  /// Converts a file and writes the result beside it (see `ConvertedFile`).
  @discardableResult
  static func convertFile(
    _ url: URL,
    to format: ImageExportFormat,
    quality: Double = 0.9,
    scale: Double = 1,
    suffix: String? = nil
  ) throws -> URL {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      throw ConversionError.unreadable
    }
    let data = try data(from: source, as: format, quality: quality, scale: scale)
    let output = ConvertedFile.url(beside: url, suffix: suffix, type: format.type)
    try data.write(to: output, options: .withoutOverwriting)
    return output
  }

  /// The full-size image with its EXIF orientation applied. Metadata is not
  /// carried into the output, so a phone photo stored sideways with an
  /// orientation flag would otherwise come out rotated. The thumbnail API is
  /// the one ImageIO call that applies the transform; asking for a thumbnail
  /// as large as the image makes it a full-size decode.
  private static func orientedImage(from source: CGImageSource) -> CGImage? {
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
    let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
    guard width > 0, height > 0 else {
      return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    let options = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(width, height)
    ] as CFDictionary
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
  }

  /// Writes an already-decoded image, e.g. a rendered PDF page.
  static func write(_ image: CGImage, as format: ImageExportFormat, to url: URL, quality: Double = 0.9) throws {
    let image = format == .jpeg || format == .bmp ? try flattened(image) : image
    try encode(image, as: format, quality: quality).write(to: url, options: .withoutOverwriting)
  }

  // MARK: - Encoding

  private static func encode(_ image: CGImage, as format: ImageExportFormat, quality: Double) throws -> Data {
    if format == .pdf {
      let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
      guard let page = PDFPage(image: nsImage) else {
        throw ConversionError.encodingFailed(format.title)
      }
      let document = PDFDocument()
      document.insert(page, at: 0)
      guard let pdf = document.dataRepresentation() else {
        throw ConversionError.encodingFailed(format.title)
      }
      return pdf
    }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, format.type.identifier as CFString, 1, nil) else {
      throw ConversionError.encodingFailed(format.title)
    }
    let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
    CGImageDestinationAddImage(destination, image, options)
    guard CGImageDestinationFinalize(destination) else {
      throw ConversionError.encodingFailed(format.title)
    }
    return data as Data
  }

  private static func resized(_ image: CGImage, by scale: Double) throws -> CGImage {
    let width = max(1, Int(Double(image.width) * scale))
    let height = max(1, Int(Double(image.height) * scale))
    return try draw(width: width, height: height, background: nil) { context in
      context.interpolationQuality = .high
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
  }

  private static func flattened(_ image: CGImage) throws -> CGImage {
    try draw(width: image.width, height: image.height, background: .white) { context in
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
  }

  private static func draw(
    width: Int,
    height: Int,
    background: CGColor?,
    _ body: (CGContext) -> Void
  ) throws -> CGImage {
    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      throw ConversionError.encodingFailed("bitmap")
    }
    if let background {
      context.setFillColor(background)
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    body(context)
    guard let image = context.makeImage() else {
      throw ConversionError.encodingFailed("bitmap")
    }
    return image
  }
}
