import Foundation
import Testing

@testable import DROPCore

@Suite("TagName")
struct TagNameTests {
    @Test(arguments: ["v1.2.3", "1.0.0", "v2.0.0-beta.1", "app/v1.0", "release-2026.10", "v1.2.3+build.7"])
    func acceptsUsualTags(_ name: String) {
        #expect(TagName.isValid(name))
    }

    @Test(arguments: [
        "", "v1 2", "-v1", "v1.", "v1..2", "v1/", "/v1", "v1.lock", "v1~1", "v1^", "v1:2", "v1?", "v1*", "v1[",
        "v1\\2", "@", "v1@{0}", "a//b", "a/.b", "v1\t",
    ])
    func refusesWhatGitRefuses(_ name: String) {
        #expect(!TagName.isValid(name))
    }
}

@Suite("Checksums")
struct ChecksumsTests {
    @Test func hashesDataAndFilesTheSame() throws {
        let data = Data("abc".utf8)
        #expect(Checksums.sha256(of: data) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).txt")
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try Checksums.sha256(of: file) == Checksums.sha256(of: data))
    }

    @Test func hashesLargeFilesInChunks() throws {
        let data = Data(repeating: 7, count: 3 * (1 << 20) + 5)
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).bin")
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try Checksums.sha256(of: file) == Checksums.sha256(of: data))
    }

    @Test func writesTheShasumFormatSortedByName() {
        let sums = Checksums.sumsFile(["b.zip": "22", "a.dmg": "11"])
        #expect(sums == "11  a.dmg\n22  b.zip\n")
    }
}

@Suite("DropWording")
struct DropWordingTests {
    @Test func namesTheVersionWhenItIsKnown() {
        #expect(DropWording.actionTitle(version: nil) == "Drop")
        #expect(DropWording.actionTitle(version: "") == "Drop")
        #expect(DropWording.actionTitle(version: "1.2.3") == "Drop v1.2.3")
        #expect(DropWording.actionTitle(version: "v1.2.3-beta.1") == "Drop v1.2.3-beta.1")
        #expect(DropWording.menuTitle == "Drop…")
        #expect(DropWording.progressTitle(version: "v1.2.3") == "Dropping v1.2.3…")
        #expect(DropWording.doneTitle(version: "v1.2.3") == "Dropped v1.2.3")
        #expect(DropWording.failedTitle == "Drop failed")
        #expect(DropWording.betaTitle == "Drop a Beta")
        #expect(DropWording.readyTitle == "Ready to Drop")
        #expect(DropWording.historyTitle == "Drops")
    }
}
