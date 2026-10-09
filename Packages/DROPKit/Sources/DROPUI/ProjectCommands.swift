import DROPCore
import SwiftUI

/// File → Add Project… and the Project menu. Drop… opens the plan for the selected project;
/// nothing is sent to GitHub before the Drop button on that plan is pressed.
public struct ProjectCommands: Commands {
    private let model: ProjectsModel

    public init(model: ProjectsModel) {
        self.model = model
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Project…") { model.isAddingProject = true }
                .keyboardShortcut("n")
                .disabled(!model.canAddProject)
        }
        CommandMenu("Project") {
            Button(DropWording.menuTitle) { model.startDrop() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canDrop)
        }
    }
}
