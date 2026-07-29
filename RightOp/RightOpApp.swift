import SwiftUI

@main
struct RightOpApp: App {
  @StateObject private var settings = SettingsStore()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(settings)
        .frame(minWidth: 820, minHeight: 560)
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 940, height: 650)

    Settings {
      PreferencesView()
        .environmentObject(settings)
        .frame(width: 560, height: 360)
    }
  }
}
