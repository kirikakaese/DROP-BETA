import AppKit
import Testing

@testable import DROPUI

@MainActor
@Suite("App icon")
struct AppIconModelTests {
    /// Records what the model would show in the Dock.
    private final class Dock {
        var icons: [NSImage?] = []
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "drop-icon-\(UUID().uuidString)") ?? .standard
    }

    @Test func startsWithTheStandardIconAndKeepsTheBundleIconInTheDock() {
        let dock = Dock()
        let model = AppIconModel(defaults: defaults()) { dock.icons.append($0) }
        #expect(model.style == .teal)
        #expect(model.style.isStandard)
        model.apply()
        #expect(dock.icons.count == 1)
        #expect(dock.icons.first == .some(nil))
    }

    @Test func showsAndRemembersAnotherIcon() throws {
        let store = defaults()
        let dock = Dock()
        let model = AppIconModel(defaults: store) { dock.icons.append($0) }
        model.style = .transgender

        let shown = try #require(dock.icons.last.flatMap { $0 })
        let pixels = try #require(shown.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(pixels.width == 1024)
        #expect(pixels.height == 1024)

        let reopened = AppIconModel(defaults: store) { _ in }
        #expect(reopened.style == .transgender)
    }

    @Test func restoringTheDefaultHandsTheDockBackToTheBundleIcon() {
        let dock = Dock()
        let model = AppIconModel(defaults: defaults()) { dock.icons.append($0) }
        model.style = .rainbow
        model.restoreDefault()
        #expect(model.style.isStandard)
        #expect(dock.icons.last == .some(nil))
    }

    @Test func settingTheSameIconAgainChangesNothing() {
        let dock = Dock()
        let model = AppIconModel(defaults: defaults()) { dock.icons.append($0) }
        model.style = .teal
        #expect(dock.icons.isEmpty)
    }

    @Test func ignoresUnknownStoredValues() {
        let store = defaults()
        store.set("plaid", forKey: "appIcon.style")
        let model = AppIconModel(defaults: store) { _ in }
        #expect(model.style == .teal)
    }

    @Test func drawsEveryStyle() throws {
        #expect(AppIconStyle.colors.count + AppIconStyle.pride.count == AppIconStyle.allCases.count)
        for style in AppIconStyle.allCases {
            let image = try #require(AppIconModel.image(for: style, size: 32))
            let pixels = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            #expect(pixels.width == 64, "\(style)")
        }
    }

    @Test func matchesSMPsPalette() {
        let colors = AppIconStyle.colors.map(\.rawValue)
        let pride = AppIconStyle.pride.map(\.rawValue)
        #expect(colors == ["teal", "graphite", "blue", "silver"])
        #expect(pride == [
            "rainbow", "progress", "transgender", "nonbinary", "bisexual", "pansexual", "lesbian", "asexual",
            "aromantic",
        ])
        for style in AppIconStyle.pride {
            #expect(AppIconPalette.gradient(style) == nil, "\(style)")
            #expect(!AppIconPalette.stripes(style).isEmpty, "\(style)")
        }
        for style in AppIconStyle.colors {
            #expect(AppIconPalette.gradient(style) != nil, "\(style)")
        }
    }

    @Test func theDropletHasItsArrowCutOut() {
        let glyph = AppIconGlyph.path
        #expect(glyph.contains(CGPoint(x: 512, y: 300)))
        #expect(glyph.contains(CGPoint(x: 512, y: 780)))
        #expect(!glyph.contains(CGPoint(x: 512, y: 500)))
        #expect(!glyph.contains(CGPoint(x: 512, y: 650)))
        #expect(!glyph.contains(CGPoint(x: 512, y: 150)))
    }
}
