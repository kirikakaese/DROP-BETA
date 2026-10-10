import DROPCore
import DROPGitHub
import DROPServices
import SwiftUI
import UniformTypeIdentifiers

/// The drop sheet: the form, then "Ready to Drop", then progress and the result.
struct DropSheet: View {
    @Bindable var model: DropModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(model.headline)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error = model.formError {
                Label(error.whatHappened, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            Divider()
            buttons
                .padding()
        }
        .frame(width: 600, height: 640)
        .task {
            await model.loadBranches()
            await model.loadAutomation()
            await model.loadSuggestion()
        }
        .interactiveDismissDisabled(model.isRunning)
    }

    @ViewBuilder private var content: some View {
        switch model.stage {
        case .editing, .planning:
            DropFormView(model: model)
        case .ready(let plan):
            ReadyToDropView(plan: plan)
        case .dropping(let plan):
            DropProgressView(plan: plan, states: model.stepStates, result: nil, error: nil)
        case .dropped(let plan, let result):
            DropProgressView(plan: plan, states: model.stepStates, result: result, error: nil)
        case .failed(let plan, let error):
            DropProgressView(plan: plan, states: model.stepStates, result: nil, error: error)
        }
    }

    @ViewBuilder private var buttons: some View {
        HStack {
            switch model.stage {
            case .editing, .planning:
                if model.stage == .planning {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Review…") { Task { await model.review() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canReview)
            case .ready:
                Button("Back") { model.backToEditing() }
                Spacer()
                Button("Cancel", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(DropWording.actionTitle(version: model.tagName)) { Task { await model.drop() } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            case .dropping:
                Spacer()
                ProgressView().controlSize(.small)
            case .dropped(_, let result):
                if let url = result.release.htmlURL {
                    Link("View on GitHub", destination: url)
                }
                if let url = result.changelogPullRequest?.htmlURL {
                    Link("View Changelog Pull Request", destination: url)
                }
                ForEach(Array(result.registryPullRequests.enumerated()), id: \.offset) { _, pullRequest in
                    if let url = pullRequest.htmlURL {
                        Link(String(localized: "View Pull Request #\(pullRequest.number)"), destination: url)
                    }
                }
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            case .failed:
                Button("Back") { model.backToEditing() }
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// The drop form: version, target, options, release notes and assets.
struct DropFormView: View {
    @Bindable var model: DropModel
    @State private var isImporting = false

    var body: some View {
        Form {
            VersionSection(model: model)
            Section {
                Picker("Branch", selection: $model.targetBranch) {
                    ForEach(model.branches) { branch in
                        Text(verbatim: branch.name).tag(branch.name)
                    }
                    if !model.branches.contains(where: { $0.name == model.targetBranch }) {
                        Text(verbatim: model.targetBranch).tag(model.targetBranch)
                    }
                }
                .disabled(model.targetsCommit)
                Toggle("Tag a specific commit", isOn: $model.targetsCommit)
                if model.targetsCommit {
                    TextField("Commit SHA", text: $model.commitSHA)
                        .monospaced()
                }
            } header: {
                Text("Target")
            } footer: {
                Text("Used only when the tag doesn't exist yet.")
                    .foregroundStyle(.secondary)
            }
            Section {
                if let automation = model.releaseAutomation {
                    Label(automationNotice(automation), systemImage: "gearshape.2")
                }
                Toggle(DropWording.betaTitle, isOn: $model.isPrerelease)
                    .help("Marks the GitHub Release as a prerelease.")
                if let notice = model.registryNotice {
                    Label(notice, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
                if model.releaseAutomation == nil {
                    Toggle("Save as Draft", isOn: $model.isDraft)
                        .help("Only you can see a draft. GitHub creates the tag when you publish it.")
                }
            }
            Section("Release Notes") {
                MarkdownEditor(text: $model.notes)
                    .frame(minHeight: 140)
                Toggle("Add to CHANGELOG.md through a pull request", isOn: $model.updatesChangelog)
                    .help("Opens a pull request; nothing is pushed to the branch directly.")
            }
            if model.releaseAutomation == nil {
                AssetsSection(model: model, isImporting: $isImporting)
            }
        }
        .formStyle(.grouped)
        .disabled(model.stage == .planning)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { model.addAssets(urls) }
        }
    }
}

extension DropFormView {
    func automationNotice(_ automation: ReleaseAutomation) -> String {
        let name = automation.name
        if automation.startsOnTag {
            return String(localized: "\(name) creates the GitHub Release on tag push. DROP pushes the tag and watches.")
        }
        return String(localized: "\(name) creates the GitHub Release. DROP pushes the tag, starts \(name) and watches.")
    }
}

/// The suggested next version, the tag and the title.
private struct VersionSection: View {
    @Bindable var model: DropModel

    var body: some View {
        Section {
            if model.changes != nil {
                Picker("Next Version", selection: $model.bump) {
                    ForEach(VersionBump.allCases.reversed(), id: \.self) { bump in
                        Text(bump.title).tag(bump)
                    }
                }
                .pickerStyle(.segmented)
            }
            TextField("Tag", text: $model.tagName, prompt: Text(verbatim: "v1.2.3"))
            TextField("Title", text: $model.title, prompt: Text("Same as the tag"))
        } footer: {
            if let summary = model.suggestionSummary {
                Text(verbatim: summary)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The files to attach, and whether to add `SHA256SUMS.txt`.
private struct AssetsSection: View {
    @Bindable var model: DropModel
    @Binding var isImporting: Bool

    var body: some View {
        Section("Assets") {
            ForEach(model.assets) { asset in
                HStack {
                    Image(systemName: "doc")
                    Text(verbatim: asset.name)
                    Spacer()
                    Text(asset.size, format: .byteCount(style: .file))
                        .foregroundStyle(.secondary)
                    Button {
                        model.removeAsset(named: asset.name)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this asset")
                }
            }
            Button("Add Files…") { isImporting = true }
            Toggle("Add \(Checksums.fileName)", isOn: $model.includesChecksums)
                .disabled(model.assets.isEmpty)
        }
    }
}

/// "Ready to Drop": every step the drop performs and who performs it. Nothing has been sent yet.
struct ReadyToDropView: View {
    let plan: DropPlan

    var body: some View {
        Form {
            Section {
                LabeledContent("Repository") { Text(verbatim: plan.request.slug.description) }
                LabeledContent("Tag") { Text(verbatim: plan.request.tagName).monospaced() }
                if plan.request.isPrerelease {
                    LabeledContent("GitHub Release") { Text("Prerelease") }
                }
                if plan.request.isDraft {
                    LabeledContent("GitHub Release") { Text("Draft") }
                }
            }
            if plan.isRedrop {
                Section {
                    Label(
                        "Dropping this tag again updates its GitHub Release and replaces assets with the same names.",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
            }
            Section {
                ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                    LabeledContent {
                        Text(verbatim: step.performer.title)
                            .foregroundStyle(step.performer == .drop ? Color.secondary : Color.orange)
                    } label: {
                        Text(verbatim: "\(index + 1). \(step.title)")
                    }
                }
            } header: {
                Text("Steps")
            } footer: {
                Text("Nothing has been sent to GitHub yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// The steps of a running or finished drop, and how it ended.
struct DropProgressView: View {
    let plan: DropPlan
    let states: [DropModel.StepState]
    let result: DropResult?
    let error: DROPError?

    var body: some View {
        Form {
            Section {
                ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                    HStack {
                        icon(for: index < states.count ? states[index] : .pending)
                            .frame(width: 18)
                        Text(verbatim: step.title)
                    }
                }
            }
            if let result, !result.unverified.isEmpty {
                Section {
                    Label(
                        "GitHub reported no checksum for \(unverifiedNames(result)), so it wasn't verified.",
                        systemImage: "questionmark.circle"
                    )
                }
            }
            if let error {
                Section {
                    Label(error.whatHappened, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    if let howToFix = error.howToFix {
                        Text(howToFix)
                    }
                    if let details = error.details {
                        Text(verbatim: details)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func unverifiedNames(_ result: DropResult) -> String {
        result.unverified.formatted(.list(type: .and))
    }

    @ViewBuilder private func icon(for state: DropModel.StepState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle").foregroundStyle(.secondary)
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }
}

/// A plain-text editor for Markdown with a preview.
struct MarkdownEditor: View {
    @Binding var text: String
    @State private var isPreviewing = false

    var body: some View {
        VStack(alignment: .leading) {
            Picker("Release Notes", selection: $isPreviewing) {
                Text("Write").tag(false)
                Text("Preview").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if isPreviewing {
                ScrollView {
                    Text(Self.render(text))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            } else {
                TextEditor(text: $text)
                    .font(.body.monospaced())
            }
        }
    }

    static func render(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }
}
