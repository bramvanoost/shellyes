import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// The twenty achievement badges, drawn from the app's own palette
/// and the brand shell rather than a separate art file. Same trick as
/// `IconExporter`: the artwork IS SwiftUI, and a DEBUG-only export
/// turns it into the 512x512 PNGs App Store Connect wants.
///
/// Game Center crops achievement art to a circle in most of its
/// surfaces, so every badge is designed circle-first and the square is
/// just the canvas it sits on.
///
/// Three dials separate them, because one was not enough: the first
/// pass varied only the ring colour and the grid read as the same coin
/// printed fourteen times. Now the ring names the family, the disc
/// ground shifts per badge, and the mark — not the shell — is the hero.

/// The three families. The ring colour is the coarsest of the three
/// dials: it groups, it does not identify.
enum BadgeFamily {
    case skill      // how you played
    case milestone  // time served
    case silly      // on-brand nonsense
    case week       // what you did with the seven days

    var accent: Color {
        switch self {
        case .skill: return .coinGoldLight
        // Lifted well clear of the plum ground; a flat lavender sank
        // into it and the family stopped reading.
        case .milestone: return Color(red: 214/255, green: 200/255, blue: 236/255)
        case .silly: return .coralLight
        // Sea green, the one direction the other three do not already
        // occupy. The weekly family is about the water going out and
        // coming back, and it has to be told apart from gold at the
        // size Game Center draws a grid.
        case .week: return Color(red: 138/255, green: 218/255, blue: 205/255)
        }
    }
}

/// Which pearls sit in the brand shell. Coral marks the silly family
/// from the centre outwards, so it reads even where the rim is cropped.
enum BadgePearls {
    case gold
    case coral
}

/// Marks follow one rule: the skill and silly families speak in the
/// game's own objects (pearls, shells, water), and the counting family
/// speaks in numerals, because a number is what it is about.
enum BadgeMark {
    case none
    /// A count of games played. Numeral alone.
    case numeral(String)
    /// A count of games won. Numeral with a shell either side, so wins
    /// never read as plays at grid size.
    case flankedNumeral(String)
    case pearls(Int)
    /// Busting: the same pearls, off their line, one dropped low.
    case scatteredPearls(Int)
    case shells(Int)
    /// Barely won. One undersized shell, adrift and low in the disc.
    case adriftShell
    /// Shell 21 and shell 36: two shells hugging opposite rims.
    case bookends
    case waves(Int)
    /// A held rank. The same crown the splash, the board and the stats
    /// pane already use, so a badge for leading a board is recognisably
    /// the thing the player has been looking at all along.
    case crowns(Int)
    /// The all-time crown, flanked by the palms the splash calls
    /// laurels. Reserved for Big Kahuna, in both places.
    case crownedLaurels
}

struct AchievementBadge: View {
    var family: BadgeFamily
    var mark: BadgeMark = .none
    var pearls: BadgePearls = .gold
    /// Position in this family's ground ramp, 0 lightest to 1 deepest.
    /// Deliberately explicit per badge rather than derived from the
    /// enum order, so reordering `Achievement` cannot silently reshuffle
    /// the art of already-published badges.
    var groundStep: Double = 0.5
    var size: CGFloat = 512

    var body: some View {
        ZStack {
            Circle()
                .fill(BadgeGround.gradient(step: groundStep))

            Circle()
                .strokeBorder(family.accent.opacity(0.9), lineWidth: size * 0.035)
                .padding(size * 0.03)

            Circle()
                .strokeBorder(Color.paper.opacity(0.28), lineWidth: size * 0.008)
                .padding(size * 0.085)

            VStack(spacing: size * 0.03) {
                ShellMedallion(
                    size: size * 0.32,
                    pearlHighlight: pearls == .coral ? .coralLight : .pearlHighlight,
                    pearlCore: pearls == .coral ? .coral : .pearlCore,
                    pearlEdge: pearls == .coral ? .coralDark : .pearlEdge,
                    pearlGlow: pearls == .coral ? .coralLight : .pearlGlow
                )
                .shadow(color: family.accent.opacity(0.5), radius: size * 0.04)

                // Fixed width as well as height: `bookends` needs to
                // spread to the rim, and every other mark centres
                // inside the same box, so the marks share a baseline.
                markView
                    .frame(width: size * 0.74, height: size * 0.26)
            }
            .offset(y: size * 0.01)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var markView: some View {
        switch mark {
        case .none:
            EmptyView()

        case .numeral(let text):
            numeralText(text, fontScale: text.count > 2 ? 0.185 : 0.22)

        case .flankedNumeral(let text):
            HStack(spacing: size * 0.035) {
                ShellMedallion(size: size * 0.105)
                numeralText(text, fontScale: 0.19)
                ShellMedallion(size: size * 0.105)
            }

        case .pearls(let n):
            // Lonely marks get drawn bigger. A row of five needs small
            // pearls to fit; one pearl at that size is a speck in a
            // Game Center grid.
            HStack(spacing: size * 0.03) {
                ForEach(0..<n, id: \.self) { _ in
                    Pearl(diameter: size * (n == 1 ? 0.165 : 0.105))
                }
            }

        case .scatteredPearls(let n):
            // Hand-placed rather than computed: the point is that the
            // row broke, and an even scatter still reads as a row.
            let drift: [CGSize] = [
                CGSize(width: -0.085, height: -0.035),
                CGSize(width: 0.005, height: 0.02),
                CGSize(width: 0.095, height: 0.075),
            ]
            ZStack {
                ForEach(0..<n, id: \.self) { i in
                    Pearl(
                        diameter: size * 0.105,
                        highlight: .coralLight,
                        core: .coral,
                        edge: .coralDark,
                        glow: .coralLight
                    )
                    .offset(
                        x: size * drift[i % drift.count].width,
                        y: size * drift[i % drift.count].height
                    )
                }
            }

        case .shells(let n):
            HStack(spacing: size * 0.025) {
                ForEach(0..<n, id: \.self) { _ in
                    ShellMedallion(size: size * (n == 1 ? 0.23 : 0.155))
                }
            }

        case .adriftShell:
            // Deliberately half the size of `shells(1)`: the joke is
            // that the win barely happened. Big enough to survive the
            // grid, small enough to read as undersized next to it.
            ShellMedallion(size: size * 0.125)
                .offset(y: size * 0.05)

        case .bookends:
            HStack(spacing: 0) {
                ShellMedallion(size: size * 0.16)
                Spacer(minLength: 0)
                ShellMedallion(size: size * 0.16)
            }

        case .crowns(let n):
            // A crown glyph is wider than its point size, so five of
            // them at the size three would take run past the mark frame
            // and into the ring — and Game Center crops to a circle, so
            // the outer two lose their heads. Sized down as the row
            // grows, not by a constant.
            let crownSize = size * (n == 1 ? 0.2 : n <= 3 ? 0.1 : 0.068)
            HStack(spacing: size * (n > 3 ? 0.018 : 0.03)) {
                ForEach(0..<n, id: \.self) { _ in
                    Image(systemName: "crown.fill")
                        .font(.system(size: crownSize, weight: .medium))
                        .foregroundStyle(Color.paper)
                }
            }

        case .crownedLaurels:
            // Semibold, like the splash: a stroked frond has to hold
            // its own beside a filled crown or it reads as smudge.
            HStack(spacing: size * 0.02) {
                Image(systemName: "laurel.leading")
                    .font(.system(size: size * 0.17, weight: .semibold))
                Image(systemName: "crown.fill")
                    .font(.system(size: size * 0.18, weight: .medium))
                Image(systemName: "laurel.trailing")
                    .font(.system(size: size * 0.17, weight: .semibold))
            }
            .foregroundStyle(Color.paper)

        case .waves(let n):
            VStack(spacing: size * 0.03) {
                ForEach(0..<n, id: \.self) { i in
                    BadgeWave()
                        .stroke(
                            Color.paper.opacity(0.9),
                            style: StrokeStyle(
                                lineWidth: size * (n == 1 ? 0.028 : 0.02),
                                lineCap: .round
                            )
                        )
                        // One wave reads as calm water, three as rough:
                        // the stack narrows and steepens as it grows.
                        .frame(width: size * (n == 1 ? 0.40 : 0.34 - Double(i) * 0.05),
                               height: size * (n == 1 ? 0.05 : 0.045))
                }
            }
        }
    }

    private func numeralText(_ text: String, fontScale: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size * fontScale, weight: .bold, design: .serif))
            .foregroundStyle(Color.paper)
            .shadow(color: BadgeGround.deep.opacity(0.7), radius: size * 0.012)
    }
}

/// The disc ground. Explicit RGB rather than the app's dynamic
/// `skyPlum` / `skyLavender`, because these render to PNG once and must
/// not depend on whichever appearance the exporting simulator is in.
enum BadgeGround {
    static let deep = Color(red: 112/255, green: 96/255, blue: 140/255)

    private static let topLight = (r: 224.0, g: 203.0, b: 228.0)
    private static let topDeep = (r: 150.0, g: 132.0, b: 172.0)
    private static let bottomLight = (r: 186.0, g: 166.0, b: 204.0)
    private static let bottomDeep = (r: 112.0, g: 96.0, b: 140.0)

    /// `step` 0 is the lightest ground, 1 the deepest. The gradient also
    /// swings a few degrees across the ramp, so neighbouring badges
    /// differ in the direction of the light as well as its depth.
    static func gradient(step: Double) -> LinearGradient {
        let t = min(max(step, 0), 1)
        let swing = (t - 0.5) * 0.22
        return LinearGradient(
            colors: [mix(topLight, topDeep, t), mix(bottomLight, bottomDeep, t)],
            startPoint: UnitPoint(x: 0.5 - swing, y: 0),
            endPoint: UnitPoint(x: 0.5 + swing, y: 1)
        )
    }

    private static func mix(
        _ a: (r: Double, g: Double, b: Double),
        _ b: (r: Double, g: Double, b: Double),
        _ t: Double
    ) -> Color {
        Color(
            red: (a.r + (b.r - a.r) * t) / 255,
            green: (a.g + (b.g - a.g) * t) / 255,
            blue: (a.b + (b.b - a.b) * t) / 255
        )
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
        case .firstWin:
            return AchievementBadge(family: .skill, mark: .pearls(1), groundStep: 0.0)
        case .cleanWin:
            return AchievementBadge(family: .skill, mark: .waves(1), groundStep: 0.2)
        case .hardWin:
            return AchievementBadge(family: .skill, mark: .waves(3), groundStep: 1.0)
        case .streak5:
            return AchievementBadge(family: .skill, mark: .pearls(5), groundStep: 0.6)
        case .lastShell:
            return AchievementBadge(family: .skill, mark: .shells(1), groundStep: 0.35)
        case .steal3:
            return AchievementBadge(family: .skill, mark: .shells(3), groundStep: 0.8)

        // The counting family's ground deepens with the count, so the
        // ramp itself says "further along" before the numeral is read.
        case .played10:
            return AchievementBadge(family: .milestone, mark: .numeral("10"), groundStep: 0.0)
        case .played50:
            return AchievementBadge(family: .milestone, mark: .numeral("50"), groundStep: 0.45)
        case .played100:
            return AchievementBadge(family: .milestone, mark: .numeral("100"), groundStep: 0.9)
        case .won10:
            return AchievementBadge(family: .milestone, mark: .flankedNumeral("10"), groundStep: 0.25)
        case .won50:
            return AchievementBadge(family: .milestone, mark: .flankedNumeral("50"), groundStep: 0.7)

        case .bust3:
            return AchievementBadge(
                family: .silly, mark: .scatteredPearls(3), pearls: .coral, groundStep: 0.55
            )
        case .squeaker:
            return AchievementBadge(family: .silly, mark: .adriftShell, groundStep: 0.1)
        case .bookends:
            return AchievementBadge(family: .silly, mark: .bookends, groundStep: 0.85)

        // The week. Its three local badges speak in pearls and water
        // like the skill family, because they are about what you did;
        // its three rank badges speak in crowns, because they are about
        // where you stand and the crown already means that everywhere
        // else in the app.
        case .weekSweep:
            return AchievementBadge(family: .week, mark: .pearls(5), groundStep: 0.3)
        case .weekBestOfThree:
            return AchievementBadge(family: .week, mark: .pearls(3), groundStep: 0.05)
        case .weekBetter:
            return AchievementBadge(family: .week, mark: .waves(2), groundStep: 0.5)
        case .topBanana:
            return AchievementBadge(family: .week, mark: .crowns(1), groundStep: 0.65)
        case .wholeBeach:
            return AchievementBadge(family: .week, mark: .crowns(5), groundStep: 0.85)
        case .bigKahuna:
            return AchievementBadge(family: .week, mark: .crownedLaurels, groundStep: 1.0)
        }
    }
}

#if DEBUG
/// Writes all twenty badges to the app's Documents directory as
/// 512x512 PNGs, named by achievement short key so the file matches the
/// row in App Store Connect. DEBUG only — this is a design tool, not a
/// shipped feature. Triggered from the debug menu.
enum AchievementArtExporter {
    /// Same trick as `ScreenshotMode`: the ladybug menu lives on the
    /// game screen, so exporting by hand means starting a game first.
    /// This makes a fresh export one `simctl launch` away.
    static var isRequestedByLaunchArgument: Bool {
        ProcessInfo.processInfo.arguments.contains("-exportAchievementBadges")
    }

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
