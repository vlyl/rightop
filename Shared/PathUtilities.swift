import Foundation

enum FileNaming {
  static func uniqueFileURL(
    in directory: URL,
    preferredName: String,
    fileManager: FileManager = .default
  ) -> URL {
    let original = directory.appendingPathComponent(preferredName)
    guard fileManager.fileExists(atPath: original.path) else { return original }

    let nameURL = URL(fileURLWithPath: preferredName)
    let pathExtension = nameURL.pathExtension
    let stem =
      pathExtension.isEmpty
      ? preferredName
      : nameURL.deletingPathExtension().lastPathComponent

    var index = 2
    while true {
      let candidateName =
        pathExtension.isEmpty
        ? "\(stem) \(index)"
        : "\(stem) \(index).\(pathExtension)"
      let candidate = directory.appendingPathComponent(candidateName)
      if !fileManager.fileExists(atPath: candidate.path) {
        return candidate
      }
      index += 1
    }
  }
}

enum PathFormatting {
  static func shellQuote(_ path: String) -> String {
    guard !path.isEmpty else { return "''" }
    return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  static func directory(for url: URL, fileManager: FileManager = .default) -> URL {
    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    {
      return url
    }
    return url.deletingLastPathComponent()
  }

  static func uniqueDirectories(
    for urls: [URL],
    fileManager: FileManager = .default
  ) -> [URL] {
    var seen = Set<String>()
    return urls.compactMap { url in
      let directory = directory(for: url, fileManager: fileManager)
      return seen.insert(directory.path).inserted ? directory : nil
    }
  }
}
