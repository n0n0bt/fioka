import Foundation
import UniformTypeIdentifiers

/// What a dragged file is, which decides the wheel it gets.
enum FileKind: Equatable {
  case image, video, audio, pdf, document, subtitle, archive, other

  static let documentExtensions: Set<String> = ["doc", "docx", "rtf", "rtfd", "html", "htm", "txt", "odt", "webarchive"]
  static let subtitleExtensions: Set<String> = ["srt", "vtt"]

  init(_ url: URL) {
    let ext = url.pathExtension.lowercased()
    let type = UTType(filenameExtension: ext)

    // Extension checks first: .txt and .html conform to broader types, and
    // .srt has no system type at all.
    if Self.subtitleExtensions.contains(ext) {
      self = .subtitle
    } else if Self.documentExtensions.contains(ext) {
      self = .document
    } else if let type, type.conforms(to: .pdf) {
      self = .pdf
    } else if let type, type.conforms(to: .image) {
      self = .image
    } else if let type, type.conforms(to: .movie) {
      self = .video
    } else if let type, type.conforms(to: .audio) {
      self = .audio
    } else if let type, type.conforms(to: .zip) {
      self = .archive
    } else {
      self = .other
    }
  }
}

enum ConversionError: LocalizedError {
  case unreadable
  case encodingFailed(String)
  case failed(String)

  var errorDescription: String? {
    switch self {
    case .unreadable: return "Could not read the file."
    case .encodingFailed(let format): return "Could not convert to \(format)."
    case .failed(let message): return message
    }
  }
}

/// Where converted files go: beside the source, where you will look for them,
/// never overwriting — `photo.png`, then `photo 2.png`.
enum ConvertedFile {
  static func url(beside source: URL, suffix: String? = nil, type: UTType) -> URL {
    let name = [source.deletingPathExtension().lastPathComponent, suffix]
      .compactMap { $0 }
      .joined(separator: " ")
    return url(in: source.deletingLastPathComponent(), name: name, type: type)
  }

  static func url(in directory: URL, name: String, type: UTType) -> URL {
    unique { counter in
      let base = counter == 1 ? name : "\(name) \(counter)"
      return directory.appendingPathComponent(base).appendingPathExtension(for: type)
    }
  }

  static func folder(beside source: URL, name: String) -> URL {
    unique { counter in
      source.deletingLastPathComponent()
        .appendingPathComponent(counter == 1 ? name : "\(name) \(counter)", isDirectory: true)
    }
  }

  private static func unique(_ candidate: (Int) -> URL) -> URL {
    var counter = 1
    while FileManager.default.fileExists(atPath: candidate(counter).path) {
      counter += 1
    }
    return candidate(counter)
  }
}

/// Runs a command-line tool that ships with macOS (afconvert, zip, ditto).
enum ExternalTool {
  static func run(_ executable: String, _ arguments: [String], in directory: URL? = nil) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
      if let directory {
        process.currentDirectoryURL = directory
      }
      let errors = Pipe()
      process.standardError = errors
      process.standardOutput = FileHandle.nullDevice

      process.terminationHandler = { process in
        guard process.terminationStatus != 0 else {
          continuation.resume()
          return
        }
        let output = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tool = (executable as NSString).lastPathComponent
        continuation.resume(throwing: ConversionError.failed(output.isEmpty ? "\(tool) failed." : "\(tool): \(output)"))
      }

      do {
        try process.run()
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }
}
