#if DEBUG
import AppKit
import DROPCore
import DROPServices
import DROPUI

/// Puts a debug build into a fixed state with sample data, for the screenshots CI takes of every
/// branch (scripts/screenshots.sh). Start the app with `-DROPScreenshot <scenario>`.
enum ScreenshotScenario: String, CaseIterable {
    case projects
    case dropForm = "drop-form"
    case readyToDrop = "ready-to-drop"
    case dropped
    case account

    static var requested: ScreenshotScenario? {
        UserDefaults.standard.string(forKey: "DROPScreenshot").flatMap(Self.init(rawValue:))
    }

    @MainActor
    func prepare(_ projects: ProjectsModel) async {
        NSApp.activate()
        projects.load()
        await projects.account.load()
        await projects.refreshFromGitHub()
        projects.selection = projects.projects.first?.id
        switch self {
        case .projects:
            break
        case .account:
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case .dropForm, .readyToDrop, .dropped:
            projects.startDrop()
            guard let drop = projects.currentDrop else { return }
            drop.tagName = "v1.0.0"
            drop.title = "SMP 1.0.0"
            drop.notes = """
                ## Features
                - **Key library:** tags, groups and favorites
                - Rotate keys from the menu bar

                ## Fixes
                - Agent no longer asks twice after sleep
                """
            drop.addAssets(Self.sampleAssets())
            if self != .dropForm { await drop.review() }
            if self == .dropped { await drop.drop() }
        }
    }

    /// Small files named like real release assets.
    private static func sampleAssets() -> [URL] {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DROPScreenshots")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ["SMP-1.0.0.dmg", "SMP-1.0.0.zip"].compactMap { name in
            let url = directory.appending(path: name)
            return (try? Data(name.utf8).write(to: url)) == nil ? nil : url
        }
    }
}
#endif
