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

    init() {
        #if DEBUG
        let services = ScreenshotScenario.requested == nil ? ServiceContainer.live() : .demo()
        #else
        let services = ServiceContainer.live()
        #endif
        self.services = services
        let account = AccountModel(services: services)
        _account = State(initialValue: account)
        _projects = State(initialValue: ProjectsModel(services: services, account: account))
    }

    var body: some Scene {
        WindowGroup(AboutPanel.shortName, id: "main") {
            RootView(model: projects)
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
            }
            SidebarCommands()
            ProjectCommands(model: projects)
        }

        Settings {
            SettingsView(account: account)
        }
    }
}
