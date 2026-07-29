import Foundation
import Testing

@testable import RightOpCore

struct PathUtilitiesTests {
  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: true
    )
    return url
  }

  @Test
  func testUniqueFileURLAddsIncreasingSuffix() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let first = temporaryDirectory.appendingPathComponent("Untitled.md")
    let second = temporaryDirectory.appendingPathComponent("Untitled 2.md")
    try Data().write(to: first)
    try Data().write(to: second)

    #expect(
      FileNaming.uniqueFileURL(
        in: temporaryDirectory,
        preferredName: "Untitled.md"
      ).lastPathComponent == "Untitled 3.md"
    )
  }

  @Test
  func testShellQuoteHandlesWhitespaceAndApostrophes() {
    #expect(
      PathFormatting.shellQuote("/Users/ada/What's New/file.md")
        == "'/Users/ada/What'\\''s New/file.md'"
    )
  }

  @Test
  func testDirectoryReturnsParentForFile() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let file = temporaryDirectory.appendingPathComponent("file.txt")
    try Data().write(to: file)
    #expect(
      PathFormatting.directory(for: file).standardizedFileURL
        == temporaryDirectory.standardizedFileURL
    )
  }
}
