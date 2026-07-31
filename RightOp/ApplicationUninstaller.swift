import AppKit
import Foundation

struct ApplicationTrashService: Sendable {
  private enum RecycleOutcome: Sendable {
    case removed
    case failed(String)
  }

  func moveToTrash(_ items: [ApplicationCleanupItem]) async -> ApplicationDeletionReport {
    let urls = ApplicationUninstallScanner.collapsedURLs(
      items.filter(\.isSelected).map(\.url)
    )
    var removed: [URL] = []
    var failures: [ApplicationDeletionFailure] = []

    for url in urls where FileManager.default.fileExists(atPath: url.path) {
      switch await recycleLikeFinder(url) {
      case .removed:
        removed.append(url)
      case .failed(let message):
        failures.append(ApplicationDeletionFailure(url: url, message: message))
      }
    }
    return ApplicationDeletionReport(removed: removed, failures: failures)
  }

  @MainActor
  private func recycleLikeFinder(_ url: URL) async -> RecycleOutcome {
    await withCheckedContinuation { continuation in
      NSWorkspace.shared.recycle([url]) { movedURLs, error in
        if !movedURLs.isEmpty || !FileManager.default.fileExists(atPath: url.path) {
          continuation.resume(returning: .removed)
        } else {
          continuation.resume(
            returning: .failed(
              error?.localizedDescription
                ?? "macOS did not grant permission to move this item to the Trash."
            )
          )
        }
      }
    }
  }
}

@MainActor
final class ApplicationUninstaller: ObservableObject {
  enum Phase: Equatable {
    case scanning
    case ready
    case deleting
    case finished
    case failed
  }

  @Published private(set) var phase: Phase = .scanning
  @Published private(set) var result: ApplicationScanResult?
  @Published var items: [ApplicationCleanupItem] = []
  @Published private(set) var report: ApplicationDeletionReport?
  @Published private(set) var errorMessage: String?
  @Published var showingConfirmation = false
  @Published private(set) var isTargetRunning = false

  private let request: ApplicationUninstallRequest
  private let scanner = ApplicationUninstallScanner()
  private let trashService = ApplicationTrashService()
  private var securityScopedURLs: [URL] = []
  private var didStart = false

  init(request: ApplicationUninstallRequest) {
    self.request = request
  }

  deinit {
    for url in securityScopedURLs {
      url.stopAccessingSecurityScopedResource()
    }
  }

  var selectedItems: [ApplicationCleanupItem] {
    items.filter(\.isSelected)
  }

  var selectedCount: Int {
    selectedItems.count
  }

  var selectedSize: Int64 {
    selectedItems.reduce(0) { $0 + $1.allocatedSize }
  }

  var reviewCount: Int {
    items.filter { $0.confidence == .likely }.count
  }

  func start() {
    guard !didStart else { return }
    didStart = true
    beginSecurityScopedAccess()

    Task {
      do {
        let scan = try await scanner.scan(applicationAt: request.applicationURL)
        let warnings = scan.warnings + folderAccessWarnings()
        let resolved = ApplicationScanResult(
          application: scan.application,
          items: scan.items,
          warnings: warnings
        )
        result = resolved
        items = resolved.items
        refreshRunningState()
        phase = .ready
      } catch {
        errorMessage = error.localizedDescription
        phase = .failed
      }
    }
  }

  func setSelected(_ selected: Bool, for id: ApplicationCleanupItem.ID) {
    guard
      let index = items.firstIndex(where: { $0.id == id }),
      !items[index].isApplication
    else { return }
    items[index].isSelected = selected
  }

  func selectExactMatches() {
    for index in items.indices {
      items[index].isSelected =
        items[index].isApplication || items[index].confidence == .exact
    }
  }

  func selectEverything() {
    for index in items.indices {
      items[index].isSelected = true
    }
  }

  func requestDeletion() {
    refreshRunningState()
    guard !isTargetRunning, !selectedItems.isEmpty else { return }
    showingConfirmation = true
  }

  func deleteSelectedItems() {
    let deletionPlan = selectedItems
    guard !deletionPlan.isEmpty else { return }

    showingConfirmation = false
    phase = .deleting
    errorMessage = nil
    Task {
      report = await trashService.moveToTrash(deletionPlan)
      phase = .finished
    }
  }

  func retryFailures() {
    guard let failures = report?.failures, !failures.isEmpty else { return }
    let paths = Set(failures.map { $0.url.standardizedFileURL.path })
    let retryItems = items.compactMap { item -> ApplicationCleanupItem? in
      guard paths.contains(item.url.standardizedFileURL.path) else { return nil }
      var selected = item
      selected.isSelected = true
      return selected
    }
    guard !retryItems.isEmpty else { return }

    let priorRemoved = report?.removed ?? []
    phase = .deleting
    Task {
      let retryReport = await trashService.moveToTrash(retryItems)
      let removedByPath = Dictionary(
        (priorRemoved + retryReport.removed).map { ($0.standardizedFileURL.path, $0) },
        uniquingKeysWith: { first, _ in first }
      )
      report = ApplicationDeletionReport(
        removed: Array(removedByPath.values),
        failures: retryReport.failures
      )
      phase = .finished
    }
  }

  func quitTargetApplication() {
    guard let bundleIdentifier = result?.application.bundleIdentifier else { return }
    for application in NSRunningApplication.runningApplications(
      withBundleIdentifier: bundleIdentifier
    ) {
      application.terminate()
    }

    Task {
      try? await Task.sleep(nanoseconds: 900_000_000)
      refreshRunningState()
    }
  }

  func reveal(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  private func refreshRunningState() {
    guard let bundleIdentifier = result?.application.bundleIdentifier else {
      isTargetRunning = false
      return
    }
    isTargetRunning = !NSRunningApplication.runningApplications(
      withBundleIdentifier: bundleIdentifier
    ).isEmpty
  }

  private func beginSecurityScopedAccess() {
    let candidates = [request.applicationURL] + SecurityScopedBookmarks.load().map(\.url)
    var seen = Set<String>()
    for url in candidates {
      let standardizedURL = url.standardizedFileURL
      guard seen.insert(standardizedURL.path).inserted else { continue }
      if standardizedURL.startAccessingSecurityScopedResource() {
        securityScopedURLs.append(standardizedURL)
      }
    }
  }

  private func folderAccessWarnings() -> [String] {
    let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    let hasHomeAccess = SecurityScopedBookmarks.load().contains { bookmark in
      let path = bookmark.url.standardizedFileURL.path
      return homePath == path || homePath.hasPrefix(path + "/")
    }
    if hasHomeAccess { return [] }
    return [
      "Grant access to your Home folder in RightOp Preferences to discover related user files."
    ]
  }
}
