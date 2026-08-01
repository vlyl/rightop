import Foundation
import Testing

@testable import RightOpCore

struct ApplicationUninstallTests {
  private let scanner = ApplicationUninstallScanner()

  @Test
  func bundleIdentifierMatchingUsesBoundaries() {
    let match = scanner.match(
      fileName: "com.example.product.savedState",
      bundleIdentifier: "com.example.product",
      identifiers: ["Product"]
    )

    #expect(match?.confidence == .exact)
  }

  @Test
  func partialBundleIdentifierDoesNotMatch() {
    let match = scanner.match(
      fileName: "com.example.productivity.plist",
      bundleIdentifier: "com.example.product",
      identifiers: ["Product"]
    )

    #expect(match == nil)
  }

  @Test
  func nameSuggestionsRequireBoundaries() {
    let exactName = scanner.match(
      fileName: "My Editor",
      bundleIdentifier: "com.example.editor",
      identifiers: ["My Editor"]
    )
    let unrelated = scanner.match(
      fileName: "My Editorial Archive",
      bundleIdentifier: "com.example.editor",
      identifiers: ["My Editor"]
    )

    #expect(exactName?.confidence == .likely)
    #expect(unrelated == nil)
  }

  @Test
  func unsafeBundleIdentifiersAreRejected() {
    #expect(ApplicationUninstallScanner.isSafeBundleIdentifier("com.example.editor"))
    #expect(ApplicationUninstallScanner.isSafeBundleIdentifier("com.example.my-app"))
    #expect(!ApplicationUninstallScanner.isSafeBundleIdentifier("../../Documents"))
    #expect(!ApplicationUninstallScanner.isSafeBundleIdentifier("com.example/escape"))
    #expect(!ApplicationUninstallScanner.isSafeBundleIdentifier("com..example"))
  }

  @Test
  func nestedCleanupPathsCollapseToTheirParent() {
    let urls = [
      URL(fileURLWithPath: "/tmp/RightOp/App"),
      URL(fileURLWithPath: "/tmp/RightOp/App/Contents/file"),
      URL(fileURLWithPath: "/tmp/RightOp/Other"),
    ]

    #expect(
      ApplicationUninstallScanner.collapsedURLs(urls).map(\.path).sorted() == [
        "/tmp/RightOp/App",
        "/tmp/RightOp/Other",
      ])
  }

  @Test
  func uninstallRequestURLAcceptsOnlyExpectedSchemeAndHost() {
    let identifier = UUID()

    #expect(
      ApplicationUninstallRequestStore.requestIdentifier(
        from: URL(string: "rightop://uninstall/\(identifier.uuidString)")!
      ) == identifier
    )
    #expect(
      ApplicationUninstallRequestStore.requestIdentifier(
        from: URL(string: "https://uninstall/\(identifier.uuidString)")!
      ) == nil
    )
  }

  @Test
  func applicationMenuDetectionRequiresANonSymlinkDirectory() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("RightOpTests-\(UUID().uuidString)", isDirectory: true)
    let application = root.appendingPathComponent("Fixture.app", isDirectory: true)
    let regularFile = root.appendingPathComponent("Document.app")
    let symbolicLink = root.appendingPathComponent("Linked.app")
    try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
    try Data().write(to: regularFile)
    try FileManager.default.createSymbolicLink(at: symbolicLink, withDestinationURL: application)
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(ApplicationUninstallRequestStore.isApplicationBundle(application))
    #expect(!ApplicationUninstallRequestStore.isApplicationBundle(regularFile))
    #expect(!ApplicationUninstallRequestStore.isApplicationBundle(symbolicLink))
  }

  @Test
  func uninstallMenuIsFinderOnlyAndDoesNotRequireFileSystemAccess() {
    let missingApplication = URL(fileURLWithPath: "/Applications/Does Not Exist.app")

    #expect(
      ApplicationUninstallMenuPolicy.shouldOffer(
        for: [missingApplication],
        frontmostApplicationBundleIdentifier: "com.apple.finder"
      )
    )
    #expect(
      !ApplicationUninstallMenuPolicy.shouldOffer(
        for: [missingApplication],
        frontmostApplicationBundleIdentifier: "com.example.file-picker-host"
      )
    )
    #expect(
      !ApplicationUninstallMenuPolicy.shouldOffer(
        for: [URL(fileURLWithPath: "/Applications/Document.txt")],
        frontmostApplicationBundleIdentifier: "com.apple.finder"
      )
    )
  }

  @Test
  func existingPreferencesEnableNewUninstallActionOnce() {
    let suiteName = "RightOpCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set([RightOpAction.copyFileName.rawValue], forKey: PreferenceKey.enabledActions)

    let migrated = PreferencesSnapshot(defaults: defaults)
    #expect(migrated.isEnabled(.uninstallApplication))

    defaults.set(
      [RightOpAction.copyFileName.rawValue],
      forKey: PreferenceKey.enabledActions
    )
    let afterUserDisablesIt = PreferencesSnapshot(defaults: defaults)
    #expect(!afterUserDisablesIt.isEnabled(.uninstallApplication))
  }

}
