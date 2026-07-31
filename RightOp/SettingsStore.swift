import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
  @Published private(set) var enabledActions: Set<RightOpAction>
  @Published var confirmPermanentDelete: Bool {
    didSet {
      defaults.set(confirmPermanentDelete, forKey: PreferenceKey.confirmPermanentDelete)
    }
  }
  @Published var terminalApplication: TerminalApplication {
    didSet {
      defaults.set(terminalApplication.rawValue, forKey: PreferenceKey.terminalApplication)
    }
  }
  @Published private(set) var authorizedFolderURLs: [URL]

  private let defaults: UserDefaults
  private var authorizedBookmarks: [SecurityScopedBookmark]

  init(defaults: UserDefaults = .rightOpShared) {
    self.defaults = defaults
    let snapshot = PreferencesSnapshot(defaults: defaults)
    enabledActions = snapshot.enabledActions
    confirmPermanentDelete = snapshot.confirmPermanentDelete
    terminalApplication = snapshot.terminalApplication
    authorizedBookmarks = SecurityScopedBookmarks.load(defaults: defaults)
    authorizedFolderURLs = authorizedBookmarks.map(\.url)
  }

  func isEnabled(_ action: RightOpAction) -> Bool {
    enabledActions.contains(action)
  }

  func setEnabled(_ isEnabled: Bool, for action: RightOpAction) {
    if isEnabled {
      enabledActions.insert(action)
    } else {
      enabledActions.remove(action)
    }
    defaults.set(enabledActions.map(\.rawValue).sorted(), forKey: PreferenceKey.enabledActions)
    objectWillChange.send()
  }

  func restoreDefaults() {
    enabledActions = Set(RightOpAction.allCases)
    confirmPermanentDelete = true
    terminalApplication = .terminal
    defaults.removeObject(forKey: PreferenceKey.enabledActions)
    defaults.removeObject(forKey: PreferenceKey.enabledActionsSchemaVersion)
    defaults.removeObject(forKey: PreferenceKey.confirmPermanentDelete)
    defaults.removeObject(forKey: PreferenceKey.terminalApplication)
    objectWillChange.send()
  }

  func addAuthorizedFolders(_ urls: [URL]) throws {
    for url in urls {
      let standardizedURL = url.standardizedFileURL
      guard
        !authorizedBookmarks.contains(where: {
          $0.url.standardizedFileURL.path == standardizedURL.path
        })
      else { continue }

      let data = try SecurityScopedBookmarks.make(for: standardizedURL)
      authorizedBookmarks.append(
        SecurityScopedBookmark(url: standardizedURL, data: data)
      )
    }
    persistAuthorizedFolders()
  }

  func removeAuthorizedFolder(_ url: URL) {
    authorizedBookmarks.removeAll {
      $0.url.standardizedFileURL.path == url.standardizedFileURL.path
    }
    persistAuthorizedFolders()
  }

  private func persistAuthorizedFolders() {
    SecurityScopedBookmarks.save(authorizedBookmarks, defaults: defaults)
    authorizedFolderURLs = authorizedBookmarks.map(\.url)
  }
}
