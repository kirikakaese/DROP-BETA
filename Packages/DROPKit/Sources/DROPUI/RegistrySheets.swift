import DROPCore
import DROPGitHub
import DROPRegistries
import DROPServices
import SwiftUI

/// How DROP publishes one registry: the tap or bucket file for Homebrew and Scoop, the workflow it
/// starts for GHCR and npm.
struct RegistrySetupSheet: View {
    let activity: ProjectActivityModel
    @State private var setup: RegistrySetup
    @State private var isProposing = false

    init(activity: ProjectActivityModel, setup: RegistrySetup) {
        self.activity = activity
        _setup = State(initialValue: setup)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Publish to \(setup.destination.title)"))
                .font(.title3.bold())
            Form {
                if setup.writesFile {
                    fileFields
                } else {
                    workflowFields
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { activity.editingRegistry = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { activity.saveSetup(setup) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!setup.isComplete)
            }
        }
        .padding()
        .frame(width: 580, height: 500)
    }

    @ViewBuilder private var fileFields: some View {
        let example = setup.destination == .homebrewTap ? "Casks/app.rb" : "bucket/app.json"
        Section {
            TextField("Repository", text: $setup.repository, prompt: Text(verbatim: "owner/homebrew-tap"))
            TextField("File", text: $setup.path, prompt: Text(verbatim: example))
            TextField("Asset", text: $setup.assetPattern, prompt: Text(verbatim: "App-{version}.zip"))
        } footer: {
            Text("In the asset, {version} stands for the version without the v, and * for anything.")
                .foregroundStyle(.secondary)
        }
        Section {
            Picker("Write Using", selection: $setup.writeMode) {
                ForEach(TapWriteMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            if setup.destination == .homebrewTap {
                TextField("App", text: $setup.appName, prompt: Text(verbatim: "App.app"))
                    .help("The app a new cask installs. DROP writes a cask when the file doesn't exist yet.")
            }
        } footer: {
            Text("DROP never changes a file another workflow writes. Betas and drafts are left out.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var workflowFields: some View {
        Section {
            Picker("Workflow", selection: Binding(
                get: { setup.workflowID },
                set: { id in
                    setup.workflowID = id
                    let summary = activity.dispatchableWorkflows.first { $0.workflow.id == id }
                    setup.workflowName = summary.map { ($0.workflow.path as NSString).lastPathComponent }
                }
            )) {
                Text("None").tag(Int64?.none)
                ForEach(activity.dispatchableWorkflows) { summary in
                    Text(verbatim: summary.workflow.name).tag(Int64?.some(summary.workflow.id))
                }
            }
        } footer: {
            Text("DROP starts it on the tag once the GitHub Release exists. DROP never holds a registry token.")
                .foregroundStyle(.secondary)
        }
        Section {
            if let url = activity.proposedPublishWorkflow?.htmlURL {
                Link("View Pull Request", destination: url)
            } else {
                Button("Add a Publish Workflow…") {
                    isProposing = true
                    Task {
                        await activity.proposePublishWorkflow(for: setup.destination)
                        isProposing = false
                    }
                }
                .disabled(isProposing)
            }
            if activity.needsWorkflowScope {
                Label(
                    "GitHub only lets DROP add workflow files with the workflow permission. Sign in again to grant it.",
                    systemImage: "lock"
                )
                Button("Sign In Again with Workflow Access") { activity.grantWorkflowScope() }
            }
        } footer: {
            Text("No workflow yet? DROP opens a pull request that adds one. Merge it, then choose it here.")
                .foregroundStyle(.secondary)
        }
    }
}

/// A dry run: the change DROP would make to a tap or bucket file for the latest release. Nothing has
/// been written.
struct RegistryPreviewSheet: View {
    let edit: RegistryEdit
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dry Run")
                .font(.title3.bold())
            Text("Nothing was written. DROP makes this change when you drop the next version.")
                .foregroundStyle(.secondary)
            Form {
                LabeledContent("Repository") { Text(verbatim: edit.repository.description) }
                LabeledContent("File") { Text(edit.isNew ? String(localized: "\(edit.path) (new)") : edit.path) }
                LabeledContent("Asset") { Text(verbatim: edit.assetName) }
                LabeledContent("SHA-256") {
                    Text(verbatim: edit.sha256)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                LabeledContent("Commit Message") { Text(verbatim: edit.message) }
            }
            .formStyle(.grouped)
            .frame(height: 230)
            ScrollView {
                Text(verbatim: edit.newText)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 640, height: 600)
    }
}
