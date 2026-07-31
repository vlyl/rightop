import Foundation

enum ActionSection: String, CaseIterable, Identifiable {
  case clipboard
  case workflow
  case create
  case fileTools
  case dangerZone

  var id: String { rawValue }

  var title: String {
    switch self {
    case .clipboard: "Clipboard"
    case .workflow: "Workflow"
    case .create: "Create"
    case .fileTools: "File Tools"
    case .dangerZone: "Danger Zone"
    }
  }

  var subtitle: String {
    switch self {
    case .clipboard: "Paths and names, ready to paste"
    case .workflow: "Jump directly into your workflow"
    case .create: "Start files without opening another app"
    case .fileTools: "Small operations that save repeated trips"
    case .dangerZone: "Destructive actions with explicit safeguards"
    }
  }
}

enum RightOpAction: String, CaseIterable, Codable, Identifiable, Sendable {
  case copyDirectoryPath
  case copyFileName
  case copyShellPath
  case openInTerminal
  case newTextFile
  case newMarkdownFile
  case toggleHidden
  case sha256
  case md5
  case uninstallApplication
  case permanentDelete

  var id: String { rawValue }

  var title: String {
    switch self {
    case .copyDirectoryPath: "Copy Directory Path"
    case .copyFileName: "Copy Name"
    case .copyShellPath: "Copy Shell-Escaped Path"
    case .openInTerminal: "Open in Terminal"
    case .newTextFile: "New Text File"
    case .newMarkdownFile: "New Markdown File"
    case .toggleHidden: "Hide or Unhide"
    case .sha256: "Copy SHA-256"
    case .md5: "Copy MD5"
    case .uninstallApplication: "Uninstall App"
    case .permanentDelete: "Permanently Delete"
    }
  }

  var detail: String {
    switch self {
    case .copyDirectoryPath:
      "Copies the containing directory, or the folder itself."
    case .copyFileName:
      "Copies file names without their parent paths."
    case .copyShellPath:
      "Quotes paths so spaces and apostrophes are safe in a shell."
    case .openInTerminal:
      "Opens the current directory in your preferred terminal."
    case .newTextFile:
      "Creates an empty, uniquely named .txt file in this folder."
    case .newMarkdownFile:
      "Creates an empty, uniquely named .md file in this folder."
    case .toggleHidden:
      "Toggles Finder's hidden flag for the selected items."
    case .sha256:
      "Calculates and copies SHA-256 checksums for selected files."
    case .md5:
      "Calculates and copies legacy MD5 checksums when needed."
    case .uninstallApplication:
      "Reviews an app and related files before moving selected items to the Trash."
    case .permanentDelete:
      "Deletes immediately without using the Trash."
    }
  }

  var systemImage: String {
    switch self {
    case .copyDirectoryPath: "folder.badge.gearshape"
    case .copyFileName: "textformat"
    case .copyShellPath: "terminal"
    case .openInTerminal: "terminal"
    case .newTextFile: "doc.badge.plus"
    case .newMarkdownFile: "doc.badge.plus"
    case .toggleHidden: "eye.slash"
    case .sha256: "checkmark.seal"
    case .md5: "number"
    case .uninstallApplication: "trash.circle"
    case .permanentDelete: "trash.slash"
    }
  }

  var section: ActionSection {
    switch self {
    case .copyDirectoryPath, .copyFileName, .copyShellPath:
      .clipboard
    case .openInTerminal:
      .workflow
    case .newTextFile, .newMarkdownFile:
      .create
    case .toggleHidden, .sha256, .md5:
      .fileTools
    case .uninstallApplication, .permanentDelete:
      .dangerZone
    }
  }
}

enum TerminalApplication: String, CaseIterable, Identifiable, Sendable {
  case terminal
  case iTerm
  case warp

  var id: String { rawValue }

  var title: String {
    switch self {
    case .terminal: "Terminal"
    case .iTerm: "iTerm2"
    case .warp: "Warp"
    }
  }

  var bundleIdentifier: String {
    switch self {
    case .terminal: "com.apple.Terminal"
    case .iTerm: "com.googlecode.iterm2"
    case .warp: "dev.warp.Warp-Stable"
    }
  }
}

struct PreferencesSnapshot: Sendable {
  private static let currentActionSchemaVersion = 1

  let enabledActions: Set<RightOpAction>
  let confirmPermanentDelete: Bool
  let terminalApplication: TerminalApplication

  init(defaults: UserDefaults = .rightOpShared) {
    var actions: Set<RightOpAction>
    if let rawValues = defaults.array(forKey: PreferenceKey.enabledActions) as? [String] {
      actions = Set(rawValues.compactMap(RightOpAction.init(rawValue:)))
    } else {
      actions = Set(RightOpAction.allCases)
    }

    if defaults.integer(forKey: PreferenceKey.enabledActionsSchemaVersion)
      < Self.currentActionSchemaVersion
    {
      actions.insert(.uninstallApplication)
      defaults.set(actions.map(\.rawValue).sorted(), forKey: PreferenceKey.enabledActions)
      defaults.set(
        Self.currentActionSchemaVersion,
        forKey: PreferenceKey.enabledActionsSchemaVersion
      )
    }
    enabledActions = actions

    if defaults.object(forKey: PreferenceKey.confirmPermanentDelete) == nil {
      confirmPermanentDelete = true
    } else {
      confirmPermanentDelete = defaults.bool(forKey: PreferenceKey.confirmPermanentDelete)
    }

    let terminalValue = defaults.string(forKey: PreferenceKey.terminalApplication)
    terminalApplication = TerminalApplication(rawValue: terminalValue ?? "") ?? .terminal
  }

  func isEnabled(_ action: RightOpAction) -> Bool {
    enabledActions.contains(action)
  }
}
