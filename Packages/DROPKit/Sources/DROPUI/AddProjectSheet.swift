import DROPGitHub
import SwiftUI

/// Picks one of your repositories, or takes any owner/name, and adds it as a project.
struct AddProjectSheet: View {
    @Bindable var model: ProjectsModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: GitHubRepository.ID?

    private var matches: [GitHubRepository] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return model.yourRepositories.filter { repository in
            guard !model.isAdded(repository) else { return false }
            return trimmed.isEmpty || repository.fullName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var input: String {
        if let selection, let repository = model.yourRepositories.first(where: { $0.id == selection }) {
            return repository.fullName
        }
        return query.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Project")
                .font(.headline)
            TextField("owner/name or github.com address", text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { selection = nil }
            List(matches, selection: $selection) { repository in
                RepositoryRow(repository: repository)
            }
            .overlay {
                if model.isLoadingRepositories {
                    ProgressView()
                }
            }
            if let error = model.addError {
                Label(error.whatHappened, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    Task {
                        if await model.addProject(input) { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(input.isEmpty || model.isAdding)
            }
        }
        .padding()
        .frame(width: 480, height: 440)
        .task {
            model.addError = nil
            await model.loadYourRepositories()
        }
    }
}

private struct RepositoryRow: View {
    let repository: GitHubRepository

    var body: some View {
        HStack {
            Image(systemName: repository.isPrivate ? "lock" : "book.closed")
                .foregroundStyle(.secondary)
            Text(verbatim: repository.fullName)
            Spacer()
            if repository.isArchived {
                Text("Archived")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
