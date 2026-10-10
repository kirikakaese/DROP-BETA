import SwiftUI

/// Settings → App Lock: lock DROP's window with Touch ID or the login password.
struct AppLockSettingsView: View {
    @Bindable var appLock: AppLockModel

    var body: some View {
        Form {
            if appLock.isAvailable {
                Toggle("Lock DROP with Touch ID or password", isOn: $appLock.settings.isEnabled)
                IdleLockPicker(settings: $appLock.settings)
                    .disabled(!appLock.settings.isEnabled)
                Button("Lock Now") { appLock.lock() }
                    .disabled(!appLock.settings.isEnabled)
            } else {
                Text("The app lock needs a login password on this Mac.")
                    .foregroundStyle(.secondary)
            }
            Text("""
                DROP also locks when your screen locks or the Mac goes to sleep. A drop that is already \
                running keeps running while DROP is locked.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

/// How long DROP may sit idle before it locks.
struct IdleLockPicker: View {
    @Binding var settings: AppLockSettings

    var body: some View {
        Picker("Lock after", selection: $settings.idleMinutes) {
            ForEach(AppLockSettings.idleChoices, id: \.self) { minutes in
                switch minutes {
                case 0: Text("Only at launch and screen lock").tag(0)
                case 60: Text("1 hour idle").tag(60)
                case 1: Text("1 minute idle").tag(1)
                default: Text("\(minutes) minutes idle").tag(minutes)
                }
            }
        }
    }
}
