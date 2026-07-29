import Foundation

enum AppConstants {
  static let appName = "RightOp"
  static let appGroupIdentifier = "group.dev.rightop.shared"
  static let appBundleIdentifier = "dev.rightop.app"
  static let extensionBundleIdentifier = "dev.rightop.app.finder-extension"
}

enum PreferenceKey {
  static let enabledActions = "enabledActions"
  static let confirmPermanentDelete = "confirmPermanentDelete"
  static let terminalApplication = "terminalApplication"
}

extension UserDefaults {
  static var rightOpShared: UserDefaults {
    UserDefaults(suiteName: AppConstants.appGroupIdentifier) ?? .standard
  }
}
