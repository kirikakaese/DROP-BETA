import DROPCore
import DROPGitHub
import DROPServices
import SwiftUI

/// The selected project: the repository, its drops on GitHub, DROP's history and the audit log.
struct ProjectDetailView: View {
    let model: ProjectsModel
    let project: Project
    @State private var activity: ProjectActivityModel?
    @State private var actions: ProjectActionsModel?
    @State private var editing: GitHubRelease?
    @State private var deleting: GitHubRelease?

    private struct ReloadKey: Equatable {
        let projectID: Project.ID
        let dropsFinished: Int
        let isSignedIn: Bool
    }

    private var reloadKey: ReloadKey {
        ReloadKey(projectID: project.id, dropsFinished: model.dropsFinished, isSignedIn: model.account.isSignedIn)
    }

    var body: some View {
        Form {
            RepositorySection(model: model, project: project)
            if let activity {
                if let unreleased = activity.unreleased {
                    UnreleasedSection(changes: unreleased)
                }
                ReleasesSection(activity: activity, editing: $editing, deleting: $deleting)
                HistorySection(activity: activity)
            }
            if let actions {
                ActionsSections(actions: actions)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(project.slug.name)
        .task(id: reloadKey) {
            let current: ProjectActivityModel
            if let activity, activity.project.id == project.id {
                current = activity
            } else {
                current = model.activityModel(for: project)
            }
            activity = current
            if actions?.project.id != project.id { actions = model.actionsModel(for: project) }
            await current.load(branch: model.repositories[project.id]?.defaultBranch ?? "main")
            await actions?.load()
        }
        .sheet(item: $editing) { release in
            if let activity {
                ReleaseEditSheet(activity: activity, release: release)
            }
        }
        .confirmationDialog(
            deleting.map { String(localized: "Delete the GitHub Release \($0.tagName)?") } ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { release in
            Button("Delete GitHub Release", role: .destructive) {
                Task { await activity?.delete(release, includingTag: false) }
            }
            if !release.isDraft {
                Button("Delete GitHub Release and Tag", role: .destructive) {
                    Task { await activity?.delete(release, includingTag: true) }
                }
            }
        } message: { _ in
            Text("Its assets are deleted too. This can't be undone.")
        }
        .errorAlert(Binding(get: { activity?.error }, set: { activity?.error = $0 }))
        .modifier(OptionalActionsSheets(actions: actions))
    }
}

/// The repository: where it is, what GitHub says about it, and whether it's still there.
private struct RepositorySection: View {
    let model: ProjectsModel
    let project: Project

    var body: some View {
        if model.missing.contains(project.id) {
            Section {
                Label(
                    "GitHub can't find this repository anymore. It may be deleted, or you lost access.",
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
        Section {
            LabeledContent("Repository") {
                Link(project.slug.description, destination: project.slug.webURL)
            }
            if let repository = model.repositories[project.id] {
                RepositoryDetails(repository: repository)
            }
            LabeledContent("Added") {
                Text(project.addedAt, format: .dateTime.day().month().year())
            }
        }
    }
}

/// What a drop would contain now, and the version DROP suggests for it.
private struct UnreleasedSection: View {
    let changes: UnreleasedChanges

    var body: some View {
        Section("Unreleased") {
            LabeledContent("Last Release") {
                if let since = changes.since {
                    Text(verbatim: since).monospaced()
                } else {
                    Text("None yet")
                }
            }
            LabeledContent("Changes") {
                Text(changes.notableCount, format: .number)
            }
            LabeledContent("Suggested Next Version") {
                Text(verbatim: changes.suggestion.tagName(for: changes.suggestion.bump, beta: false))
                    .monospaced()
            }
        }
    }
}

/// The project's GitHub Releases, newest first.
private struct ReleasesSection: View {
    let activity: ProjectActivityModel
    @Binding var editing: GitHubRelease?
    @Binding var deleting: GitHubRelease?

    var body: some View {
        Section {
            if activity.releases.isEmpty {
                if activity.isLoading {
                    Text("Loading…").foregroundStyle(.secondary)
                } else {
                    Text("No GitHub Releases yet.").foregroundStyle(.secondary)
                }
            }
            ForEach(activity.releases) { release in
                ReleaseRow(release: release, isLatest: release.id == activity.latest?.id)
                    .contextMenu {
                        if let url = release.htmlURL {
                            Link("Open on GitHub", destination: url)
                        }
                        Button("Edit…") { editing = release }
                        Button("Delete…", role: .destructive) { deleting = release }
                    }
            }
        } header: {
            Text(DropWording.historyTitle)
        }
    }
}

private struct ReleaseRow: View {
    let release: GitHubRelease
    let isLatest: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: release.title)
                Text(verbatim: release.tagName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isLatest { Badge(text: String(localized: "Latest"), color: .green) }
            if release.isPrerelease { Badge(text: String(localized: "Prerelease"), color: .orange) }
            if release.isDraft { Badge(text: String(localized: "Draft"), color: .gray) }
            if let date = release.publishedAt ?? release.createdAt {
                Text(date, format: .dateTime.day().month().year())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(verbatim: text)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
    }
}

/// DROP's own record of drops for this project, and the audit log.
private struct HistorySection: View {
    let activity: ProjectActivityModel

    var body: some View {
        Section("History") {
            if activity.history.isEmpty {
                Text("You haven't dropped this project with DROP yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(activity.history) { record in
                HStack {
                    Image(systemName: record.outcome == .failed ? "xmark.octagon.fill" : "checkmark.circle.fill")
                        .foregroundStyle(record.outcome == .failed ? Color.red : Color.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: summary(of: record))
                        if let step = record.failedStep {
                            Text(verbatim: step).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(record.startedAt, format: .dateTime.day().month().hour().minute())
                        .foregroundStyle(.secondary)
                }
            }
            if !activity.auditLog.isEmpty {
                DisclosureGroup("Activity") {
                    ForEach(activity.auditLog) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: entry.succeeded ? "checkmark" : "xmark")
                                .foregroundStyle(entry.succeeded ? Color.secondary : Color.red)
                            Text(verbatim: entry.message)
                            Spacer()
                            Text(entry.date, format: .dateTime.day().month().hour().minute().second())
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private func summary(of record: DropRecord) -> String {
        switch record.outcome {
        case .dropped: DropWording.doneTitle(version: record.tagName)
        case .failed: "\(DropWording.failedTitle): \(record.tagName)"
        case nil: DropWording.progressTitle(version: record.tagName)
        }
    }
}

/// Edits a GitHub Release's title, notes and flags.
private struct ReleaseEditSheet: View {
    let activity: ProjectActivityModel
    let release: GitHubRelease
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var isDraft = false
    @State private var isPrerelease = false
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: release.tagName)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            Form {
                TextField("Title", text: $title)
                Toggle(DropWording.betaTitle, isOn: $isPrerelease)
                if release.isDraft {
                    Toggle("Draft", isOn: $isDraft)
                        .help("Turn this off to publish the draft. GitHub then creates the tag.")
                }
                Section("Release Notes") {
                    MarkdownEditor(text: $notes)
                        .frame(minHeight: 200)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    isSaving = true
                    Task {
                        let fields = ReleaseFields(
                            name: title, body: notes, isDraft: isDraft, isPrerelease: isPrerelease
                        )
                        if await activity.update(release, fields) { dismiss() }
                        isSaving = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
            }
            .padding()
        }
        .frame(width: 560, height: 520)
        .onAppear {
            title = release.name ?? ""
            notes = release.body ?? ""
            isDraft = release.isDraft
            isPrerelease = release.isPrerelease
        }
    }
}

/// `ActionsSheets` once the project's actions are loaded.
private struct OptionalActionsSheets: ViewModifier {
    let actions: ProjectActionsModel?

    @ViewBuilder func body(content: Content) -> some View {
        if let actions {
            content.modifier(ActionsSheets(actions: actions))
        } else {
            content
        }
    }
}
