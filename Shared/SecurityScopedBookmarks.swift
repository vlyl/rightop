import Foundation

struct SecurityScopedBookmark {
  let url: URL
  let data: Data
}

enum SecurityScopedBookmarks {
  static let defaultsKey = "authorizedFolderBookmarks"

  static func make(for url: URL) throws -> Data {
    try url.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
  }

  static func load(defaults: UserDefaults = .rightOpShared) -> [SecurityScopedBookmark] {
    let bookmarkData = defaults.array(forKey: defaultsKey) as? [Data] ?? []

    return bookmarkData.compactMap { data in
      var isStale = false
      guard
        let url = try? URL(
          resolvingBookmarkData: data,
          options: [.withSecurityScope, .withoutUI],
          relativeTo: nil,
          bookmarkDataIsStale: &isStale
        )
      else {
        return nil
      }

      if isStale, let refreshedData = try? make(for: url) {
        return SecurityScopedBookmark(url: url, data: refreshedData)
      }
      return SecurityScopedBookmark(url: url, data: data)
    }
  }

  static func save(
    _ bookmarks: [SecurityScopedBookmark],
    defaults: UserDefaults = .rightOpShared
  ) {
    var seen = Set<String>()
    let uniqueData = bookmarks.compactMap { bookmark -> Data? in
      let path = bookmark.url.standardizedFileURL.path
      return seen.insert(path).inserted ? bookmark.data : nil
    }
    defaults.set(uniqueData, forKey: defaultsKey)
  }
}
