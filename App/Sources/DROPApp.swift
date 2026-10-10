import DROPCore
import DROPServices
import DROPUI
import SwiftUI

@main
struct DROPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let services: ServiceContainer
    @State private var account: AccountModel
    @State private var projects: ProjectsModel
    @State private var updates = UpdateModel()
    @State private var appIcon: AppIconModel
    @State private var appLock: AppLockModel

    init() {
        #if DEBUG
        let services = ScreenshotScenario.requested.map { ServiceContainer.demo(account: $0.account) }
            ?? ServiceContainer.live()
        #else
        let services = ServiceContainer.live()
        #endif
        self.services = services
        let account = AccountModel(services: services)
        _account = State(initialValue: account)
        _projects = State(initialValue: ProjectsModel(services: services, account: account))
        #if DEBUG
        let appLock = ScreenshotScenario.requested.map {
            // Screenshots never ask for Touch ID; the lock screen stays up for its own scenario.
            AppLockModel(authenticator: FakeAuthenticator(succeeds: false), startsLocked: $0 == .locked)
        } ?? Self.liveAppLock()
        #else
        let appLock = Self.liveAppLock()
        #endif
        _appLock = State(initialValue: appLock)
        let appIcon = AppIconModel()
        _appIcon = State(initialValue: appIcon)
        // macOS shows the bundle's icon until launching has finished; the chosen one replaces it then.
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { appIcon.apply() }
        }
    }

    @MainActor
    private static func liveAppLock() -> AppLockModel {
        let appLock = AppLockModel(
            authenticator: DeviceAuthenticator(),
            isAvailable: DeviceAuthenticator.isAvailable()
        )
        appLock.startMonitoring()
        return appLock
    }

    var body: some Scene {
        WindowGroup(AboutPanel.shortName, id: "main") {
            RootView(model: projects, appLock: appLock)
                .environment(\.services, services)
                .frame(minWidth: 820, minHeight: 520)
                #if DEBUG
                .task { await ScreenshotScenario.requested?.prepare(projects) }
                #endif
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(AboutPanel.shortName)") {
                    AboutPanel.show()
                }
                Button("Check for Updates…") { updates.checkNow() }
                    .disabled(!updates.isAvailable)
            }
            CommandGroup(after: .appSettings) {
                Button("Lock \(AboutPanel.shortName)") { appLock.lock() }
                    .keyboardShortcut("l", modifiers: [.command, .control])
                    .disabled(!appLock.isAvailable || !appLock.settings.isEnabled)
            }
            SidebarCommands()
            ProjectCommands(model: projects)
        }

        Settings {
            SettingsView(account: account, appLock: appLock, appIcon: appIcon) {
                UpdateSettingsView(model: updates)
            }
        }
    }
}
