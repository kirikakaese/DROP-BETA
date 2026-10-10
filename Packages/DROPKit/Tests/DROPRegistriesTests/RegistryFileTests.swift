import DROPCore
import DROPGitHub
import DROPTestFixtures
import Foundation
import Testing

@testable import DROPRegistries

private let oldSHA = String(repeating: "a", count: 64)
private let newSHA = String(repeating: "b", count: 64)
private let project = Fixtures.slug("octocat/SMP")
private let newURL = "https://github.com/octocat/SMP/releases/download/v1.1.0/SMP-1.1.0.dmg"

@Suite("Asset patterns")
struct AssetPatternTests {
    @Test func versionDropsTheLeadingV() {
        #expect(AssetPattern.version(fromTag: "v1.2.3") == "1.2.3")
        #expect(AssetPattern.version(fromTag: "v1.2.3-beta.1") == "1.2.3-beta.1")
        #expect(AssetPattern.version(fromTag: "1.2.3") == "1.2.3")
        #expect(AssetPattern.version(fromTag: "very-1") == "very-1")
    }

    @Test func matchesVersionsAndWildcards() {
        #expect(AssetPattern.matches("SMP-1.2.3.dmg", pattern: "SMP-{version}.dmg", version: "1.2.3"))
        #expect(!AssetPattern.matches("SMP-1.2.4.dmg", pattern: "SMP-{version}.dmg", version: "1.2.3"))
        #expect(AssetPattern.matches("tool-1.0-windows-x64.zip", pattern: "*-windows-*.zip", version: "1.0"))
        #expect(AssetPattern.matches("a.zip", pattern: "?.zip", version: ""))
        #expect(!AssetPattern.matches("ab.zip", pattern: "?.zip", version: ""))
        #expect(AssetPattern.matches("", pattern: "*", version: ""))
    }

    @Test func selectsExactlyOneAsset() throws {
        let names = ["SMP-1.0.0.dmg", "SMP-1.0.0.zip"]
        #expect(try AssetPattern.select(from: names, pattern: "*.zip", version: "1.0.0") == "SMP-1.0.0.zip")
        #expect(throws: DROPError.self) { try AssetPattern.select(from: names, pattern: "*.pkg", version: "1.0.0") }
        #expect(throws: DROPError.self) { try AssetPattern.select(from: names, pattern: "SMP-*", version: "1.0.0") }
    }
}

@Suite("Homebrew files")
struct HomebrewFileTests {
    static let cask = """
        cask "smp" do
          version "1.0.0"
          sha256 "\(oldSHA)"

          url "https://github.com/octocat/SMP/releases/download/v#{version}/SMP-#{version}.dmg",
              verified: "github.com/octocat/SMP/"
          name "SMP"
          homepage "https://github.com/octocat/SMP"

          livecheck do
            url :url
            strategy :github_latest
          end

          app "SMP.app"
        end

        """

    static let formula = """
        class Smp < Formula
          desc "SSH keys and hosts"
          homepage "https://github.com/octocat/SMP"
          url "https://github.com/octocat/SMP/releases/download/v1.0.0/smp-1.0.0.tar.gz"
          sha256 "\(oldSHA)"

          resource "helper" do
            url "https://example.com/helper-2.0.tar.gz"
            sha256 "cccc"
          end

          bottle do
            sha256 cellar: :any, arm64_sonoma: "dddd"
          end
        end

        """

    @Test func recognizesCasksAndFormulas() {
        #expect(HomebrewFile.kind(of: Self.cask) == .cask)
        #expect(HomebrewFile.kind(of: Self.formula) == .formula)
        #expect(HomebrewFile.kind(of: "puts 1") == nil)
    }

    @Test func caskKeepsItsInterpolatedURL() throws {
        let bumped = try HomebrewFile.bump(Self.cask, version: "1.1.0", sha256: newSHA, url: newURL)
        let expected = Self.cask
            .replacingOccurrences(of: "version \"1.0.0\"", with: "version \"1.1.0\"")
            .replacingOccurrences(of: oldSHA, with: newSHA)
        #expect(bumped == expected)
    }

    @Test func caskWithAPlainURLGetsAnInterpolatedOne() throws {
        let cask = Self.cask.replacingOccurrences(
            of: "v#{version}/SMP-#{version}.dmg", with: "v1.0.0/SMP-1.0.0.dmg"
        )
        let bumped = try HomebrewFile.bump(cask, version: "1.1.0", sha256: newSHA, url: newURL)
        #expect(bumped.contains("v#{version}/SMP-#{version}.dmg\","))
        #expect(bumped.contains("      verified: \"github.com/octocat/SMP/\""))
    }

    @Test func formulaChangesOnlyItsOwnURLAndChecksum() throws {
        let url = "https://github.com/octocat/SMP/releases/download/v1.1.0/smp-1.1.0.tar.gz"
        let bumped = try HomebrewFile.bump(Self.formula, version: "1.1.0", sha256: newSHA, url: url)
        let expected = Self.formula
            .replacingOccurrences(of: "v1.0.0/smp-1.0.0.tar.gz", with: "v1.1.0/smp-1.1.0.tar.gz")
            .replacingOccurrences(of: oldSHA, with: newSHA)
        #expect(bumped == expected)
    }

    @Test func refusesOneDownloadPerArchitecture() {
        let cask = Self.cask.replacingOccurrences(
            of: "sha256 \"\(oldSHA)\"", with: "sha256 arm:   \"\(oldSHA)\",\n         intel: \"\(oldSHA)\""
        )
        #expect(throws: DROPError.self) {
            try HomebrewFile.bump(cask, version: "1.1.0", sha256: newSHA, url: newURL)
        }
        let unchecked = Self.cask.replacingOccurrences(of: "sha256 \"\(oldSHA)\"", with: "sha256 :no_check")
        #expect(throws: DROPError.self) {
            try HomebrewFile.bump(unchecked, version: "1.1.0", sha256: newSHA, url: newURL)
        }
    }

    @Test func writesANewCask() {
        let setup = RegistrySetup(destination: .homebrewTap, repository: "octocat/homebrew-tap", path: "Casks/smp.rb")
        let cask = HomebrewFile.newCask(
            setup, project: project, version: "1.1.0", sha256: newSHA, url: newURL,
            description: "SSH keys and hosts."
        )
        let expected = """
            cask "smp" do
              version "1.1.0"
              sha256 "\(newSHA)"

              url "https://github.com/octocat/SMP/releases/download/v#{version}/SMP-#{version}.dmg"
              name "SMP"
              desc "SSH keys and hosts"
              homepage "https://github.com/octocat/SMP"

              app "SMP.app"
            end

            """
        #expect(cask == expected)
    }
}

@Suite("Scoop manifests")
struct ScoopManifestTests {
    static let manifest = """
        {
            "version": "1.0.0",
            "description": "SSH keys and hosts",
            "license": "GPL-3.0-only",
            "url": "https://github.com/octocat/SMP/releases/download/v1.0.0/SMP-1.0.0.zip",
            "hash": "\(oldSHA)",
            "bin": "smp.exe",
            "checkver": "github",
            "autoupdate": {
                "url": "https://github.com/octocat/SMP/releases/download/v$version/SMP-$version.zip"
            }
        }

        """

    @Test func updatesVersionURLAndHashInPlace() throws {
        let url = "https://github.com/octocat/SMP/releases/download/v1.1.0/SMP-1.1.0.zip"
        let bumped = try ScoopManifest.bump(Self.manifest, version: "1.1.0", url: url, hash: newSHA)
        let expected = Self.manifest
            .replacingOccurrences(of: "\"version\": \"1.0.0\"", with: "\"version\": \"1.1.0\"")
            .replacingOccurrences(of: "v1.0.0/SMP-1.0.0.zip", with: "v1.1.0/SMP-1.1.0.zip")
            .replacingOccurrences(of: oldSHA, with: newSHA)
        #expect(bumped == expected)
    }

    @Test func updatesTheOnlyArchitecture() throws {
        let manifest = """
            {
                "version": "1.0.0",
                "architecture": {
                    "64bit": {
                        "url": "https://example.com/SMP-1.0.0.zip",
                        "hash": "\(oldSHA)"
                    }
                }
            }
            """
        let url = "https://example.com/new.zip"
        let bumped = try ScoopManifest.bump(manifest, version: "1.1.0", url: url, hash: newSHA)
        let parsed = try OrderedJSON(parsing: bumped)
        let entry = parsed["architecture"]?["64bit"]
        #expect(entry?["url"]?.stringValue == "https://example.com/new.zip")
        #expect(entry?["hash"]?.stringValue == newSHA)
        #expect(parsed["version"]?.stringValue == "1.1.0")
    }

    @Test func refusesSeveralArchitecturesAndBrokenJSON() {
        let manifest = """
            {"version": "1", "architecture": {"64bit": {"url": "a", "hash": "b"}, "arm64": {"url": "c", "hash": "d"}}}
            """
        #expect(throws: DROPError.self) {
            try ScoopManifest.bump(manifest, version: "2", url: "u", hash: "h")
        }
        #expect(throws: DROPError.self) {
            try ScoopManifest.bump("{\"version\": ", version: "2", url: "u", hash: "h")
        }
    }
}

@Suite("Ordered JSON")
struct OrderedJSONTests {
    @Test func keepsOrderSpellingAndEscapes() throws {
        let text = #"{"z":[1,2.50,"x\"y\u00e9\n\ud83d\ude00"],"b":{},"c":[],"d":null,"e":true}"#
        let json = try OrderedJSON(parsing: text)
        let expected = #"""
            {
                "z": [
                    1,
                    2.50,
                    "x\"yé\n😀"
                ],
                "b": {},
                "c": [],
                "d": null,
                "e": true
            }

            """#
        #expect(json.formatted() == expected)
    }

    @Test func rejectsTrailingText() {
        #expect(throws: OrderedJSON.ParseError.self) { try OrderedJSON(parsing: "{} x") }
        #expect(throws: OrderedJSON.ParseError.self) { try OrderedJSON(parsing: "[1,]") }
    }

    @Test func subscriptSetsAndRemovesKeys() throws {
        var json = try OrderedJSON(parsing: #"{"a": 1, "b": 2}"#)
        json["a"] = .string("x")
        json["c"] = .bool(false)
        json["b"] = nil
        #expect(json == .object([OrderedJSON.Member("a", .string("x")), OrderedJSON.Member("c", .bool(false))]))
    }
}

@Suite("Registry edits")
struct RegistryEditTests {
    let tap = RegistrySetup(
        destination: .homebrewTap, repository: "octocat/homebrew-tap", path: "Casks/smp.rb", assetPattern: "*.dmg"
    )
    let asset = SelectedAsset(name: "SMP-1.1.0.dmg", sha256: newSHA)

    @Test func findsTheAutomationThatOwnsAFile() {
        let files = [
            ".github/workflows/ci.yml": "brew audit",
            ".github/workflows/release.yml": "git -C tap add Casks/smp.rb",
        ]
        #expect(TapOwnership.owner(of: "Casks/smp.rb", in: files) == ".github/workflows/release.yml")
        #expect(TapOwnership.owner(of: "Casks/drop.rb", in: files) == nil)
        #expect(TapOwnership.owner(of: "bucket/smp.json", in: ["w.yml": "cp out/smp.json bucket/"]) == "w.yml")
    }

    @Test func updatesAnExistingCask() throws {
        let existing = GitHubFile(sha: "blob1", text: HomebrewFileTests.cask)
        let edit = try RegistryEditor.edit(tap, project: project, tag: "v1.1.0", asset: asset, existing: existing)
        #expect(edit.message == "smp 1.1.0")
        #expect(edit.branch == "drop/smp-1.1.0")
        #expect(edit.blobSHA == "blob1")
        #expect(!edit.isNew)
        #expect(edit.newText.contains("version \"1.1.0\""))
        #expect(edit.isApplied(in: edit.newText))
        #expect(!edit.isApplied(in: HomebrewFileTests.cask))
    }

    @Test func writesAMissingCaskButNotAMissingFormulaOrManifest() throws {
        let edit = try RegistryEditor.edit(tap, project: project, tag: "v1.1.0", asset: asset, existing: nil)
        #expect(edit.isNew)
        #expect(edit.message == "smp 1.1.0 (new cask)")

        var formula = tap
        formula.path = "Formula/smp.rb"
        #expect(throws: DROPError.self) {
            try RegistryEditor.edit(formula, project: project, tag: "v1.1.0", asset: asset, existing: nil)
        }
        let bucket = RegistrySetup(
            destination: .scoopBucket, repository: "octocat/scoop-bucket", path: "bucket/smp.json"
        )
        #expect(throws: DROPError.self) {
            try RegistryEditor.edit(bucket, project: project, tag: "v1.1.0", asset: asset, existing: nil)
        }
    }

    @Test func scoopMessagesFollowTheBucketConvention() throws {
        let bucket = RegistrySetup(
            destination: .scoopBucket, repository: "octocat/scoop-bucket", path: "bucket/smp.json"
        )
        let existing = GitHubFile(sha: "blob2", text: ScoopManifestTests.manifest)
        let edit = try RegistryEditor.edit(bucket, project: project, tag: "v1.1.0", asset: asset, existing: existing)
        #expect(edit.message == "smp: Update to version 1.1.0")
        #expect(edit.newText.contains("releases/download/v1.1.0/SMP-1.1.0.dmg"))
    }

    @Test func encodesDownloadURLs() {
        let url = RegistryEditor.downloadURL(project: project, tag: "v1.0", asset: "My App 1.0.zip")
        #expect(url == "https://github.com/octocat/SMP/releases/download/v1.0/My%20App%201.0.zip")
    }
}
