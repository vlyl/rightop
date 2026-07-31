import Foundation

struct ApplicationUninstallRequest: Identifiable {
  let id: UUID
  let applicationURL: URL
}

enum ApplicationUninstallRequestError: LocalizedError {
  case notAnApplication
  case invalidRequest
  case requestExpired

  var errorDescription: String? {
    switch self {
    case .notAnApplication:
      "Select one macOS application ending in .app."
    case .invalidRequest:
      "The uninstall request is invalid. Return to Finder and try again."
    case .requestExpired:
      "The uninstall request has expired. Return to Finder and try again."
    }
  }
}

enum ApplicationUninstallRequestStore {
  private static let scheme = "rightop"
  private static let host = "uninstall"
  private static let keyPrefix = "pendingApplicationUninstall."

  static func isApplicationBundle(_ url: URL) -> Bool {
    guard url.pathExtension.lowercased() == "app" else { return false }
    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    return values?.isDirectory == true && values?.isSymbolicLink != true
  }

  static func create(
    for applicationURL: URL,
    defaults: UserDefaults = .rightOpShared
  ) throws -> URL {
    guard isApplicationBundle(applicationURL) else {
      throw ApplicationUninstallRequestError.notAnApplication
    }

    let identifier = UUID()
    let bookmark = try SecurityScopedBookmarks.make(for: applicationURL.standardizedFileURL)
    defaults.set(bookmark, forKey: storageKey(for: identifier))
    defaults.synchronize()

    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.path = "/\(identifier.uuidString)"
    guard let requestURL = components.url else {
      defaults.removeObject(forKey: storageKey(for: identifier))
      throw ApplicationUninstallRequestError.invalidRequest
    }
    return requestURL
  }

  static func consume(
    _ requestURL: URL,
    defaults: UserDefaults = .rightOpShared
  ) throws -> ApplicationUninstallRequest {
    guard let identifier = requestIdentifier(from: requestURL) else {
      throw ApplicationUninstallRequestError.invalidRequest
    }
    let key = storageKey(for: identifier)
    guard let bookmark = defaults.data(forKey: key) else {
      throw ApplicationUninstallRequestError.requestExpired
    }

    var isStale = false
    guard
      let applicationURL = try? URL(
        resolvingBookmarkData: bookmark,
        options: [.withSecurityScope, .withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
    else {
      throw ApplicationUninstallRequestError.requestExpired
    }

    defaults.removeObject(forKey: key)
    defaults.synchronize()
    return ApplicationUninstallRequest(
      id: identifier,
      applicationURL: applicationURL.standardizedFileURL
    )
  }

  static func discard(
    _ requestURL: URL,
    defaults: UserDefaults = .rightOpShared
  ) {
    guard let identifier = requestIdentifier(from: requestURL) else { return }
    defaults.removeObject(forKey: storageKey(for: identifier))
    defaults.synchronize()
  }

  static func requestIdentifier(from url: URL) -> UUID? {
    guard url.scheme == scheme, url.host == host else { return nil }
    return UUID(uuidString: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
  }

  private static func storageKey(for identifier: UUID) -> String {
    keyPrefix + identifier.uuidString
  }
}
