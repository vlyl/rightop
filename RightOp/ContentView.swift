import AppKit
import FinderSync
import SwiftUI

private enum AppSection: String, CaseIterable, Identifiable {
  case overview
  case actions
  case preferences

  var id: String { rawValue }

  var title: String {
    switch self {
    case .overview: "Overview"
    case .actions: "Menu Actions"
    case .preferences: "Preferences"
    }
  }

  var systemImage: String {
    switch self {
    case .overview: "sparkles"
    case .actions: "list.bullet.rectangle"
    case .preferences: "slider.horizontal.3"
    }
  }
}

struct ContentView: View {
  @State private var selection: AppSection? = .overview

  var body: some View {
    NavigationSplitView {
      List(AppSection.allCases, selection: $selection) { section in
        Label(section.title, systemImage: section.systemImage)
          .tag(section)
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 205)
      .safeAreaInset(edge: .bottom) {
        VStack(alignment: .leading, spacing: 4) {
          Text("RIGHTOP")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
          Text("Finder tools, one click away")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
      }
    } detail: {
      Group {
        switch selection ?? .overview {
        case .overview:
          OverviewView()
        case .actions:
          ActionsView()
        case .preferences:
          PreferencesView()
        }
      }
      .background(Color(nsColor: .windowBackgroundColor))
    }
    .tint(.indigo)
  }
}

private struct OverviewView: View {
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var settings: SettingsStore
  @State private var extensionEnabled = FIFinderSyncController.isExtensionEnabled

  private let benefits = [
    Benefit(
      title: "Clipboard-ready",
      detail: "Full paths, directory paths, names, and shell-safe paths without hidden shortcuts.",
      symbol: "doc.on.clipboard"
    ),
    Benefit(
      title: "Create in place",
      detail: "Start text and Markdown files in the folder you are already viewing.",
      symbol: "doc.badge.plus"
    ),
    Benefit(
      title: "Terminal shortcut",
      detail: "Open the current Finder location in Terminal, iTerm2, or Warp.",
      symbol: "terminal"
    ),
    Benefit(
      title: "Power tools",
      detail: "Checksums, hidden flags, and careful permanent deletion.",
      symbol: "wrench.and.screwdriver"
    ),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        hero

        VStack(alignment: .leading, spacing: 12) {
          Text("A smaller trip from thought to action")
            .font(.title2.bold())
          Text(
            "RightOp puts practical file operations directly in Finder’s contextual menu, with optional actions configurable."
          )
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

          LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
          ) {
            ForEach(benefits) { benefit in
              BenefitCard(benefit: benefit)
            }
          }
        }

        SetupCard(extensionEnabled: extensionEnabled, manageExtension: manageExtension)
        FolderAccessCard(
          folderCount: settings.authorizedFolderURLs.count,
          grantAccess: { requestFolderAccess(using: settings) }
        )
      }
      .padding(32)
      .frame(maxWidth: 820, alignment: .leading)
    }
    .navigationTitle("Overview")
    .onChange(of: scenePhase) { newValue in
      if newValue == .active {
        extensionEnabled = FIFinderSyncController.isExtensionEnabled
      }
    }
  }

  private var hero: some View {
    HStack(spacing: 22) {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .interpolation(.high)
        .frame(width: 112, height: 112)
        .shadow(color: .indigo.opacity(0.22), radius: 22, y: 10)

      VStack(alignment: .leading, spacing: 9) {
        Text("Right-click. Keep moving.")
          .font(.system(size: 32, weight: .bold, design: .rounded))
        Text(
          "A focused, open-source Finder extension for the file actions macOS makes you reach for."
        )
        .font(.title3)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

        StatusPill(isEnabled: extensionEnabled)
          .padding(.top, 3)
      }
    }
    .padding(24)
    .background {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(
          LinearGradient(
            colors: [
              Color.indigo.opacity(0.15),
              Color.blue.opacity(0.07),
              Color(nsColor: .controlBackgroundColor),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .overlay {
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(.indigo.opacity(0.16), lineWidth: 1)
        }
    }
  }

  private func manageExtension() {
    FIFinderSyncController.showExtensionManagementInterface()
  }
}

private struct ActionsView: View {
  @EnvironmentObject private var settings: SettingsStore

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        PageHeader(
          title: "Shape the menu",
          subtitle:
            "Only enabled actions appear in Finder. Changes are picked up the next time you open the context menu."
        )

        ForEach(ActionSection.allCases) { section in
          VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
              Text(section.title)
                .font(.headline)
              Text(section.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
              ForEach(actions(in: section)) { action in
                ActionToggleRow(
                  action: action,
                  isEnabled: Binding(
                    get: { settings.isEnabled(action) },
                    set: { settings.setEnabled($0, for: action) }
                  )
                )

                if action.id != actions(in: section).last?.id {
                  Divider()
                    .padding(.leading, 50)
                }
              }
            }
            .background {
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
            }
          }
        }
      }
      .padding(32)
      .frame(maxWidth: 800, alignment: .leading)
    }
    .navigationTitle("Menu Actions")
  }

  private func actions(in section: ActionSection) -> [RightOpAction] {
    RightOpAction.allCases.filter { $0.section == section }
  }
}

struct PreferencesView: View {
  @EnvironmentObject private var settings: SettingsStore

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        PageHeader(
          title: "Preferences",
          subtitle: "Choose the tools RightOp should use and keep destructive actions deliberate."
        )

        PreferenceGroup(title: "Terminal", symbol: "terminal") {
          Picker("Open directories in", selection: $settings.terminalApplication) {
            ForEach(TerminalApplication.allCases) { app in
              Text(app.title).tag(app)
            }
          }
          .pickerStyle(.segmented)

          Text("If the selected app is not installed, RightOp falls back to Apple Terminal.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        PreferenceGroup(title: "Safety", symbol: "checkmark.shield") {
          Toggle(
            "Confirm before permanent deletion",
            isOn: $settings.confirmPermanentDelete
          )
          Text(
            "Permanent deletion bypasses the Trash and cannot be undone. Keeping confirmation enabled is strongly recommended."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        PreferenceGroup(title: "Folder Access", symbol: "folder.badge.questionmark") {
          Text(
            "RightOp is sandboxed. Grant your Home folder—and any external volumes you use—so file-changing actions can work there."
          )
          .font(.callout)
          .foregroundStyle(.secondary)

          if settings.authorizedFolderURLs.isEmpty {
            Text("No folders have been authorized.")
              .font(.caption)
              .foregroundStyle(.orange)
          } else {
            VStack(spacing: 8) {
              ForEach(settings.authorizedFolderURLs, id: \.path) { url in
                HStack(spacing: 10) {
                  Image(systemName: "folder.fill")
                    .foregroundStyle(.indigo)
                  Text(url.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(url.path)
                  Spacer()
                  Button {
                    settings.removeAuthorizedFolder(url)
                  } label: {
                    Image(systemName: "xmark.circle.fill")
                      .foregroundStyle(.secondary)
                  }
                  .buttonStyle(.plain)
                  .help("Remove access")
                }
              }
            }
          }

          HStack {
            Spacer()
            Button("Grant Folder Access…") {
              requestFolderAccess(using: settings)
            }
          }
        }

        PreferenceGroup(title: "Reset", symbol: "arrow.counterclockwise") {
          HStack {
            Text("Restore every menu action and the recommended safety settings.")
              .foregroundStyle(.secondary)
            Spacer()
            Button("Restore Defaults") {
              settings.restoreDefaults()
            }
          }
        }
      }
      .padding(32)
      .frame(maxWidth: 760, alignment: .leading)
    }
    .navigationTitle("Preferences")
  }
}

private struct FolderAccessCard: View {
  let folderCount: Int
  let grantAccess: () -> Void

  var body: some View {
    HStack(spacing: 18) {
      Image(systemName: folderCount > 0 ? "folder.badge.checkmark" : "folder.badge.questionmark")
        .font(.system(size: 25, weight: .semibold))
        .foregroundStyle(folderCount > 0 ? .green : .orange)
        .frame(width: 44, height: 44)
        .background(
          (folderCount > 0 ? Color.green : Color.orange).opacity(0.1),
          in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )

      VStack(alignment: .leading, spacing: 3) {
        Text(folderCount > 0 ? "Folder access granted" : "Grant file access")
          .font(.headline)
        Text(
          folderCount > 0
            ? "RightOp can modify items inside \(folderCount) authorized folder\(folderCount == 1 ? "" : "s")."
            : "Choose your Home folder so sandboxed file actions can work there."
        )
        .foregroundStyle(.secondary)
      }

      Spacer()

      Button(folderCount > 0 ? "Add Folder…" : "Choose Folder…") {
        grantAccess()
      }
    }
    .padding(18)
    .background {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
    }
  }
}

private struct Benefit: Identifiable {
  let title: String
  let detail: String
  let symbol: String

  var id: String { title }
}

private struct BenefitCard: View {
  let benefit: Benefit

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: benefit.symbol)
        .font(.title3.weight(.semibold))
        .foregroundStyle(.indigo)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 4) {
        Text(benefit.title)
          .font(.headline)
        Text(benefit.detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
    .padding(16)
    .background {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
    }
  }
}

private struct StatusPill: View {
  let isEnabled: Bool

  var body: some View {
    Label(
      isEnabled ? "Finder extension enabled" : "Finder extension needs enabling",
      systemImage: isEnabled ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    )
    .font(.subheadline.weight(.semibold))
    .foregroundStyle(isEnabled ? .green : .orange)
    .padding(.horizontal, 11)
    .padding(.vertical, 6)
    .background((isEnabled ? Color.green : Color.orange).opacity(0.11), in: Capsule())
  }
}

private struct SetupCard: View {
  let extensionEnabled: Bool
  let manageExtension: () -> Void

  var body: some View {
    HStack(spacing: 18) {
      Image(systemName: extensionEnabled ? "checkmark.seal.fill" : "puzzlepiece.extension")
        .font(.system(size: 28, weight: .semibold))
        .foregroundStyle(extensionEnabled ? .green : .indigo)
        .frame(width: 44, height: 44)
        .background(
          (extensionEnabled ? Color.green : Color.indigo).opacity(0.1),
          in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )

      VStack(alignment: .leading, spacing: 3) {
        Text(extensionEnabled ? "You’re ready" : "One setup step")
          .font(.headline)
        Text(
          extensionEnabled
            ? "RightOp now appears when you right-click items or empty space in Finder."
            : "Enable RightOp under Finder Extensions in System Settings, then return here."
        )
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }

      Spacer()

      Button(extensionEnabled ? "Manage Extension" : "Enable Extension") {
        manageExtension()
      }
      .buttonStyle(.borderedProminent)
    }
    .padding(18)
    .background {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
    }
  }
}

private struct PageHeader: View {
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.system(size: 30, weight: .bold, design: .rounded))
      Text(subtitle)
        .font(.title3)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct ActionToggleRow: View {
  let action: RightOpAction
  @Binding var isEnabled: Bool

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: action.systemImage)
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(action == .permanentDelete ? .red : .indigo)
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 2) {
        Text(action.title)
          .font(.body.weight(.medium))
        Text(action.detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Spacer()

      Toggle("", isOn: $isEnabled)
        .labelsHidden()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}

private struct PreferenceGroup<Content: View>: View {
  let title: String
  let symbol: String
  let content: () -> Content

  init(
    title: String,
    symbol: String,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = title
    self.symbol = symbol
    self.content = content
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(title, systemImage: symbol)
        .font(.headline)
        .foregroundStyle(.primary)
      content()
    }
    .padding(18)
    .background {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
    }
  }
}

@MainActor
private func requestFolderAccess(using settings: SettingsStore) {
  let panel = NSOpenPanel()
  panel.title = "Grant RightOp Folder Access"
  panel.message =
    "Choose your Home folder for normal use. You can also add external volumes or other folders."
  panel.prompt = "Grant Access"
  panel.canChooseFiles = false
  panel.canChooseDirectories = true
  panel.allowsMultipleSelection = true
  panel.canCreateDirectories = false
  panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

  guard panel.runModal() == .OK else { return }

  do {
    try settings.addAuthorizedFolders(panel.urls)
  } catch {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Folder access could not be saved"
    alert.informativeText = error.localizedDescription
    alert.runModal()
  }
}
