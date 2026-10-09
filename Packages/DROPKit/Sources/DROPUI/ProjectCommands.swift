import SwiftUI

/// The Project menu. Drop… opens the plan for the selected project; nothing is sent to GitHub
/// before the Drop button on that plan is pressed.
public struct ProjectCommands: Commands {
    private let model: ProjectsModel

    public init(model: ProjectsModel) {
        self.model = model
    }

    public var body: some Commands {
        CommandMenu("Project") {
            Button(DropWording.menuTitle) {}
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canDrop)
        }
    }
}
