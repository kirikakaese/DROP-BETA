import DROPCore
import SwiftUI

/// Settings → Account: who is signed in, and what DROP may do with the account.
struct AccountSettingsView: View {
    let account: AccountModel

    private static let applicationsURL = URL(string: "https://github.com/settings/applications")

    var body: some View {
        Form {
            Section {
                accountRow
                if !account.canSignIn {
                    Text("This build has no GitHub Client ID, so it can't sign in. See SETUP.md.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Permissions") {
                LabeledContent {
                    Text("Create tags, GitHub Releases, assets and pull requests in public and private repositories.")
                } label: {
                    Text(verbatim: "repo").monospaced()
                }
                Text("DROP asks for workflow access only when you let it add a release workflow to a repository.")
                    .foregroundStyle(.secondary)
                Text("Your tokens are kept in the Keychain and never written anywhere else.")
                    .foregroundStyle(.secondary)
                if let url = Self.applicationsURL {
                    Link("Review or revoke DROP's access on GitHub", destination: url)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var accountRow: some View {
        switch account.phase {
        case .signedIn:
            HStack(spacing: 12) {
                AsyncImage(url: account.user?.avatarURL) { image in
                    image.resizable()
                } placeholder: {
                    Image(systemName: "person.crop.circle").resizable()
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                VStack(alignment: .leading) {
                    Text(verbatim: account.user?.name ?? account.user?.login ?? "")
                    if let login = account.user?.login {
                        Text(verbatim: "@\(login)").foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Sign Out") { Task { await account.signOut() } }
            }
        case .waitingForApproval:
            LabeledContent("GitHub") {
                ProgressView().controlSize(.small)
            }
        case .loading, .signedOut, .sessionExpired:
            LabeledContent("GitHub") {
                Button("Sign In with GitHub…") { account.signIn() }
                    .disabled(!account.canSignIn)
            }
            if account.phase == .sessionExpired {
                Text("Your GitHub session has ended. Sign in again to keep using DROP with GitHub.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
