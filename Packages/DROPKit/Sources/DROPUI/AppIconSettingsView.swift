import SwiftUI

/// Settings → App Icon: pick a color or pride flag for DROP's Dock icon.
struct AppIconSettingsView: View {
    @Bindable var model: AppIconModel

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    AppIconArtwork(style: model.style)
                        .frame(width: 88, height: 88)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("""
                            DROP shows this icon in the Dock while it's running. Finder and Launchpad keep the \
                            standard icon.
                            """)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Restore Default") { model.restoreDefault() }
                            .disabled(model.style.isStandard)
                    }
                }
            }
            Section("Colors") {
                optionGrid { options(AppIconStyle.colors) }
            }
            Section("Pride") {
                optionGrid { options(AppIconStyle.pride) }
            }
        }
        .formStyle(.grouped)
    }

    private func optionGrid(@ViewBuilder content: () -> some View) -> some View {
        let options = content()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 12) {
            options
        }
        .padding(.vertical, 4)
    }

    private func options(_ styles: [AppIconStyle]) -> some View {
        ForEach(styles) { style in
            AppIconOption(style: style, isSelected: model.style == style) { model.style = style }
        }
    }
}

/// One selectable icon with its name below.
private struct AppIconOption: View {
    let style: AppIconStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                AppIconArtwork(style: style)
                    .frame(width: 48, height: 48)
                    .padding(3)
                    .background {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
                    }
                Text(style.title)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
