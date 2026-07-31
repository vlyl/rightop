import AppKit
import SwiftUI

struct ApplicationUninstallView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var model: ApplicationUninstaller

  init(request: ApplicationUninstallRequest) {
    _model = StateObject(wrappedValue: ApplicationUninstaller(request: request))
  }

  var body: some View {
    VStack(spacing: 0) {
      switch model.phase {
      case .scanning:
        scanningView
      case .ready:
        reviewView
      case .deleting:
        deletingView
      case .finished:
        finishedView
      case .failed:
        failedView
      }
    }
    .frame(width: 780, height: 620)
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear { model.start() }
    .interactiveDismissDisabled(model.phase == .deleting)
    .alert("Move selected items to the Trash?", isPresented: $model.showingConfirmation) {
      Button("Move to Trash", role: .destructive) {
        model.deleteSelectedItems()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "RightOp will move \(model.selectedCount) selected item\(model.selectedCount == 1 ? "" : "s") to the Trash. Review the paths before continuing."
      )
    }
  }

  private var scanningView: some View {
    VStack(spacing: 20) {
      Spacer()
      ProgressView()
        .controlSize(.large)
      Text("Finding related files…")
        .font(.title2.bold())
      Text("Checking the app bundle, preferences, caches, containers, logs, and helpers.")
        .foregroundStyle(.secondary)
      Spacer()
      Button("Cancel") { dismiss() }
        .padding(.bottom, 24)
    }
  }

  private var reviewView: some View {
    VStack(spacing: 0) {
      if let application = model.result?.application {
        applicationSummary(application)
      }

      Divider()

      if model.isTargetRunning {
        runningApplicationWarning
        Divider()
      }

      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Review before uninstalling")
            .font(.headline)
          Text(
            "\(model.items.count) item\(model.items.count == 1 ? "" : "s") found · \(model.reviewCount) suggestion\(model.reviewCount == 1 ? "" : "s") need review"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Spacer()

        Menu {
          Button("Select exact matches") { model.selectExactMatches() }
          Button("Select everything") { model.selectEverything() }
        } label: {
          Label("Selection", systemImage: "checklist")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
      }
      .padding(.horizontal, 22)
      .padding(.vertical, 13)

      ScrollView {
        LazyVStack(spacing: 8) {
          ForEach(model.items) { item in
            ApplicationCleanupRow(
              item: item,
              isSelected: Binding(
                get: {
                  model.items.first(where: { $0.id == item.id })?.isSelected ?? false
                },
                set: { model.setSelected($0, for: item.id) }
              ),
              reveal: { model.reveal(item.url) }
            )
          }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
      }

      if let warnings = model.result?.warnings, !warnings.isEmpty {
        HStack(alignment: .top, spacing: 9) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text(warnings.joined(separator: " "))
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
      }

      Divider()
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("\(model.selectedCount) selected")
            .font(.subheadline.bold())
          Text(ByteCountFormatter.string(fromByteCount: model.selectedSize, countStyle: .file))
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Text("Items remain recoverable in the Trash")
          .font(.caption)
          .foregroundStyle(.secondary)

        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)

        Button {
          model.requestDeletion()
        } label: {
          Label("Move to Trash", systemImage: "trash")
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(model.selectedCount == 0 || model.isTargetRunning)
      }
      .padding(.horizontal, 22)
      .padding(.vertical, 14)
      .background(.ultraThinMaterial)
    }
  }

  private func applicationSummary(_ application: ApplicationIdentity) -> some View {
    HStack(spacing: 15) {
      Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
        .resizable()
        .interpolation(.high)
        .frame(width: 52, height: 52)

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 7) {
          Text(application.displayName)
            .font(.title2.bold())
          if let version = application.version {
            Text("v\(version)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Text(application.bundleIdentifier)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
        Text(application.url.path)
          .font(.caption2)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer()

      VStack(alignment: .trailing, spacing: 2) {
        Text(
          ByteCountFormatter.string(
            fromByteCount: model.items.reduce(0) { $0 + $1.allocatedSize },
            countStyle: .file
          )
        )
        .font(.title3.bold())
        Text("total found")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 16)
  }

  private var runningApplicationWarning: some View {
    HStack(spacing: 10) {
      Image(systemName: "exclamationmark.octagon.fill")
        .foregroundStyle(.orange)
      VStack(alignment: .leading, spacing: 2) {
        Text("The application is still running")
          .font(.subheadline.bold())
        Text("Quit it first so it cannot recreate files while being removed.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Quit App") { model.quitTargetApplication() }
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 10)
    .background(Color.orange.opacity(0.08))
  }

  private var deletingView: some View {
    VStack(spacing: 18) {
      Spacer()
      ProgressView()
        .controlSize(.large)
      Text("Moving selected items to the Trash…")
        .font(.title2.bold())
      Text("macOS may ask for administrator approval when removing protected applications.")
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Spacer()
    }
    .padding(30)
  }

  private var finishedView: some View {
    VStack(spacing: 22) {
      Spacer()

      Image(
        systemName: model.report?.failures.isEmpty == true
          ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
      )
      .font(.system(size: 58))
      .foregroundStyle(model.report?.failures.isEmpty == true ? .green : .orange)

      VStack(spacing: 6) {
        Text(
          model.report?.failures.isEmpty == true
            ? "Uninstall complete" : "Some items could not be removed"
        )
        .font(.title.bold())
        Text(finishedSummary)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      if let failures = model.report?.failures, !failures.isEmpty {
        ScrollView {
          VStack(alignment: .leading, spacing: 9) {
            ForEach(failures) { failure in
              VStack(alignment: .leading, spacing: 2) {
                Text(failure.url.path)
                  .font(.caption.bold())
                  .lineLimit(1)
                  .truncationMode(.middle)
                Text(failure.message)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
        .frame(maxWidth: 600, maxHeight: 150)
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

        Button("Try Again") { model.retryFailures() }
          .buttonStyle(.borderedProminent)
      }

      Button("Close") { dismiss() }
        .keyboardShortcut(.defaultAction)

      Spacer()
    }
    .padding(30)
  }

  private var failedView: some View {
    VStack(spacing: 18) {
      Spacer()
      Image(systemName: "xmark.octagon.fill")
        .font(.system(size: 52))
        .foregroundStyle(.red)
      Text("Unable to inspect this application")
        .font(.title2.bold())
      Text(model.errorMessage ?? "An unknown error occurred.")
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Button("Close") { dismiss() }
        .keyboardShortcut(.defaultAction)
      Spacer()
    }
    .padding(30)
  }

  private var finishedSummary: String {
    guard let report = model.report else { return "" }
    if report.failures.isEmpty {
      return
        "\(report.removed.count) item\(report.removed.count == 1 ? " was" : "s were") moved to the Trash."
    }
    return
      "\(report.removed.count) item\(report.removed.count == 1 ? "" : "s") removed; \(report.failures.count) could not be moved."
  }
}

private struct ApplicationCleanupRow: View {
  let item: ApplicationCleanupItem
  @Binding var isSelected: Bool
  let reveal: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Toggle("", isOn: $isSelected)
        .labelsHidden()
        .disabled(item.isApplication)

      Image(systemName: categoryIcon)
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(categoryColor)
        .frame(width: 32, height: 32)
        .background(categoryColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(item.url.lastPathComponent)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
          Text(item.category.title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
          if item.requiresElevatedAccess {
            Image(systemName: "lock.fill")
              .font(.caption2)
              .foregroundStyle(.orange)
          }
        }
        Text(item.url.deletingLastPathComponent().path)
          .font(.caption2)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
          .truncationMode(.middle)
        Text(item.reason)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 3) {
        Text(ByteCountFormatter.string(fromByteCount: item.allocatedSize, countStyle: .file))
          .font(.caption)
        Text(item.confidence.title)
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(item.confidence == .exact ? .green : .orange)
      }

      Button(action: reveal) {
        Image(systemName: "arrow.right.circle")
      }
      .buttonStyle(.borderless)
      .help("Show in Finder")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
    )
    .opacity(isSelected ? 1 : 0.58)
  }

  private var categoryIcon: String {
    switch item.category {
    case .application: "app.fill"
    case .applicationSupport: "shippingbox.fill"
    case .caches: "bolt.horizontal.circle.fill"
    case .preferences: "slider.horizontal.3"
    case .containers: "cube.box.fill"
    case .savedState: "clock.arrow.circlepath"
    case .webData: "globe"
    case .logs: "doc.text.fill"
    case .helpers: "gearshape.2.fill"
    case .other: "doc.fill"
    }
  }

  private var categoryColor: Color {
    switch item.category {
    case .application: .red
    case .applicationSupport: .blue
    case .caches: .orange
    case .preferences: .purple
    case .containers: .indigo
    case .savedState: .cyan
    case .webData: .teal
    case .logs: .gray
    case .helpers: .pink
    case .other: .secondary
    }
  }
}
