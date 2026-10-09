import DROPCore
import DROPGitHub
import SwiftUI

/// The main window: projects in the sidebar, the selected project on the right.
public struct RootView: View {
    @Bindable private var model: ProjectsModel
    @Bindable private var account: AccountModel

    public init(model: ProjectsModel) {
        self.model = model
        account = model.account
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            if let project = model.selectedProject {
                ProjectDetailView(model: model, project: project)
            } else {
                ContentUnavailableView(
                    "Select a Project",
                    systemImage: "shippingbox",
                    description: Text("Choose a project in the sidebar to see its drops.")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.isAddingProject = true
                } label: {
                    Label("Add Project", systemImage: "plus")
                }
                .help("Add a GitHub repository")
                .disabled(!model.canAddProject)
                Button {
                    model.startDrop()
                } label: {
                    Label(DropWording.actionTitle(version: nil), systemImage: "arrow.down.to.line")
                }
                .help("Plan the next drop of this project")
                .disabled(!model.canDrop)
            }
        }
        .task {
            model.load()
            await account.load()
            await model.refreshFromGitHub()
        }
        .onChange(of: account.isSignedIn) { _, isSignedIn in
            if isSignedIn { Task { await model.refreshFromGitHub() } }
        }
        .sheet(isPresented: $model.isAddingProject) {
            AddProjectSheet(model: model)
        }
        .sheet(isPresented: dropSheetBinding) {
            if let drop = model.currentDrop {
                DropSheet(model: drop) { model.currentDrop = nil }
            }
        }
        .sheet(isPresented: signInSheetBinding) {
            if let authorization = account.pendingAuthorization {
                SignInSheet(account: account, authorization: authorization)
            }
        }
        .errorAlert($model.error)
        .errorAlert($account.error)
    }

    private var dropSheetBinding: Binding<Bool> {
        Binding(
            get: { model.currentDrop != nil },
            set: { if !$0, model.currentDrop?.isRunning != true { model.currentDrop = nil } }
        )
    }

    private var signInSheetBinding: Binding<Bool> {
        Binding(
            get: { account.pendingAuthorization != nil },
            set: { if !$0 { account.cancelSignIn() } }
        )
    }
}

struct SidebarView: View {
    @Bindable var model: ProjectsModel

    var body: some View {
        List(selection: $model.selection) {
            Section("Projects") {
                ForEach(model.projects) { project in
                    Label {
                        Text(verbatim: project.slug.description)
                    } icon: {
                        Image(systemName: icon(for: project))
                    }
                    .tag(project.id)
                    .contextMenu {
                        Button("Remove from DROP") { model.removeProject(id: project.id) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            if model.account.phase == .sessionExpired {
                SessionEndedBanner(account: model.account)
            }
        }
        .overlay {
            if model.projects.isEmpty {
                EmptyProjectsView(model: model)
            }
        }
    }

    private func icon(for project: Project) -> String {
        model.missing.contains(project.id) ? "exclamationmark.triangle" : "shippingbox"
    }
}

private struct EmptyProjectsView: View {
    let model: ProjectsModel

    var body: some View {
        if model.account.isSignedIn {
            ContentUnavailableView {
                Label("No Projects", systemImage: "tray")
            } description: {
                Text("Add a repository to start dropping.")
            } actions: {
                Button("Add Project…") { model.isAddingProject = true }
            }
        } else {
            ContentUnavailableView {
                Label("No Projects", systemImage: "tray")
            } description: {
                Text("Sign in with GitHub to add your repositories.")
            } actions: {
                Button("Sign In with GitHub…") { model.account.signIn() }
                    .disabled(!model.account.canSignIn)
            }
        }
    }
}

private struct SessionEndedBanner: View {
    let account: AccountModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Your GitHub session has ended.", systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.callout)
            Button("Sign In Again") { account.signIn() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
    }
}

struct RepositoryDetails: View {
    let repository: GitHubRepository

    var body: some View {
        LabeledContent("Visibility") {
            if repository.isPrivate { Text("Private") } else { Text("Public") }
        }
        LabeledContent("Default Branch") {
            Text(verbatim: repository.defaultBranch).monospaced()
        }
        if let summary = repository.summary, !summary.isEmpty {
            LabeledContent("Description") {
                Text(verbatim: summary)
            }
        }
        if repository.isArchived {
            LabeledContent("Status") {
                Text("Archived")
            }
        }
    }
}

extension View {
    /// Shows `error` as an alert with its explanation and fix.
    func errorAlert(_ error: Binding<DROPError?>) -> some View {
        alert(
            error.wrappedValue?.whatHappened ?? "",
            isPresented: Binding(get: { error.wrappedValue != nil }, set: { if !$0 { error.wrappedValue = nil } }),
            presenting: error.wrappedValue
        ) { _ in
            Button("OK") { error.wrappedValue = nil }
        } message: { presented in
            if let howToFix = presented.howToFix {
                Text(howToFix)
            }
        }
    }
}
