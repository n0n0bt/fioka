import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Text documents, read and written by AppKit's own importers: the same code
/// TextEdit uses, so Word files convert without Word or LibreOffice.
enum DocumentFormat: CaseIterable {
  case pdf, docx, doc, rtf, odt, html, txt

  var title: String {
    switch self {
    case .pdf: return "PDF"
    case .docx: return "DOCX"
    case .doc: return "DOC"
    case .rtf: return "RTF"
    case .odt: return "ODT"
    case .html: return "HTML"
    case .txt: return "TXT"
    }
  }

  var type: UTType {
    switch self {
    case .pdf: return .pdf
    case .docx: return UTType("org.openxmlformats.wordprocessingml.document") ?? .data
    case .doc: return UTType("com.microsoft.word.doc") ?? .data
    case .rtf: return .rtf
    case .odt: return UTType("org.oasis-open.opendocument.text") ?? .data
    case .html: return .html
    case .txt: return .plainText
    }
  }

  var documentType: NSAttributedString.DocumentType? {
    switch self {
    case .pdf: return nil
    case .docx: return .officeOpenXML
    case .doc: return .docFormat
    case .rtf: return .rtf
    case .odt: return .openDocument
    case .html: return .html
    case .txt: return .plain
    }
  }

  func matches(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    switch self {
    case .html: return ext == "html" || ext == "htm"
    default: return ext == title.lowercased()
    }
  }
}

enum SubtitleFormat: CaseIterable {
  case srt, vtt, txt

  var title: String {
    switch self {
    case .srt: return "SRT"
    case .vtt: return "VTT"
    case .txt: return "TXT"
    }
  }

  var type: UTType {
    switch self {
    case .srt: return UTType(filenameExtension: "srt") ?? .plainText
    case .vtt: return UTType(filenameExtension: "vtt") ?? .plainText
    case .txt: return .plainText
    }
  }
}

/// PDFs, text documents, subtitles and zip archives.
@MainActor
enum DocumentConverter {
  // MARK: - PDF

  private static func open(_ url: URL) throws -> PDFDocument {
    guard let document = PDFDocument(url: url) else { throw ConversionError.unreadable }
    return document
  }

  /// One image per page at 2× (144 dpi). A single page keeps the plain name;
  /// otherwise pages are numbered.
  static func pdfToImages(_ url: URL, as format: ImageExportFormat) throws -> [URL] {
    let document = try open(url)
    return try (0..<document.pageCount).compactMap { index in
      guard let page = document.page(at: index) else { return nil }
      let bounds = page.bounds(for: .mediaBox)
      // thumbnail(of:for:) applies page rotation and paints a white page.
      let size = NSSize(width: bounds.width * 2, height: bounds.height * 2)
      let image = page.thumbnail(of: size, for: .mediaBox)
      guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw ConversionError.encodingFailed(format.title)
      }
      let suffix = document.pageCount == 1 ? nil : "\(index + 1)"
      let output = ConvertedFile.url(beside: url, suffix: suffix, type: format.type)
      try ImageConverter.write(cgImage, as: format, to: output)
      return output
    }
  }

  static func pdfText(_ url: URL) throws -> String {
    try open(url).string ?? ""
  }

  static func pdfToText(_ url: URL) throws -> URL {
    let output = ConvertedFile.url(beside: url, type: .plainText)
    try pdfText(url).write(to: output, atomically: true, encoding: .utf8)
    return output
  }

  /// Text with its fonts kept; layout is not, since a PDF has no paragraphs
  /// to recover, only positioned glyphs.
  static func pdfToDocument(_ url: URL, as format: DocumentFormat) throws -> URL {
    let document = try open(url)
    let text = NSMutableAttributedString()
    for index in 0..<document.pageCount {
      if let page = document.page(at: index)?.attributedString {
        if text.length > 0 { text.append(NSAttributedString(string: "\n\n")) }
        text.append(page)
      }
    }
    return try write(text, beside: url, as: format)
  }

  /// One PDF from several, in drag order. Images may be mixed in: each one
  /// becomes a page of its own size, so scans and photos combine directly.
  static func merge(_ urls: [URL]) throws -> URL {
    guard let first = urls.first else { throw ConversionError.unreadable }
    let merged = PDFDocument()
    for url in urls {
      if FileKind(url) == .image {
        // NSImage applies EXIF orientation, so phone photos come out upright.
        guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else {
          throw ConversionError.unreadable
        }
        merged.insert(page, at: merged.pageCount)
        continue
      }
      let document = try open(url)
      for index in 0..<document.pageCount {
        if let page = document.page(at: index)?.copy() as? PDFPage {
          merged.insert(page, at: merged.pageCount)
        }
      }
    }
    let output = ConvertedFile.url(beside: first, suffix: "merged", type: .pdf)
    guard merged.write(to: output) else { throw ConversionError.encodingFailed("PDF") }
    return output
  }

  /// One PDF per page, in a folder beside the original.
  static func split(_ url: URL) throws -> [URL] {
    let document = try open(url)
    let name = url.deletingPathExtension().lastPathComponent
    let folder = ConvertedFile.folder(beside: url, name: "\(name) pages")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    return try (0..<document.pageCount).compactMap { index in
      guard let page = document.page(at: index)?.copy() as? PDFPage else { return nil }
      let single = PDFDocument()
      single.insert(page, at: 0)
      let output = folder.appendingPathComponent("\(name) \(index + 1)").appendingPathExtension(for: .pdf)
      guard single.write(to: output) else { throw ConversionError.encodingFailed("PDF") }
      return output
    }
  }

  /// Re-encodes embedded images as JPEG at screen resolution, which is where
  /// nearly all of a large PDF's size is.
  static func compressPDF(_ url: URL) throws -> URL {
    let document = try open(url)
    let output = ConvertedFile.url(beside: url, suffix: "compressed", type: .pdf)
    let options: [PDFDocumentWriteOption: Any] = [
      .saveImagesAsJPEGOption: true,
      .optimizeImagesForScreenOption: true
    ]
    guard document.write(to: output, withOptions: options) else { throw ConversionError.encodingFailed("PDF") }
    return output
  }

  static func rotate(_ url: URL) throws -> URL {
    let document = try open(url)
    for index in 0..<document.pageCount {
      if let page = document.page(at: index) {
        page.rotation = (page.rotation + 90) % 360
      }
    }
    let output = ConvertedFile.url(beside: url, suffix: "rotated", type: .pdf)
    guard document.write(to: output) else { throw ConversionError.encodingFailed("PDF") }
    return output
  }

  // MARK: - Documents

  static func readDocument(_ url: URL) throws -> NSAttributedString {
    do {
      return try NSAttributedString(url: url, options: [:], documentAttributes: nil)
    } catch {
      throw ConversionError.unreadable
    }
  }

  static func convertDocument(_ url: URL, to format: DocumentFormat) throws -> URL {
    try write(readDocument(url), beside: url, as: format)
  }

  private static func write(_ text: NSAttributedString, beside source: URL, as format: DocumentFormat) throws -> URL {
    let output = ConvertedFile.url(beside: source, type: format.type)

    guard let documentType = format.documentType else {
      try writePDF(text, to: output)
      return output
    }

    var attributes: [NSAttributedString.DocumentAttributeKey: Any] = [.documentType: documentType]
    if format == .txt || format == .html {
      attributes[.characterEncoding] = String.Encoding.utf8.rawValue
    }
    let data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: attributes)
    try data.write(to: output, options: .withoutOverwriting)
    return output
  }

  /// Lays the text out on A4/Letter (whatever the system default is) and
  /// "prints" it to a file, which paginates it the way TextEdit would.
  private static func writePDF(_ text: NSAttributedString, to url: URL) throws {
    guard let info = NSPrintInfo.shared.copy() as? NSPrintInfo else { throw ConversionError.encodingFailed("PDF") }
    info.jobDisposition = .save
    info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
    info.horizontalPagination = .fit
    info.verticalPagination = .automatic
    info.isVerticallyCentered = false
    for margin in [\NSPrintInfo.topMargin, \.bottomMargin, \.leftMargin, \.rightMargin] {
      info[keyPath: margin] = 56
    }

    let width = info.paperSize.width - info.leftMargin - info.rightMargin
    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
    view.textStorage?.setAttributedString(text)
    view.isVerticallyResizable = true
    if let container = view.textContainer, let layout = view.layoutManager {
      layout.ensureLayout(for: container)
      view.frame.size.height = max(1, layout.usedRect(for: container).height)
    }

    let operation = NSPrintOperation(view: view, printInfo: info)
    operation.showsPrintPanel = false
    operation.showsProgressPanel = false
    guard operation.run(), FileManager.default.fileExists(atPath: url.path) else {
      throw ConversionError.encodingFailed("PDF")
    }
  }

  // MARK: - Subtitles

  struct Cue: Equatable {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
  }

  /// Reads SRT and WebVTT alike: both are blank-line-separated blocks with a
  /// `start --> end` line followed by the text.
  static func parseCues(_ string: String) -> [Cue] {
    let normalized = string
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    return normalized.components(separatedBy: "\n\n").compactMap { block in
      let lines = block.components(separatedBy: "\n")
      guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
      let parts = lines[timing].components(separatedBy: "-->")
      guard parts.count == 2,
            let start = parseTime(parts[0]),
            // VTT may follow the end time with cue settings.
            let end = parseTime(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ")[0]) else {
        return nil
      }
      let text = lines[(timing + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
      return text.isEmpty ? nil : Cue(start: start, end: end, text: text)
    }
  }

  private static func parseTime(_ string: String) -> TimeInterval? {
    let fields = string.trimmingCharacters(in: .whitespaces)
      .replacingOccurrences(of: ",", with: ".")
      .components(separatedBy: ":")
    guard (2...3).contains(fields.count) else { return nil }
    var total: TimeInterval = 0
    for field in fields {
      guard let value = Double(field) else { return nil }
      total = total * 60 + value
    }
    return total
  }

  private static func formatTime(_ time: TimeInterval, separator: String) -> String {
    let milliseconds = Int((time * 1000).rounded())
    return String(format: "%02d:%02d:%02d%@%03d",
                  milliseconds / 3_600_000, milliseconds / 60_000 % 60, milliseconds / 1000 % 60,
                  separator, milliseconds % 1000)
  }

  static func render(_ cues: [Cue], as format: SubtitleFormat) -> String {
    switch format {
    case .srt:
      return cues.enumerated().map { index, cue in
        "\(index + 1)\n\(formatTime(cue.start, separator: ",")) --> \(formatTime(cue.end, separator: ","))\n\(cue.text)"
      }.joined(separator: "\n\n") + "\n"
    case .vtt:
      return "WEBVTT\n\n" + cues.map { cue in
        "\(formatTime(cue.start, separator: ".")) --> \(formatTime(cue.end, separator: "."))\n\(cue.text)"
      }.joined(separator: "\n\n") + "\n"
    case .txt:
      // Styling tags (<i>, <b>, VTT voice spans) are markup, not words.
      return cues.map {
        $0.text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
      }.joined(separator: "\n") + "\n"
    }
  }

  static func convertSubtitles(_ url: URL, to format: SubtitleFormat) throws -> URL {
    guard let string = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else {
      throw ConversionError.unreadable
    }
    let cues = parseCues(string)
    guard !cues.isEmpty else { throw ConversionError.failed("No subtitles found in \(url.lastPathComponent).") }
    let output = ConvertedFile.url(beside: url, type: format.type)
    try render(cues, as: format).write(to: output, atomically: true, encoding: .utf8)
    return output
  }

  // MARK: - Archives

  static func zip(_ urls: [URL]) async throws -> URL {
    guard let first = urls.first else { throw ConversionError.unreadable }
    let directory = first.deletingLastPathComponent()
    let name = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
    let output = ConvertedFile.url(in: directory, name: name, type: .zip)

    // Relative names keep the archive free of absolute paths; files from
    // other folders fall back to their full path.
    let names = urls.map { url in
      url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL
        ? url.lastPathComponent : url.path
    }
    try await ExternalTool.run("/usr/bin/zip", ["-r", "-q", "-y", output.path] + names, in: directory)
    return output
  }

  static func extract(_ url: URL) async throws -> URL {
    let folder = ConvertedFile.folder(beside: url, name: url.deletingPathExtension().lastPathComponent)
    try await ExternalTool.run("/usr/bin/ditto", ["-x", "-k", url.path, folder.path])
    return folder
  }
}
