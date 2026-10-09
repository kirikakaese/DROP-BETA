import DROPCore
import SwiftUI

/// The main window: projects in the sidebar, the selected project on the right.
public struct RootView: View {
    @Bindable private var model: ProjectsModel

    public init(model: ProjectsModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            if let project = model.selectedProject {
                ProjectDetailView(project: project)
            } else {
                ContentUnavailableView(
                    "Select a Project",
                    systemImage: "shippingbox",
                    description: Text("Choose a project in the sidebar to see its drops.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {} label: {
                    Label(DropWording.actionTitle(version: nil), systemImage: "arrow.down.to.line")
                }
                .help("Plan the next drop of this project")
                .disabled(!model.canDrop)
            }
        }
        .task { model.load() }
        .alert(
            model.error?.whatHappened ?? "",
            isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } }),
            presenting: model.error
        ) { _ in
            Button("OK") { model.error = nil }
        } message: { error in
            if let howToFix = error.howToFix {
                Text(howToFix)
            }
        }
    }
}

struct SidebarView: View {
    @Bindable var model: ProjectsModel

    var body: some View {
        List(selection: $model.selection) {
            Section("Projects") {
                ForEach(model.projects) { project in
                    Label(project.slug.description, systemImage: "shippingbox")
                        .tag(project.id)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.projects.isEmpty {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "tray",
                    description: Text("Sign in with GitHub to add your repositories.")
                )
            }
        }
    }
}

struct ProjectDetailView: View {
    let project: Project

    var body: some View {
        Form {
            Section {
                LabeledContent("Repository") {
                    Link(project.slug.description, destination: project.slug.webURL)
                }
                LabeledContent("Added") {
                    Text(project.addedAt, format: .dateTime.day().month().year())
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(project.slug.name)
    }
}
