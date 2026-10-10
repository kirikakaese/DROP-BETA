import DROPCore
import DROPRegistries
import DROPServices
import SwiftUI

/// Who performs each destination of a drop: DROP (Managed), an existing automation (External) or
/// nobody (Off), with what DROP found in the repository.
struct DestinationsSection: View {
    let activity: ProjectActivityModel
    let report: AutomationReport

    var body: some View {
        Section {
            ForEach(report.settings) { setting in
                DestinationRow(activity: activity, report: report, setting: setting)
            }
        } header: {
            Text("Destinations")
        } footer: {
            Text("External destinations are left to the automation that owns them; DROP only checks the result.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct DestinationRow: View {
    let activity: ProjectActivityModel
    let report: AutomationReport
    let setting: DestinationSetting

    private var finding: AutomationFinding? {
        report.findings.first { $0.destination == setting.destination }
    }

    private var isManagedRegistry: Bool {
        setting.destination != .githubRelease && setting.mode == .managed
    }

    private var setup: RegistrySetup { activity.setup(for: setting.destination) }

    var body: some View {
        LabeledContent {
            HStack {
                if isManagedRegistry {
                    if setup.writesFile && activity.registrySetups[setting.destination]?.isComplete == true {
                        Button("Try It…") { Task { await activity.preview(setting.destination) } }
                            .disabled(activity.isPreviewing || activity.latest == nil)
                            .help("Shows what DROP would write for the latest release, without writing anything.")
                    }
                    Button("Set Up…") { activity.editSetup(for: setting.destination) }
                }
                Picker("Performed by", selection: Binding(
                    get: { setting.mode },
                    set: { activity.setMode($0, for: setting.destination) }
                )) {
                    ForEach(OwnershipMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: setting.destination.title)
                    Text(verbatim: caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: setting.destination.systemImage)
            }
        }
    }

    private var caption: String {
        switch setting.mode {
        case .managed:
            return isManagedRegistry ? registryCaption : String(localized: "DROP does this.")
        case .external:
            let owner = setting.ownerName ?? String(localized: "An automation")
            if let found = finding?.evidence {
                return String(localized: "\(owner) does this (found “\(found)”). DROP watches and verifies.")
            }
            return String(localized: "\(owner) does this. DROP watches and verifies.")
        case .off:
            return String(localized: "Not part of drops.")
        }
    }

    private var registryCaption: String {
        guard let saved = activity.registrySetups[setting.destination], saved.isComplete else {
            return String(localized: "Set up how DROP publishes this.")
        }
        if !saved.writesFile {
            let workflow = saved.workflowName ?? ""
            return String(localized: "DROP starts \(workflow) on each tag.")
        }
        switch saved.writeMode {
        case .pullRequest:
            return String(localized: "DROP updates \(saved.path) in \(saved.repository) through a pull request.")
        case .directCommit:
            return String(localized: "DROP commits \(saved.path) to \(saved.repository).")
        }
    }
}

/// Asks before DROP takes over a destination an automation owns, naming that automation.
struct TakeoverConfirmation: ViewModifier {
    @Bindable var activity: ProjectActivityModel

    func body(content: Content) -> some View {
        content.confirmationDialog(
            activity.pendingTakeover.map { String(localized: "Let DROP do \($0.destination.title) instead?") } ?? "",
            isPresented: Binding(
                get: { activity.pendingTakeover != nil },
                set: { if !$0 { activity.pendingTakeover = nil } }
            ),
            presenting: activity.pendingTakeover
        ) { _ in
            Button("Let DROP Do It", role: .destructive) { activity.confirmTakeover() }
            Button("Cancel", role: .cancel) { activity.pendingTakeover = nil }
        } message: { setting in
            Text(Self.warning(owner: activity.automation?.setting(for: setting.destination).ownerName ?? ""))
        }
    }

    private static func warning(owner: String) -> String {
        String(localized: "\(owner) already does this. If DROP does it too, they will overwrite each other.")
    }
}

/// The sheets and dialogs of the Destinations section.
struct DestinationSheets: ViewModifier {
    @Bindable var activity: ProjectActivityModel

    func body(content: Content) -> some View {
        content
            .modifier(TakeoverConfirmation(activity: activity))
            .sheet(item: $activity.editingRegistry) { setup in
                RegistrySetupSheet(activity: activity, setup: setup)
            }
            .sheet(item: $activity.registryPreview) { edit in
                RegistryPreviewSheet(edit: edit)
            }
    }
}
