import AppKit
import DROPGitHub
import SwiftUI

/// Shows the device flow code while DROP waits for you to approve it on GitHub.
struct SignInSheet: View {
    let account: AccountModel
    let authorization: DeviceAuthorization
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Sign In with GitHub")
                .font(.title2.bold())
            Text("Enter this code on GitHub to let DROP use your account:")
                .multilineTextAlignment(.center)
            Text(authorization.userCode)
                .font(.system(.largeTitle, design: .monospaced).bold())
                .textSelection(.enabled)
            HStack {
                Button("Copy Code", action: copyCode)
                Button("Open GitHub") {
                    copyCode()
                    openURL(authorization.verificationURL)
                }
                .keyboardShortcut(.defaultAction)
            }
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for you to approve DROP on GitHub…")
            }
            .foregroundStyle(.secondary)
            Button("Cancel", role: .cancel) { account.cancelSignIn() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 400)
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(authorization.userCode, forType: .string)
    }
}
