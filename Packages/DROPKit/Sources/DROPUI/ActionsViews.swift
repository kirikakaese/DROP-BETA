import DROPCore
import DROPGitHub
import DROPServices
import SwiftUI

/// The Workflows and Recent Runs sections of a project. Their sheets come from `ActionsSheets`.
struct ActionsSections: View {
    let actions: ProjectActionsModel

    var body: some View {
        Section("Workflows") {
            if actions.isLoaded && actions.workflows.isEmpty {
                Text("This repository has no workflows yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(actions.workflows) { summary in
                WorkflowRow(summary: summary) { actions.dispatching = summary.workflow }
            }
            if actions.isLoaded && !actions.hasReleaseWorkflow {
                Button("Add a Release Workflow…") { actions.isProposingWorkflow = true }
                    .help("Opens a pull request with a workflow that builds every tag for six platforms.")
            }
        }
        Section("Recent Runs") {
            if actions.isLoaded && actions.runs.isEmpty {
                Text("No runs yet.").foregroundStyle(.secondary)
            }
            ForEach(actions.runs.prefix(10)) { run in
                Button { actions.openRun = run } label: {
                    RunRow(run: run, workflowName: actions.workflowName(of: run))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The sheets and alerts of `ActionsSections`, attached where they stay put (the whole form).
struct ActionsSheets: ViewModifier {
    @Bindable var actions: ProjectActionsModel

    func body(content: Content) -> some View {
        content
            .sheet(item: $actions.openRun) { run in
                WorkflowRunSheet(model: actions.runModel(for: run))
            }
            .sheet(item: $actions.dispatching) { workflow in
                DispatchSheet(actions: actions, workflow: workflow)
            }
            .sheet(isPresented: $actions.isProposingWorkflow) {
                ReleaseWorkflowSheet(actions: actions)
            }
            .errorAlert($actions.error)
    }
}

private struct WorkflowRow: View {
    let summary: WorkflowSummary
    let onRun: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: summary.workflow.name)
                Text(verbatim: summary.workflow.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if summary.triggers.tagPush {
                Text(tagLabel).font(.caption).foregroundStyle(.secondary)
            }
            if summary.triggers.dispatch {
                Button("Run…", action: onRun)
            }
        }
    }

    private var tagLabel: String {
        let patterns = summary.triggers.tagPatterns
        return patterns.isEmpty
            ? String(localized: "Runs on every tag")
            : String(localized: "Runs on tags \(patterns.joined(separator: ", "))")
    }
}

private struct RunRow: View {
    let run: GitHubWorkflowRun
    let workflowName: String

    var body: some View {
        HStack {
            RunStatusIcon(status: run.status, conclusion: run.conclusion)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: run.title ?? workflowName)
                    .lineLimit(1)
                Text(verbatim: "\(workflowName) #\(run.runNumber) · \(run.headBranch ?? run.event)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let date = run.createdAt {
                Text(date, format: .relative(presentation: .named))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Queued, running, succeeded, failed or cancelled.
struct RunStatusIcon: View {
    let status: String
    let conclusion: String?

    var body: some View {
        switch (status, conclusion) {
        case ("completed", "success"?):
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case ("completed", "failure"?), ("completed", "timed_out"?):
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case ("completed", _):
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case ("in_progress", _):
            ProgressView().controlSize(.small)
        default:
            Image(systemName: "clock").foregroundStyle(.secondary)
        }
    }
}

/// A run's jobs and steps, the end of their logs and the artifacts. Refreshes while running.
struct WorkflowRunSheet: View {
    let model: WorkflowRunModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                RunStatusIcon(status: model.run.status, conclusion: model.run.conclusion)
                Text(verbatim: model.run.title ?? model.run.name ?? "")
                    .font(.title3.bold())
                    .lineLimit(1)
                Spacer()
                Text(verbatim: "#\(model.run.runNumber)").foregroundStyle(.secondary)
            }
            .padding()
            Divider()
            Form {
                ForEach(model.jobs) { job in
                    JobSection(model: model, job: job)
                }
                if !model.artifacts.isEmpty {
                    ArtifactsSection(model: model)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if let url = model.run.htmlURL {
                    Link("View on GitHub", destination: url)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 620, height: 560)
        .task { await model.watch() }
        .errorAlert(Binding(get: { model.error }, set: { model.error = $0 }))
    }
}

private struct JobSection: View {
    let model: WorkflowRunModel
    let job: GitHubJob

    var body: some View {
        Section {
            ForEach(job.steps, id: \.number) { step in
                HStack {
                    RunStatusIcon(status: step.status, conclusion: step.conclusion)
                        .frame(width: 18)
                    Text(verbatim: step.name)
                }
            }
            if let log = model.logs[job.id] {
                ScrollView {
                    Text(verbatim: log)
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 160)
            } else {
                Button("Show Log") { Task { await model.loadLog(of: job) } }
            }
        } header: {
            HStack {
                RunStatusIcon(status: job.status, conclusion: job.conclusion)
                Text(verbatim: job.name)
            }
        }
    }
}

private struct ArtifactsSection: View {
    let model: WorkflowRunModel

    var body: some View {
        Section("Artifacts") {
            ForEach(model.artifacts) { artifact in
                HStack {
                    Image(systemName: "shippingbox")
                    Text(verbatim: artifact.name)
                    Spacer()
                    Text(artifact.size, format: .byteCount(style: .file))
                        .foregroundStyle(.secondary)
                    if model.attached.contains(artifact.id) {
                        Label("Attached", systemImage: "checkmark")
                            .foregroundStyle(.green)
                    } else if model.attaching.contains(artifact.id) {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Attach to Next Drop") { Task { await model.attachToNextDrop(artifact) } }
                            .disabled(artifact.isExpired)
                    }
                }
            }
        }
    }
}

/// Runs a workflow by hand on a branch.
private struct DispatchSheet: View {
    let actions: ProjectActionsModel
    let workflow: GitHubWorkflow
    @Environment(\.dismiss) private var dismiss
    @State private var ref = ""
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Run \(workflow.name)")
                .font(.title3.bold())
            Picker("Branch", selection: $ref) {
                ForEach(actions.branches) { branch in
                    Text(verbatim: branch.name).tag(branch.name)
                }
                if !actions.branches.contains(where: { $0.name == ref }) {
                    Text(verbatim: ref).tag(ref)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Run Workflow") {
                    isRunning = true
                    Task {
                        if await actions.dispatch(workflow, ref: ref) { dismiss() }
                        isRunning = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(ref.isEmpty || isRunning)
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear { ref = actions.defaultBranch }
        .task { await actions.loadBranches() }
    }
}

/// Shows the release workflow DROP would add, and opens the pull request.
private struct ReleaseWorkflowSheet: View {
    let actions: ProjectActionsModel
    @Environment(\.dismiss) private var dismiss
    @State private var isOpening = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a Release Workflow")
                .font(.title3.bold())
            Text("DROP opens a pull request adding \(WorkflowTemplate.path). Replace its build step before merging.")
                .foregroundStyle(.secondary)
            ScrollView {
                Text(verbatim: WorkflowTemplate.release)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
            if actions.needsWorkflowScope {
                Label(
                    "GitHub only lets DROP add workflow files with the workflow permission. Sign in again to grant it.",
                    systemImage: "lock"
                )
                Button("Sign In Again with Workflow Access") { actions.grantWorkflowScope() }
            }
            HStack {
                if let url = actions.proposedWorkflow?.htmlURL {
                    Link("View Pull Request", destination: url)
                }
                Spacer()
                Button("Close", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Open Pull Request") {
                    isOpening = true
                    Task {
                        await actions.proposeReleaseWorkflow()
                        isOpening = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isOpening || actions.proposedWorkflow != nil)
            }
        }
        .padding()
        .frame(width: 600, height: 560)
    }
}
