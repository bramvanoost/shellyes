import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// The fourteen achievement badges, drawn from the app's own palette
/// and the brand shell rather than a separate art file. Same trick as
/// `IconExporter`: the artwork IS SwiftUI, and a DEBUG-only export
/// turns it into the 512x512 PNGs App Store Connect wants.
///
/// Game Center crops achievement art to a circle in most of its
/// surfaces, so every badge is designed circle-first and the square is
/// just the canvas it sits on.

/// The three families. The ring colour is the one thing that separates
/// them at a glance when fourteen sit in a grid.
enum BadgeFamily {
    case skill      // how you played
    case milestone  // time served
    case silly      // on-brand nonsense

    var accent: Color {
        switch self {
        case .skill: return .coinGoldLight
        // Lifted well clear of the plum ground; a flat lavender sank
        // into it and the family stopped reading.
        case .milestone: return Color(red: 214/255, green: 200/255, blue: 236/255)
        case .silly: return .coralLight
        }
    }
}

/// Marks follow one rule: the skill family speaks in the game's own
/// objects (pearls, shells, water), and the counting families speak in
/// numerals, because a number is what they are about.
enum BadgeMark {
    case none
    case numeral(String)
    case pearls(Int)
    case shells(Int)
    case waves(Int)
}

struct AchievementBadge: View {
    var family: BadgeFamily
    var mark: BadgeMark = .none
    var shellTop: Color = .pearlHighlight
    var shellBottom: Color = .safePeachDark
    var size: CGFloat = 512

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.skyPlum, .skyLavender],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Circle()
                .strokeBorder(family.accent.opacity(0.9), lineWidth: size * 0.035)
                .padding(size * 0.03)

            Circle()
                .strokeBorder(Color.paper.opacity(0.28), lineWidth: size * 0.008)
                .padding(size * 0.085)

            VStack(spacing: size * 0.035) {
                ShellMedallion(size: size * 0.44)
                    .shadow(color: family.accent.opacity(0.5), radius: size * 0.045)

                markView
                    .frame(height: size * 0.15)
            }
            .offset(y: size * 0.015)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var markView: some View {
        switch mark {
        case .none:
            EmptyView()

        case .numeral(let text):
            Text(text)
                .font(.system(size: size * 0.14, weight: .bold, design: .serif))
                .foregroundStyle(Color.paper)
                .shadow(color: .skyPlum.opacity(0.7), radius: size * 0.012)

        case .pearls(let n):
            HStack(spacing: size * 0.028) {
                ForEach(0..<n, id: \.self) { _ in
                    Pearl(diameter: size * 0.085)
                }
            }

        case .shells(let n):
            HStack(spacing: size * 0.022) {
                ForEach(0..<n, id: \.self) { _ in
                    ShellMedallion(size: size * 0.13)
                }
            }

        case .waves(let n):
            VStack(spacing: size * 0.022) {
                ForEach(0..<n, id: \.self) { i in
                    BadgeWave()
                        .stroke(Color.paper.opacity(0.85), lineWidth: size * 0.016)
                        .frame(width: size * (0.30 - Double(i) * 0.05),
                               height: size * 0.035)
                }
            }
        }
    }
}

/// One sine period. Two or three stacked read as water without needing
/// a literal wave illustration.
struct BadgeWave: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let steps = 40
        for s in 0...steps {
            let t = Double(s) / Double(steps)
            let x = rect.minX + rect.width * t
            let y = rect.midY - sin(t * .pi * 2) * rect.height / 2
            if s == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}

extension Achievement {
    /// The badge for this achievement. Kept next to the ID enum so a
    /// new achievement can't ship without artwork.
    var badge: AchievementBadge {
        switch self {
        case .firstWin:  return AchievementBadge(family: .skill, mark: .pearls(1))
        case .cleanWin:  return AchievementBadge(family: .skill, mark: .waves(1))
        case .hardWin:   return AchievementBadge(family: .skill, mark: .waves(3))
        case .streak5:   return AchievementBadge(family: .skill, mark: .pearls(5))
        case .lastShell: return AchievementBadge(family: .skill, mark: .shells(1))
        case .steal3:    return AchievementBadge(family: .skill, mark: .shells(3))

        case .played10:  return AchievementBadge(family: .milestone, mark: .numeral("10"))
        case .played50:  return AchievementBadge(family: .milestone, mark: .numeral("50"))
        case .played100: return AchievementBadge(family: .milestone, mark: .numeral("100"))
        case .won10:     return AchievementBadge(family: .milestone, mark: .numeral("10 W"))
        case .won50:     return AchievementBadge(family: .milestone, mark: .numeral("50 W"))

        case .bust3:
            return AchievementBadge(family: .silly, mark: .numeral("3"),
                                    shellTop: .coralLight, shellBottom: .coralDark)
        case .squeaker:  return AchievementBadge(family: .silly, mark: .numeral("<10"))
        case .bookends:  return AchievementBadge(family: .silly, mark: .numeral("21·36"))
        }
    }
}

#if DEBUG
/// Writes all fourteen badges to the app's Documents directory as
/// 512x512 PNGs, named by achievement short key so the file matches the
/// row in App Store Connect. DEBUG only — this is a design tool, not a
/// shipped feature. Triggered from the debug menu.
enum AchievementArtExporter {
    @MainActor
    static func exportAll() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("AchievementBadges", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for achievement in Achievement.allCases {
            let url = dir.appendingPathComponent("\(achievement.shortKey).png")
            let renderer = ImageRenderer(content: achievement.badge)
            renderer.scale = 1.0
            guard let image = renderer.uiImage, let cg = image.cgImage else { continue }
            guard let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
            ) else { continue }
            CGImageDestinationAddImage(dest, cg, nil)
            CGImageDestinationFinalize(dest)
        }

        print("[AchievementArt] exported \(Achievement.allCases.count) badges to \(dir.path)")
    }
}
#endif
