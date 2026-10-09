import DROPCore
import DROPServices
import DROPUI
import SwiftUI

@main
struct DROPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let services: ServiceContainer
    @State private var projects: ProjectsModel

    init() {
        let services = ServiceContainer.live()
        self.services = services
        _projects = State(initialValue: ProjectsModel(services: services))
    }

    var body: some Scene {
        WindowGroup(AboutPanel.shortName, id: "main") {
            RootView(model: projects)
                .environment(\.services, services)
                .frame(minWidth: 820, minHeight: 520)
        }
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
            SettingsView()
        }
    }
}
