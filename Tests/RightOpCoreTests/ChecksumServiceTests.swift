import Foundation
import Testing

@testable import RightOpCore

struct ChecksumServiceTests {
  @Test
  func testKnownSHA256() throws {
    let file = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try Data("abc".utf8).write(to: file)

    #expect(
      try ChecksumService.checksum(of: file, algorithm: .sha256)
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
  }

  @Test
  func testKnownMD5() throws {
    let file = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try Data("abc".utf8).write(to: file)

    #expect(
      try ChecksumService.checksum(of: file, algorithm: .md5)
        == "900150983cd24fb0d6963f7d28e17f72"
    )
  }
}
