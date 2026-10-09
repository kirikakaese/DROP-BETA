import DROPCore
import Foundation
import UserNotifications

/// Tells you when a drop finished or failed, also while DROP is in the background.
public protocol DropNotifying: Sendable {
    func dropped(tag: String, project: String, url: URL?) async
    func dropFailed(tag: String, project: String, step: String) async
}

/// `DropNotifying` through Notification Center. Asks for permission the first time it is needed.
public struct UserNotificationDropNotifier: DropNotifying {
    public init() {}

    public func dropped(tag: String, project: String, url: URL?) async {
        await post(title: DropWording.doneTitle(version: tag), body: project)
    }

    public func dropFailed(tag: String, project: String, step: String) async {
        await post(
            title: DropWording.failedTitle,
            body: String(localized: "\(project) \(tag) stopped at “\(step)”.")
        )
    }

    private func post(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

/// `DropNotifying` that records what it would have shown, for tests and previews.
public actor RecordingDropNotifier: DropNotifying {
    public private(set) var notifications: [String] = []

    public init() {}

    public func dropped(tag: String, project: String, url: URL?) async {
        notifications.append("dropped \(tag)")
    }

    public func dropFailed(tag: String, project: String, step: String) async {
        notifications.append("failed \(tag) at \(step)")
    }
}
