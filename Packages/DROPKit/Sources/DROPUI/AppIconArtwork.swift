import SwiftUI

/// DROP's app icon, drawn in code so every style is available without shipping images. The geometry
/// and colors match `design/app-icon/icon.py`, which renders the bundle's icon.
public struct AppIconArtwork: View {
    private let style: AppIconStyle

    public init(style: AppIconStyle) {
        self.style = style
    }

    public var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / AppIconPainter.canvas
            context.scaleBy(x: scale, y: scale)
            AppIconPainter(style: style).draw(in: &context)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Draws an icon on a 1024 x 1024 canvas, like Apple's macOS icon template: an 824-point rounded
/// square with a 100-point margin for its shadow, and the droplet with its arrow on top.
struct AppIconPainter {
    static let canvas: CGFloat = 1024
    static let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    static let tileRadius: CGFloat = 185

    let style: AppIconStyle

    func draw(in context: inout GraphicsContext) {
        let tilePath = Path(roundedRect: Self.tile, cornerRadius: Self.tileRadius, style: .continuous)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 10))
            layer.drawLayer { tile in
                tile.clip(to: tilePath)
                drawBackground(in: &tile)
                tile.fill(Path(Self.tile), with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .white.opacity(0.2), location: 0),
                        .init(color: .white.opacity(0), location: 0.5),
                    ]),
                    startPoint: CGPoint(x: 512, y: Self.tile.minY),
                    endPoint: CGPoint(x: 512, y: Self.tile.maxY)
                ))
            }
            let rim = Path(
                roundedRect: Self.tile.insetBy(dx: 1, dy: 1),
                cornerRadius: Self.tileRadius - 1,
                style: .continuous
            )
            layer.stroke(rim, with: .color(.white.opacity(0.16)), lineWidth: 2)
        }
        drawGlyph(in: &context)
    }

    private func drawBackground(in context: inout GraphicsContext) {
        if let colors = AppIconPalette.gradient(style) {
            context.fill(Path(Self.tile), with: .linearGradient(
                Gradient(colors: colors),
                startPoint: CGPoint(x: 512, y: Self.tile.minY),
                endPoint: CGPoint(x: 512, y: Self.tile.maxY)
            ))
            return
        }
        let stripes = AppIconPalette.stripes(style)
        let total = stripes.reduce(0) { $0 + $1.weight }
        var top = Self.tile.minY
        for stripe in stripes {
            let height = Self.tile.height * stripe.weight / total
            // Half a point of overlap, so no background shows between stripes.
            let rect = CGRect(x: Self.tile.minX, y: top, width: Self.tile.width, height: height + 0.5)
            context.fill(Path(rect), with: .color(stripe.color))
            top += height
        }
        if style == .progress {
            drawProgressChevron(in: &context)
        }
    }

    /// The Progress Pride flag's chevron: nested triangles from the left edge, outermost first.
    private func drawProgressChevron(in context: inout GraphicsContext) {
        let tile = Self.tile
        for (index, color) in AppIconPalette.progressChevron.enumerated() {
            let step = CGFloat(index) * 0.075
            let tip = tile.minX + tile.width * (0.46 - step)
            let left = tile.minX - tile.width * step - 1
            var triangle = Path()
            triangle.move(to: CGPoint(x: left, y: tile.minY))
            triangle.addLine(to: CGPoint(x: tip, y: tile.midY))
            triangle.addLine(to: CGPoint(x: left, y: tile.maxY))
            triangle.closeSubpath()
            context.fill(triangle, with: .color(color))
        }
    }

    private func drawGlyph(in context: inout GraphicsContext) {
        let glyph = AppIconGlyph.path
        let onFlag = AppIconPalette.gradient(style) == nil
        let colors = AppIconPalette.glyph(style)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(onFlag ? 0.55 : 0.4), radius: 16, x: 0, y: 16))
            if onFlag {
                // A dark rim keeps the white droplet visible on light stripes.
                layer.stroke(glyph, with: .color(.black.opacity(0.35)), lineWidth: 20)
            }
            layer.fill(glyph, with: .linearGradient(
                Gradient(stops: [
                    .init(color: colors[0], location: 0),
                    .init(color: colors[1], location: 0.5),
                    .init(color: colors[2], location: 1),
                ]),
                startPoint: CGPoint(x: 230, y: 230),
                endPoint: CGPoint(x: 800, y: 800)
            ))
        }
    }
}

/// The droplet with a downward arrow cut out of it: a circle with a point on top.
enum AppIconGlyph {
    static let center = CGPoint(x: 512, y: 600)
    static let radius: CGFloat = 230
    static let apex = CGPoint(x: 512, y: 190)
    static let shaft = CGRect(x: 472, y: 410, width: 80, height: 190)
    static let head = [CGPoint(x: 388, y: 580), CGPoint(x: 636, y: 580), CGPoint(x: 512, y: 724)]

    static var path: Path {
        // Where the straight sides touch the circle.
        let beta = CGFloat.pi / 2 - asin(radius / (center.y - apex.y))
        let dx = radius * sin(beta)
        let dy = radius * cos(beta)
        let sides = polygon([
            apex, CGPoint(x: center.x + dx, y: center.y - dy), center, CGPoint(x: center.x - dx, y: center.y - dy),
        ])
        let circle = Path(ellipseIn: CGRect(
            x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
        ))
        let arrow = Path(shaft).union(polygon(head))
        return sides.union(circle).subtracting(arrow)
    }

    private static func polygon(_ points: [CGPoint]) -> Path {
        Path { path in
            path.addLines(points)
            path.closeSubpath()
        }
    }
}

/// The colors of each style. Flags follow their commonly used versions.
enum AppIconPalette {
    struct Stripe {
        let color: Color
        let weight: CGFloat
    }

    static let tealGlyph: [Color] = [Color(hex: 0x2CC4B5), Color(hex: 0x179A8E), Color(hex: 0x0A6F68)]
    static let goldGlyph: [Color] = [Color(hex: 0xFFE9A8), Color(hex: 0xE6B43A), Color(hex: 0xB8840F)]
    static let whiteGlyph: [Color] = [Color(hex: 0xFFFFFF), Color(hex: 0xEEF2F8), Color(hex: 0xC8D1DE)]
    /// Black, brown, light blue, pink and white.
    static let progressChevron: [Color] = ([0x000000, 0x784F17, 0x5BCEFA, 0xF5A9B8, 0xFFFFFF] as [UInt32])
        .map { Color(hex: $0) }

    /// The droplet's diagonal gradient: teal on DROP's tile, gold on graphite and silver, white on
    /// blue and on every flag.
    static func glyph(_ style: AppIconStyle) -> [Color] {
        switch style {
        case .teal: tealGlyph
        case .graphite, .silver: goldGlyph
        default: whiteGlyph
        }
    }

    /// The top-to-bottom gradient of a plain style, or `nil` for a flag.
    static func gradient(_ style: AppIconStyle) -> [Color]? {
        switch style {
        case .teal: [Color(hex: 0xF4FBFA), Color(hex: 0xD3ECE9)]
        case .graphite: [Color(hex: 0x5B616B), Color(hex: 0x24282E)]
        case .blue: [Color(hex: 0x4F9BFF), Color(hex: 0x0B4FD0)]
        case .silver: [Color(hex: 0xFBFBFD), Color(hex: 0xC7CCD4)]
        default: nil
        }
    }

    /// A flag's stripes from top to bottom.
    static func stripes(_ style: AppIconStyle) -> [Stripe] {
        let colors: [UInt32]
        switch style {
        case .rainbow, .progress: colors = [0xE40303, 0xFF8C00, 0xFFED00, 0x008026, 0x004DFF, 0x750787]
        case .transgender: colors = [0x5BCEFA, 0xF5A9B8, 0xFFFFFF, 0xF5A9B8, 0x5BCEFA]
        case .nonbinary: colors = [0xFCF434, 0xFFFFFF, 0x9C59D1, 0x2C2C2C]
        case .bisexual:
            return [
                Stripe(color: Color(hex: 0xD60270), weight: 2),
                Stripe(color: Color(hex: 0x9B4F96), weight: 1),
                Stripe(color: Color(hex: 0x0038A8), weight: 2),
            ]
        case .pansexual: colors = [0xFF218C, 0xFFD800, 0x21B1FF]
        case .lesbian: colors = [0xD52D00, 0xEF7627, 0xFF9A56, 0xFFFFFF, 0xD162A4, 0xB55690, 0xA30262]
        case .asexual: colors = [0x000000, 0xA3A3A3, 0xFFFFFF, 0x800080]
        case .aromantic: colors = [0x3DA542, 0xA7D379, 0xFFFFFF, 0xA9A9A9, 0x000000]
        case .teal, .graphite, .blue, .silver: colors = []
        }
        return colors.map { Stripe(color: Color(hex: $0), weight: 1) }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
