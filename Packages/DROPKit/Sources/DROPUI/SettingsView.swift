import DROPCore
import SwiftUI

/// The size of a settings tab.
public enum SettingsTab {
    public static let width: CGFloat = 520
    public static let height: CGFloat = 360
}

/// The Settings window.
public struct SettingsView: View {
    private let account: AccountModel

    public init(account: AccountModel) {
        self.account = account
    }

    public var body: some View {
        TabView {
            GeneralSettingsView()
                .frame(width: SettingsTab.width, height: SettingsTab.height)
                .tabItem { Label("General", systemImage: "gearshape") }
            AccountSettingsView(account: account)
                .frame(width: SettingsTab.width, height: SettingsTab.height)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
    }
}

struct GeneralSettingsView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: version)
                if let slug = AppRepository.slug() {
                    LabeledContent("Source Code") {
                        Link(slug.description, destination: slug.webURL)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
