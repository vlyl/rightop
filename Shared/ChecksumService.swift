import CryptoKit
import Foundation

enum ChecksumAlgorithm: String, Sendable {
  case sha256 = "SHA-256"
  case md5 = "MD5"
}

enum ChecksumService {
  private static let chunkSize = 1024 * 1024

  static func checksum(of url: URL, algorithm: ChecksumAlgorithm) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    switch algorithm {
    case .sha256:
      var hash = SHA256()
      while let data = try handle.read(upToCount: chunkSize), !data.isEmpty {
        hash.update(data: data)
      }
      return hash.finalize().map { String(format: "%02x", $0) }.joined()

    case .md5:
      var hash = Insecure.MD5()
      while let data = try handle.read(upToCount: chunkSize), !data.isEmpty {
        hash.update(data: data)
      }
      return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
  }
}
