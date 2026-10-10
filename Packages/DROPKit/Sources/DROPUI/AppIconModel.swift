import AppKit
import Observation
import SwiftUI

/// The tile behind the droplet: DROP's teal, another color, or a pride flag.
public enum AppIconStyle: String, CaseIterable, Identifiable, Sendable {
    case teal
    case graphite
    case blue
    case silver
    case rainbow
    case progress
    case transgender
    case nonbinary
    case bisexual
    case pansexual
    case lesbian
    case asexual
    case aromantic

    public var id: String { rawValue }

    /// The icon in the app bundle, which Finder, Launchpad and the Dock show while DROP isn't running.
    public static let standard: AppIconStyle = .teal

    public static let colors: [AppIconStyle] = [.teal, .graphite, .blue, .silver]
    public static let pride: [AppIconStyle] = allCases.filter { !colors.contains($0) }

    public var isStandard: Bool { self == .standard }

    public var title: LocalizedStringKey {
        switch self {
        case .teal: "Teal"
        case .graphite: "Graphite"
        case .blue: "Blue"
        case .silver: "Silver"
        case .rainbow: "Rainbow"
        case .progress: "Progress Pride"
        case .transgender: "Transgender"
        case .nonbinary: "Nonbinary"
        case .bisexual: "Bisexual"
        case .pansexual: "Pansexual"
        case .lesbian: "Lesbian"
        case .asexual: "Asexual"
        case .aromantic: "Aromantic"
        }
    }
}

/// The app icon picked in Settings. macOS has no alternate app icons, so DROP shows the choice in
/// the Dock while it runs; the bundle (and its signature) stays untouched.
@MainActor
@Observable
public final class AppIconModel {
    private static let styleKey = "appIcon.style"

    public var style: AppIconStyle {
        didSet {
            guard style != oldValue else { return }
            defaults.set(style.rawValue, forKey: Self.styleKey)
            apply()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let setDockIcon: @MainActor (NSImage?) -> Void

    /// - Parameter setDockIcon: Shows an icon in the Dock; `nil` restores the bundle's icon.
    public init(
        defaults: UserDefaults = .standard,
        setDockIcon: @escaping @MainActor (NSImage?) -> Void = { NSApplication.shared.applicationIconImage = $0 }
    ) {
        self.defaults = defaults
        self.setDockIcon = setDockIcon
        style = defaults.string(forKey: Self.styleKey).flatMap(AppIconStyle.init(rawValue:)) ?? .standard
    }

    /// Shows the chosen icon in the Dock. Called once DROP has finished launching and on every change.
    public func apply() {
        setDockIcon(style.isStandard ? nil : Self.image(for: style))
    }

    public func restoreDefault() {
        style = .standard
    }

    /// Renders an icon. `size` is in points; the image has twice as many pixels.
    public static func image(for style: AppIconStyle, size: CGFloat = 512) -> NSImage? {
        let renderer = ImageRenderer(content: AppIconArtwork(style: style).frame(width: size, height: size))
        renderer.scale = 2
        return renderer.nsImage
    }
}
