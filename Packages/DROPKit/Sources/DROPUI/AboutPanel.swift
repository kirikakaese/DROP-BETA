import AppKit

/// Shows the standard About panel with DROP's full product name and license.
@MainActor
public enum AboutPanel {
    public static let productName = "Distribution & Release Orchestration Platform"
    public static let shortName = "DROP"

    public static func show() {
        let credits = NSAttributedString(
            string: String(localized: """
                DROP: drop new versions to GitHub Releases and package registries.\n\
                Released under the GNU General Public License v3.0.
                """),
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: productName,
            .credits: credits,
        ])
        NSApplication.shared.activate()
    }
}
