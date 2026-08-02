import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
  private let controller = FIFinderSyncController.default()
  private var securityScopedURLs = [URL]()

  override init() {
    super.init()

    // Finder Sync only contributes menus inside registered roots. Monitoring
    // the filesystem root makes RightOp available in normal Finder locations
    // and on mounted external volumes.
    controller.directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
  }

  deinit {
    for url in securityScopedURLs {
      url.stopAccessingSecurityScopedResource()
    }
  }

  override var toolbarItemName: String {
    AppConstants.appName
  }

  override var toolbarItemToolTip: String {
    "Useful actions for the current Finder location"
  }

  override var toolbarItemImage: NSImage {
    NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: AppConstants.appName)
      ?? NSImage(size: NSSize(width: 18, height: 18))
  }

  override func menu(for menuKind: FIMenuKind) -> NSMenu? {
    let preferences = PreferencesSnapshot()
    let selectedURLs = controller.selectedItemURLs() ?? []
    let targetURL = controller.targetedURL()
    let hasContext = !selectedURLs.isEmpty || targetURL != nil

    let menu = NSMenu(title: AppConstants.appName)

    addClipboardActions(
      to: menu,
      preferences: preferences,
      hasSelection: !selectedURLs.isEmpty,
      hasTarget: targetURL != nil
    )

    addWorkflowActions(
      to: menu,
      preferences: preferences,
      hasContext: hasContext
    )

    addCreationActions(
      to: menu,
      preferences: preferences,
      hasContext: hasContext
    )

    addFileTools(
      to: menu,
      preferences: preferences,
      selectedURLs: selectedURLs
    )

    if preferences.isEnabled(.uninstallApplication),
      ApplicationUninstallMenuPolicy.shouldOffer(
        for: selectedURLs,
        frontmostApplicationBundleIdentifier: NSWorkspace.shared.frontmostApplication?
          .bundleIdentifier
      )
    {
      menu.addItem(
        menuItem(
          "Uninstall App…",
          action: #selector(uninstallApplication(_:)),
          symbol: "trash.circle"
        )
      )
    }

    if !selectedURLs.isEmpty, preferences.isEnabled(.permanentDelete) {
      menu.addItem(
        menuItem(
          "Permanently Delete…",
          action: #selector(permanentlyDelete(_:)),
          symbol: "trash.slash"
        )
      )
    }

    menu.addItem(
      menuItem(
        "RightOp Settings…",
        action: #selector(openSettings(_:)),
        symbol: "gearshape"
      )
    )

    return menu
  }

  private func addClipboardActions(
    to menu: NSMenu,
    preferences: PreferencesSnapshot,
    hasSelection: Bool,
    hasTarget: Bool
  ) {
    guard hasSelection || hasTarget else { return }

    menu.addItem(
      menuItem("Copy Path", action: #selector(copyPaths(_:)), symbol: "doc.on.doc")
    )

    if preferences.isEnabled(.copyDirectoryPath) {
      menu.addItem(
        menuItem(
          "Copy Directory Path",
          action: #selector(copyDirectoryPaths(_:)),
          symbol: "folder.badge.gearshape"
        )
      )
    }

    if hasSelection, preferences.isEnabled(.copyFileName) {
      menu.addItem(
        menuItem("Copy Name", action: #selector(copyNames(_:)), symbol: "textformat")
      )
    }

    if preferences.isEnabled(.copyShellPath) {
      menu.addItem(
        menuItem(
          "Copy Shell-Escaped Path",
          action: #selector(copyShellPaths(_:)),
          symbol: "terminal"
        )
      )
    }
  }

  private func addWorkflowActions(
    to menu: NSMenu,
    preferences: PreferencesSnapshot,
    hasContext: Bool
  ) {
    if hasContext, preferences.isEnabled(.openInTerminal) {
      menu.addItem(
        menuItem(
          "Open in \(preferences.terminalApplication.title)",
          action: #selector(openInTerminal(_:)),
          symbol: "terminal"
        )
      )
    }
  }

  private func addCreationActions(
    to menu: NSMenu,
    preferences: PreferencesSnapshot,
    hasContext: Bool
  ) {
    guard hasContext else { return }

    if preferences.isEnabled(.newTextFile) {
      menu.addItem(
        menuItem(
          "New Text File",
          action: #selector(createTextFile(_:)),
          symbol: "doc.badge.plus"
        )
      )
    }
    if preferences.isEnabled(.newMarkdownFile) {
      menu.addItem(
        menuItem(
          "New Markdown File",
          action: #selector(createMarkdownFile(_:)),
          symbol: "doc.badge.plus"
        )
      )
    }
  }

  private func addFileTools(
    to menu: NSMenu,
    preferences: PreferencesSnapshot,
    selectedURLs: [URL]
  ) {
    guard !selectedURLs.isEmpty else { return }

    if preferences.isEnabled(.toggleHidden) {
      menu.addItem(
        menuItem(
          "Hide or Unhide",
          action: #selector(toggleHidden(_:)),
          symbol: "eye.slash"
        )
      )
    }

    if preferences.isEnabled(.sha256) || preferences.isEnabled(.md5) {
      if preferences.isEnabled(.sha256) {
        menu.addItem(
          menuItem(
            "Copy SHA-256",
            action: #selector(copySHA256(_:)),
            symbol: "checkmark.seal"
          )
        )
      }
      if preferences.isEnabled(.md5) {
        menu.addItem(
          menuItem("Copy MD5", action: #selector(copyMD5(_:)), symbol: "number")
        )
      }
    }
  }

  @objc private func copyPaths(_ sender: Any?) {
    copyToPasteboard(selectedOrTargetedURLs().map(\.path).joined(separator: "\n"))
  }

  @objc private func copyDirectoryPaths(_ sender: Any?) {
    activateAuthorizedFolderAccess()
    let directories = PathFormatting.uniqueDirectories(for: selectedOrTargetedURLs())
    copyToPasteboard(directories.map(\.path).joined(separator: "\n"))
  }

  @objc private func copyNames(_ sender: Any?) {
    copyToPasteboard(selectedURLs().map(\.lastPathComponent).joined(separator: "\n"))
  }

  @objc private func copyShellPaths(_ sender: Any?) {
    let value = selectedOrTargetedURLs()
      .map { PathFormatting.shellQuote($0.path) }
      .joined(separator: " ")
    copyToPasteboard(value)
  }

  @objc private func openInTerminal(_ sender: Any?) {
    activateAuthorizedFolderAccess()
    guard
      let directory = contextDirectory(
        selection: selectedURLs(),
        target: controller.targetedURL()
      )
    else { return }

    let preference = PreferencesSnapshot().terminalApplication
    let workspace = NSWorkspace.shared
    let preferredApp = workspace.urlForApplication(
      withBundleIdentifier: preference.bundleIdentifier)
    let terminalApp = workspace.urlForApplication(
      withBundleIdentifier: TerminalApplication.terminal.bundleIdentifier)

    guard let applicationURL = preferredApp ?? terminalApp else {
      showError("Terminal could not be found.")
      return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    workspace.open(
      [directory],
      withApplicationAt: applicationURL,
      configuration: configuration
    ) { [weak self] _, error in
      if let error {
        self?.showError(error.localizedDescription)
      }
    }
  }

  @objc private func createTextFile(_ sender: Any?) {
    createFile(named: "Untitled.txt")
  }

  @objc private func createMarkdownFile(_ sender: Any?) {
    createFile(named: "Untitled.md")
  }

  @objc private func toggleHidden(_ sender: Any?) {
    activateAuthorizedFolderAccess()
    let urls = selectedURLs()
    let shouldHide = !urls.allSatisfy(isHidden)

    performFileOperation("The hidden flag could not be changed.") {
      for originalURL in urls {
        var url = originalURL
        var values = URLResourceValues()
        values.isHidden = shouldHide
        try url.setResourceValues(values)
      }
    }
  }

  @objc private func copySHA256(_ sender: Any?) {
    copyChecksums(.sha256)
  }

  @objc private func copyMD5(_ sender: Any?) {
    copyChecksums(.md5)
  }

  @objc private func permanentlyDelete(_ sender: Any?) {
    activateAuthorizedFolderAccess()
    let urls = selectedURLs()
    guard !urls.isEmpty else { return }

    let preferences = PreferencesSnapshot()
    if preferences.confirmPermanentDelete, !confirmPermanentDeletion(of: urls) {
      return
    }

    performFileOperation("One or more items could not be permanently deleted.") {
      for url in urls {
        try FileManager.default.removeItem(at: url)
      }
    }
  }

  @objc private func uninstallApplication(_ sender: Any?) {
    activateAuthorizedFolderAccess()
    let urls = selectedURLs()
    guard
      ApplicationUninstallMenuPolicy.shouldOffer(
        for: urls,
        frontmostApplicationBundleIdentifier: NSWorkspace.shared.frontmostApplication?
          .bundleIdentifier
      ),
      ApplicationUninstallRequestStore.isApplicationBundle(urls[0])
    else { return }

    do {
      let requestURL = try ApplicationUninstallRequestStore.create(for: urls[0])
      guard let appURL = containingApplicationURL() else {
        ApplicationUninstallRequestStore.discard(requestURL)
        showError("The RightOp application could not be found.")
        return
      }

      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      NSWorkspace.shared.open(
        [requestURL],
        withApplicationAt: appURL,
        configuration: configuration
      ) { [weak self] _, error in
        if let error {
          ApplicationUninstallRequestStore.discard(requestURL)
          self?.showError(
            "The uninstall review could not be opened.\n\n\(error.localizedDescription)"
          )
        }
      }
    } catch {
      showError("The uninstall review could not be prepared.\n\n\(error.localizedDescription)")
    }
  }

  @objc private func openSettings(_ sender: Any?) {
    guard let appURL = containingApplicationURL() else {
      showError("The RightOp application could not be found.")
      return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(
      at: appURL,
      configuration: configuration,
      completionHandler: nil
    )
  }

  private func createFile(named preferredName: String) {
    activateAuthorizedFolderAccess()
    guard
      let directory = contextDirectory(
        selection: selectedURLs(),
        target: controller.targetedURL()
      )
    else { return }

    performFileOperation("The file could not be created.") {
      let destination = FileNaming.uniqueFileURL(
        in: directory,
        preferredName: preferredName
      )
      try Data().write(to: destination, options: .atomic)
      NSWorkspace.shared.activateFileViewerSelecting([destination])
    }
  }

  private func copyChecksums(_ algorithm: ChecksumAlgorithm) {
    activateAuthorizedFolderAccess()
    let files = selectedURLs().filter(isRegularFile)
    guard !files.isEmpty else { return }

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        let values = try files.map { url in
          (try ChecksumService.checksum(of: url, algorithm: algorithm), url)
        }
        let output: String
        if values.count == 1 {
          output = values[0].0
        } else {
          output =
            values
            .map { "\($0.0)  \($0.1.lastPathComponent)" }
            .joined(separator: "\n")
        }

        DispatchQueue.main.async {
          self?.copyToPasteboard(output)
        }
      } catch {
        DispatchQueue.main.async {
          self?.showError("The checksum could not be calculated.\n\n\(error.localizedDescription)")
        }
      }
    }
  }

  private func selectedURLs() -> [URL] {
    controller.selectedItemURLs() ?? []
  }

  private func selectedOrTargetedURLs() -> [URL] {
    let selected = selectedURLs()
    if !selected.isEmpty { return selected }
    if let target = controller.targetedURL() { return [target] }
    return []
  }

  private func contextDirectory(selection: [URL], target: URL?) -> URL? {
    if let first = selection.first {
      return PathFormatting.directory(for: first)
    }
    if let target {
      return PathFormatting.directory(for: target)
    }
    return nil
  }

  private func isRegularFile(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
  }

  private func isHidden(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isHiddenKey]).isHidden) ?? false
  }

  private func containingApplicationURL() -> URL? {
    let applicationURL = Bundle(for: FinderSync.self).bundleURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .standardizedFileURL
    guard
      applicationURL.pathExtension.lowercased() == "app",
      Bundle(url: applicationURL)?.bundleIdentifier == AppConstants.appBundleIdentifier
    else { return nil }
    return applicationURL
  }

  private func copyToPasteboard(_ string: String) {
    guard !string.isEmpty else { return }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(string, forType: .string)
  }

  private func performFileOperation(_ message: String, operation: () throws -> Void) {
    do {
      try operation()
    } catch {
      showError("\(message)\n\n\(error.localizedDescription)")
    }
  }

  private func confirmPermanentDeletion(of urls: [URL]) -> Bool {
    NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText =
      urls.count == 1
      ? "Permanently delete “\(urls[0].lastPathComponent)”?"
      : "Permanently delete \(urls.count) items?"
    alert.informativeText = "This bypasses the Trash and cannot be undone."
    alert.addButton(withTitle: "Delete Permanently")
    alert.addButton(withTitle: "Cancel")
    alert.buttons.first?.hasDestructiveAction = true
    return alert.runModal() == .alertFirstButtonReturn
  }

  private func showError(_ message: String) {
    DispatchQueue.main.async {
      NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = "RightOp"
      alert.informativeText = message
      alert.addButton(withTitle: "OK")
      alert.runModal()
    }
  }

  private func menuItem(
    _ title: String,
    action: Selector,
    symbol: String
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.image = menuImage(symbol)
    return item
  }

  private func menuImage(_ symbol: String) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    let image = NSImage(
      systemSymbolName: symbol,
      accessibilityDescription: nil
    )?.withSymbolConfiguration(configuration)
    image?.size = NSSize(width: 16, height: 16)
    return image
  }

  private func activateAuthorizedFolderAccess() {
    // Never call this from init or menu(for:). Finder Sync is also hosted by
    // other applications' open/save panels, where eager bookmark access causes
    // macOS to request App Data permission before the user chooses an action.
    for url in securityScopedURLs {
      url.stopAccessingSecurityScopedResource()
    }

    securityScopedURLs = SecurityScopedBookmarks.load()
      .map(\.url)
      .filter { $0.startAccessingSecurityScopedResource() }
  }
}
