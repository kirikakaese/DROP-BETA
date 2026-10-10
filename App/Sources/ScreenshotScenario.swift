#if DEBUG
import AppKit
import DROPCore
import DROPServices
import DROPUI

/// Puts a debug build into a fixed state with sample data, for the screenshots CI takes of every
/// branch (scripts/screenshots.sh). Start the app with `-DROPScreenshot <scenario>`.
enum ScreenshotScenario: String, CaseIterable {
    case signedOut = "signed-out"
    case signIn = "sign-in"
    case sessionEnded = "session-ended"
    case projects
    case addProject = "add-project"
    case dropForm = "drop-form"
    case readyToDrop = "ready-to-drop"
    case dropped
    case run
    case runWorkflow = "run-workflow"
    case releaseWorkflow = "release-workflow"
    case registrySetup = "registry-setup"
    case registryDryRun = "registry-dry-run"
    case settingsGeneral = "settings-general"
    case settingsAccount = "settings-account"

    static var requested: ScreenshotScenario? {
        UserDefaults.standard.string(forKey: "DROPScreenshot").flatMap(Self.init(rawValue:))
    }

    /// The account the demo services start with.
    var account: DemoAccount {
        switch self {
        case .signedOut, .signIn: .signedOut
        case .sessionEnded: .sessionEnded
        default: .signedIn
        }
    }

    @MainActor
    func prepare(_ projects: ProjectsModel) async {
        NSApp.activate()
        Self.enlargeMainWindow()
        projects.load()
        await projects.account.load()
        await projects.refreshFromGitHub()
        if account == .signedIn { projects.selection = projects.projects.first?.id }
        switch self {
        case .signedOut, .sessionEnded, .projects:
            break
        case .signIn:
            projects.account.signIn()
        case .addProject:
            projects.isAddingProject = true
        case .settingsGeneral, .settingsAccount:
            UserDefaults.standard.set(self == .settingsGeneral ? "general" : "account", forKey: "settingsTab")
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case .run, .runWorkflow, .releaseWorkflow:
            await prepareActions(projects)
        case .dropForm, .readyToDrop, .dropped:
            await prepareDrop(projects)
        case .registrySetup, .registryDryRun:
            await prepareRegistry(projects)
        }
    }

    /// The Scoop bucket DROP manages in the demo: its setup, or a dry run for the latest release.
    @MainActor
    private func prepareRegistry(_ projects: ProjectsModel) async {
        guard let project = projects.selectedProject else { return }
        let activity = projects.activityModel(for: project)
        await activity.load(branch: "main")
        if self == .registrySetup {
            activity.editSetup(for: .scoopBucket)
        } else {
            await activity.preview(.scoopBucket)
        }
    }

    @MainActor
    private func prepareActions(_ projects: ProjectsModel) async {
        guard let project = projects.selectedProject else { return }
        let actions = projects.actionsModel(for: project)
        await actions.load()
        switch self {
        case .run: actions.openRun = actions.runs.first
        case .runWorkflow: actions.dispatching = actions.workflows.first { $0.triggers.dispatch }?.workflow
        default: actions.isProposingWorkflow = true
        }
    }

    @MainActor
    private func prepareDrop(_ projects: ProjectsModel) async {
        projects.startDrop()
        guard let drop = projects.currentDrop else { return }
        await drop.loadSuggestion()
        drop.title = "SMP \(drop.tagName.dropFirst())"
        drop.updatesChangelog = true
        drop.addAssets(Self.sampleAssets())
        if self != .dropForm { await drop.review() }
        if self == .dropped { await drop.drop() }
    }

    /// Big enough that the project view shows most of its sections.
    @MainActor
    private static func enlargeMainWindow() {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
            let screen = window.screen ?? NSScreen.main
        else { return }
        let visible = screen.visibleFrame
        let size = NSSize(width: min(1240, visible.width - 40), height: min(1000, visible.height - 20))
        let origin = NSPoint(x: visible.minX + 20, y: visible.maxY - size.height)
        window.setFrame(NSRect(origin: origin, size: size), display: true)
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
