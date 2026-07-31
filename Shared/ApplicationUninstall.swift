import Foundation

struct ApplicationIdentity: Sendable, Equatable {
  let url: URL
  let displayName: String
  let bundleIdentifier: String
  let version: String?
  let executableName: String?
}

enum ApplicationCleanupCategory: String, CaseIterable, Sendable {
  case application
  case applicationSupport
  case caches
  case preferences
  case containers
  case savedState
  case webData
  case logs
  case helpers
  case other

  var title: String {
    switch self {
    case .application: "Application"
    case .applicationSupport: "Application Support"
    case .caches: "Caches"
    case .preferences: "Preferences"
    case .containers: "Containers"
    case .savedState: "Saved State"
    case .webData: "Web Data"
    case .logs: "Logs"
    case .helpers: "Background Helpers"
    case .other: "Other Files"
    }
  }
}

enum ApplicationMatchConfidence: String, Sendable {
  case exact
  case likely

  var title: String {
    switch self {
    case .exact: "Exact match"
    case .likely: "Review"
    }
  }
}

struct ApplicationCleanupItem: Identifiable, Sendable, Equatable {
  let id: UUID
  let url: URL
  let category: ApplicationCleanupCategory
  let reason: String
  let confidence: ApplicationMatchConfidence
  let allocatedSize: Int64
  let isApplication: Bool
  let requiresElevatedAccess: Bool
  var isSelected: Bool

  init(
    id: UUID = UUID(),
    url: URL,
    category: ApplicationCleanupCategory,
    reason: String,
    confidence: ApplicationMatchConfidence,
    allocatedSize: Int64,
    isApplication: Bool = false,
    requiresElevatedAccess: Bool = false,
    isSelected: Bool = true
  ) {
    self.id = id
    self.url = url
    self.category = category
    self.reason = reason
    self.confidence = confidence
    self.allocatedSize = allocatedSize
    self.isApplication = isApplication
    self.requiresElevatedAccess = requiresElevatedAccess
    self.isSelected = isSelected
  }
}

struct ApplicationScanResult: Sendable {
  let application: ApplicationIdentity
  let items: [ApplicationCleanupItem]
  let warnings: [String]
}

struct ApplicationDeletionFailure: Identifiable, Sendable {
  let id = UUID()
  let url: URL
  let message: String
}

struct ApplicationDeletionReport: Sendable {
  let removed: [URL]
  let failures: [ApplicationDeletionFailure]
}

enum ApplicationScanError: LocalizedError {
  case notAnApplication
  case missingMetadata
  case cannotReadApplication

  var errorDescription: String? {
    switch self {
    case .notAnApplication:
      "Select a macOS application ending in .app."
    case .missingMetadata:
      "This app has no valid bundle identifier, so RightOp cannot match related files safely."
    case .cannotReadApplication:
      "RightOp could not read this application. Check its permissions and try again."
    }
  }
}

struct ApplicationUninstallScanner: Sendable {
  private struct SearchRoot: Sendable {
    let url: URL
    let category: ApplicationCleanupCategory
    let maxDepth: Int
    let systemWide: Bool
  }

  private typealias ExactCandidate = (
    url: URL,
    category: ApplicationCleanupCategory,
    reason: String,
    confidence: ApplicationMatchConfidence,
    systemWide: Bool
  )

  private var fileManager: FileManager { FileManager.default }

  func scan(applicationAt inputURL: URL) async throws -> ApplicationScanResult {
    try await Task.detached(priority: .userInitiated) {
      try scanSynchronously(applicationAt: inputURL)
    }.value
  }

  func match(
    fileName: String,
    bundleIdentifier: String,
    identifiers: [String]
  ) -> (confidence: ApplicationMatchConfidence, reason: String)? {
    let stem =
      fileName
      .replacingOccurrences(of: ".plist", with: "")
      .replacingOccurrences(of: ".savedState", with: "")
      .replacingOccurrences(of: ".binarycookies", with: "")
    let normalizedStem = normalized(stem)
    let normalizedBundleID = normalized(bundleIdentifier)

    if hasIdentifierBoundary(normalizedStem, identifier: normalizedBundleID) {
      return (.exact, "Name contains the app's bundle identifier")
    }

    for identifier in identifiers where normalized(identifier) != normalizedBundleID {
      let token = normalized(identifier)
      guard token.count >= 4 else { continue }
      if normalizedStem == token || hasIdentifierBoundary(normalizedStem, identifier: token) {
        return (.likely, "Name matches the application")
      }
    }
    return nil
  }

  static func collapsedURLs(_ urls: [URL]) -> [URL] {
    let normalizedPaths = Array(Set(urls.map { $0.standardizedFileURL.path }))
      .sorted { left, right in
        if left.count != right.count { return left.count < right.count }
        return left < right
      }

    var kept: [String] = []
    for path in normalizedPaths {
      let isNested = kept.contains { parent in
        path == parent || path.hasPrefix(parent + "/")
      }
      if !isNested {
        kept.append(path)
      }
    }
    return kept.map { URL(fileURLWithPath: $0) }
  }

  private func scanSynchronously(applicationAt inputURL: URL) throws -> ApplicationScanResult {
    let appURL = inputURL.standardizedFileURL
    guard appURL.pathExtension.lowercased() == "app" else {
      throw ApplicationScanError.notAnApplication
    }

    let values = try? appURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values?.isDirectory == true, values?.isSymbolicLink != true else {
      throw ApplicationScanError.cannotReadApplication
    }

    guard let bundle = Bundle(url: appURL) else {
      throw ApplicationScanError.cannotReadApplication
    }

    let fallbackName = appURL.deletingPathExtension().lastPathComponent
    let displayName =
      (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
      ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
      ?? fallbackName

    guard
      let bundleIdentifier = bundle.bundleIdentifier?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ),
      Self.isSafeBundleIdentifier(bundleIdentifier)
    else {
      throw ApplicationScanError.missingMetadata
    }

    let identity = ApplicationIdentity(
      url: appURL,
      displayName: displayName,
      bundleIdentifier: bundleIdentifier,
      version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
      executableName: bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
    )

    let home = fileManager.homeDirectoryForCurrentUser
    let userLibrary = home.appendingPathComponent("Library", isDirectory: true)
    let systemLibrary = URL(fileURLWithPath: "/Library", isDirectory: true)
    let identifiers = safeIdentifiers(for: identity)
    var found: [String: ApplicationCleanupItem] = [:]
    var warnings: [String] = []

    found[canonicalKey(appURL)] = ApplicationCleanupItem(
      url: appURL,
      category: .application,
      reason: "The selected application bundle",
      confidence: .exact,
      allocatedSize: allocatedSize(of: appURL),
      isApplication: true,
      requiresElevatedAccess: !fileManager.isWritableFile(
        atPath: appURL.deletingLastPathComponent().path
      )
    )

    for candidate in exactCandidateURLs(
      for: identity,
      userLibrary: userLibrary,
      systemLibrary: systemLibrary
    ) where fileManager.fileExists(atPath: candidate.url.path) {
      add(
        url: candidate.url,
        category: candidate.category,
        reason: candidate.reason,
        confidence: candidate.confidence,
        systemWide: candidate.systemWide,
        into: &found
      )
    }

    for root in searchRoots(userLibrary: userLibrary, systemLibrary: systemLibrary) {
      guard fileManager.fileExists(atPath: root.url.path) else { continue }
      do {
        try enumerate(
          root: root,
          identity: identity,
          identifiers: identifiers,
          found: &found
        )
      } catch {
        warnings.append("Some files in \(root.url.path) could not be inspected.")
      }
    }

    let ordered = found.values.sorted { left, right in
      if left.isApplication != right.isApplication {
        return left.isApplication
      }
      if left.category != right.category {
        let categories = ApplicationCleanupCategory.allCases
        return (categories.firstIndex(of: left.category) ?? 0)
          < (categories.firstIndex(of: right.category) ?? 0)
      }
      return left.url.path.localizedStandardCompare(right.url.path) == .orderedAscending
    }

    if ordered.contains(where: \.requiresElevatedAccess) {
      warnings.append(
        "System-wide items may require an administrator account or additional privacy access."
      )
    }

    return ApplicationScanResult(
      application: identity,
      items: ordered,
      warnings: warnings
    )
  }

  private func safeIdentifiers(for identity: ApplicationIdentity) -> [String] {
    var values = [
      identity.bundleIdentifier,
      identity.displayName,
      identity.url.deletingPathExtension().lastPathComponent,
    ]
    if let executableName = identity.executableName {
      values.append(executableName)
    }
    return Array(
      Set(
        values.filter { value in
          let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
          return trimmed.count >= 3 && !Self.unsafeGenericNames.contains(trimmed.lowercased())
        }))
  }

  private static let unsafeGenericNames: Set<String> = [
    "app", "application", "client", "desktop", "helper", "launcher", "mac", "setup", "update",
  ]

  static func isSafeBundleIdentifier(_ value: String) -> Bool {
    guard value.count >= 3, !value.contains("..") else { return false }
    return value.range(
      of: #"^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$"#,
      options: .regularExpression
    ) != nil
  }

  private func searchRoots(userLibrary: URL, systemLibrary: URL) -> [SearchRoot] {
    [
      SearchRoot(
        url: userLibrary.appendingPathComponent("Application Support"),
        category: .applicationSupport, maxDepth: 2, systemWide: false),
      SearchRoot(
        url: userLibrary.appendingPathComponent("Caches"), category: .caches, maxDepth: 1,
        systemWide: false),
      SearchRoot(
        url: userLibrary.appendingPathComponent("Preferences"), category: .preferences, maxDepth: 1,
        systemWide: false),
      SearchRoot(
        url: userLibrary.appendingPathComponent("Containers"), category: .containers, maxDepth: 1,
        systemWide: false),
      SearchRoot(
        url: userLibrary.appendingPathComponent("Group Containers"), category: .containers,
        maxDepth: 1, systemWide: false),
      SearchRoot(
        url: userLibrary.appendingPathComponent("Application Scripts"), category: .containers,
        maxDepth: 1, systemWide: false),
      SearchRoot(
        url: userLibrary.appendingPathComponent("Saved Application State"), category: .savedState,
        maxDepth: 1, systemWide: false),
      SearchRoot(
        url: userLibrary.appendingPathComponent("WebKit"), category: .webData, maxDepth: 1,
        systemWide: false),
      SearchRoot(
        url: userLibrary.appendingPathComponent("HTTPStorages"), category: .webData, maxDepth: 1,
        systemWide: false),
      SearchRoot(
        url: userLibrary.appendingPathComponent("Cookies"), category: .webData, maxDepth: 1,
        systemWide: false),
      SearchRoot(
        url: userLibrary.appendingPathComponent("Logs"), category: .logs, maxDepth: 2,
        systemWide: false),
      SearchRoot(
        url: userLibrary.appendingPathComponent("LaunchAgents"), category: .helpers, maxDepth: 1,
        systemWide: false),
      SearchRoot(
        url: systemLibrary.appendingPathComponent("Application Support"),
        category: .applicationSupport, maxDepth: 2, systemWide: true),
      SearchRoot(
        url: systemLibrary.appendingPathComponent("Caches"), category: .caches, maxDepth: 1,
        systemWide: true),
      SearchRoot(
        url: systemLibrary.appendingPathComponent("LaunchAgents"), category: .helpers, maxDepth: 1,
        systemWide: true),
      SearchRoot(
        url: systemLibrary.appendingPathComponent("LaunchDaemons"), category: .helpers, maxDepth: 1,
        systemWide: true),
      SearchRoot(
        url: systemLibrary.appendingPathComponent("PrivilegedHelperTools"), category: .helpers,
        maxDepth: 1, systemWide: true),
    ]
  }

  private func exactCandidateURLs(
    for identity: ApplicationIdentity,
    userLibrary: URL,
    systemLibrary: URL
  ) -> [ExactCandidate] {
    let bundleID = identity.bundleIdentifier
    let names = Array(
      Set([
        identity.displayName,
        identity.url.deletingPathExtension().lastPathComponent,
      ]))
    var candidates: [ExactCandidate] = []

    func append(
      _ base: URL,
      _ component: String,
      _ category: ApplicationCleanupCategory,
      _ reason: String,
      _ confidence: ApplicationMatchConfidence = .exact,
      _ systemWide: Bool = false
    ) {
      let standardizedBase = base.standardizedFileURL
      let candidate = base.appendingPathComponent(component).standardizedFileURL
      guard candidate.path.hasPrefix(standardizedBase.path + "/") else { return }
      candidates.append(
        (
          candidate,
          category,
          reason,
          confidence,
          systemWide
        ))
    }

    for name in names {
      append(
        userLibrary.appendingPathComponent("Application Support"), name, .applicationSupport,
        "Folder exactly matches the app name", .likely)
      append(
        userLibrary.appendingPathComponent("Caches"), name, .caches,
        "Cache folder exactly matches the app name", .likely)
      append(
        userLibrary.appendingPathComponent("Logs"), name, .logs,
        "Log folder exactly matches the app name", .likely)
      append(
        systemLibrary.appendingPathComponent("Application Support"), name, .applicationSupport,
        "System support folder exactly matches the app name", .likely, true)
    }

    let userExact: [(String, ApplicationCleanupCategory, String)] = [
      (
        "Application Support/\(bundleID)", .applicationSupport,
        "Folder matches the bundle identifier"
      ),
      ("Caches/\(bundleID)", .caches, "Cache matches the bundle identifier"),
      (
        "Preferences/\(bundleID).plist", .preferences,
        "Preference file matches the bundle identifier"
      ),
      ("Preferences/\(bundleID)", .preferences, "Preference folder matches the bundle identifier"),
      ("Containers/\(bundleID)", .containers, "Sandbox container matches the bundle identifier"),
      (
        "Application Scripts/\(bundleID)", .containers,
        "Application scripts match the bundle identifier"
      ),
      (
        "Saved Application State/\(bundleID).savedState", .savedState,
        "Saved state matches the bundle identifier"
      ),
      ("WebKit/\(bundleID)", .webData, "Web data matches the bundle identifier"),
      ("HTTPStorages/\(bundleID)", .webData, "HTTP storage matches the bundle identifier"),
      (
        "HTTPStorages/\(bundleID).binarycookies", .webData,
        "Cookie storage matches the bundle identifier"
      ),
      ("Cookies/\(bundleID).binarycookies", .webData, "Cookies match the bundle identifier"),
      ("Logs/\(bundleID)", .logs, "Logs match the bundle identifier"),
      ("LaunchAgents/\(bundleID).plist", .helpers, "Launch agent matches the bundle identifier"),
    ]
    for (path, category, reason) in userExact {
      append(userLibrary, path, category, reason)
    }

    let systemExact: [(String, ApplicationCleanupCategory, String)] = [
      (
        "Application Support/\(bundleID)", .applicationSupport,
        "System support folder matches the bundle identifier"
      ),
      ("Caches/\(bundleID)", .caches, "System cache matches the bundle identifier"),
      (
        "LaunchAgents/\(bundleID).plist", .helpers,
        "System launch agent matches the bundle identifier"
      ),
      ("LaunchDaemons/\(bundleID).plist", .helpers, "Launch daemon matches the bundle identifier"),
      (
        "PrivilegedHelperTools/\(bundleID)", .helpers,
        "Privileged helper matches the bundle identifier"
      ),
    ]
    for (path, category, reason) in systemExact {
      append(systemLibrary, path, category, reason, .exact, true)
    }

    return candidates
  }

  private func enumerate(
    root: SearchRoot,
    identity: ApplicationIdentity,
    identifiers: [String],
    found: inout [String: ApplicationCleanupItem]
  ) throws {
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .nameKey]
    guard
      let enumerator = fileManager.enumerator(
        at: root.url,
        includingPropertiesForKeys: Array(keys),
        options: [.skipsHiddenFiles, .skipsPackageDescendants],
        errorHandler: { _, _ in true }
      )
    else { return }

    while let item = enumerator.nextObject() as? URL {
      let relativeDepth = item.pathComponents.count - root.url.pathComponents.count
      if relativeDepth > root.maxDepth {
        enumerator.skipDescendants()
        continue
      }

      let values = try? item.resourceValues(forKeys: keys)
      if values?.isSymbolicLink == true {
        enumerator.skipDescendants()
        continue
      }

      guard
        let match = match(
          fileName: item.lastPathComponent,
          bundleIdentifier: identity.bundleIdentifier,
          identifiers: identifiers
        )
      else { continue }

      add(
        url: item,
        category: root.category,
        reason: match.reason,
        confidence: match.confidence,
        systemWide: root.systemWide,
        into: &found
      )
      if values?.isDirectory == true {
        enumerator.skipDescendants()
      }
    }
  }

  private func add(
    url: URL,
    category: ApplicationCleanupCategory,
    reason: String,
    confidence: ApplicationMatchConfidence,
    systemWide: Bool,
    into found: inout [String: ApplicationCleanupItem]
  ) {
    let canonicalURL = url.standardizedFileURL
    let values = try? canonicalURL.resourceValues(forKeys: [.isSymbolicLinkKey])
    guard values?.isSymbolicLink != true else { return }

    let key = canonicalKey(canonicalURL)
    guard found[key] == nil else { return }
    found[key] = ApplicationCleanupItem(
      url: canonicalURL,
      category: category,
      reason: reason,
      confidence: confidence,
      allocatedSize: allocatedSize(of: canonicalURL),
      requiresElevatedAccess: systemWide
        || !fileManager.isWritableFile(atPath: canonicalURL.deletingLastPathComponent().path),
      isSelected: confidence == .exact
    )
  }

  private func normalized(_ value: String) -> String {
    value
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9]+"#, with: ".", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))
  }

  private func hasIdentifierBoundary(_ value: String, identifier: String) -> Bool {
    guard !identifier.isEmpty else { return false }
    return value == identifier
      || value.hasPrefix(identifier + ".")
      || value.hasSuffix("." + identifier)
      || value.contains("." + identifier + ".")
  }

  private func canonicalKey(_ url: URL) -> String {
    url.standardizedFileURL.path
  }

  private func allocatedSize(of url: URL) -> Int64 {
    let keys: Set<URLResourceKey> = [
      .isRegularFileKey,
      .fileAllocatedSizeKey,
      .totalFileAllocatedSizeKey,
    ]
    if let values = try? url.resourceValues(forKeys: keys),
      let total = values.totalFileAllocatedSize
    {
      return Int64(total)
    }
    if let values = try? url.resourceValues(forKeys: keys),
      values.isRegularFile == true
    {
      return Int64(values.fileAllocatedSize ?? 0)
    }

    guard
      let enumerator = fileManager.enumerator(
        at: url,
        includingPropertiesForKeys: Array(keys),
        options: [.skipsHiddenFiles],
        errorHandler: { _, _ in true }
      )
    else { return 0 }

    var total: Int64 = 0
    while let child = enumerator.nextObject() as? URL {
      if let values = try? child.resourceValues(forKeys: keys),
        values.isRegularFile == true
      {
        total += Int64(values.fileAllocatedSize ?? 0)
      }
    }
    return total
  }
}
