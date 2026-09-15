import SwiftUI
import UIKit

// MARK: - Palette (Monument Valley)

extension Color {
    /// Top of sky gradient (light: cream peach, dark: deep plum).
    static let paper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 61/255, green: 46/255, blue: 72/255, alpha: 1)
            : UIColor(red: 251/255, green: 231/255, blue: 208/255, alpha: 1)
    })

    /// All type and borders (light: deep plum, dark: cream).
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 251/255, green: 231/255, blue: 208/255, alpha: 1)
            : UIColor(red: 74/255, green: 55/255, blue: 84/255, alpha: 1)
    })

    /// Secondary text / dim borders (light: soft plum, dark: dusky lavender).
    static let dimInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 168/255, green: 154/255, blue: 184/255, alpha: 1)
            : UIColor(red: 122/255, green: 95/255, blue: 132/255, alpha: 1)
    })

    /// Translucent card surface that adapts to mode. Light mode keeps
    /// the existing white-tinted glass; dark mode goes deep plum so
    /// cream `ink` text has real contrast against the card body
    /// instead of fading into a pale lavender wash.
    static let cardSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 32/255, green: 22/255, blue: 44/255, alpha: 0.78)
            : UIColor(white: 1, alpha: 0.7)
    })

    /// Secondary translucent surface for inset controls (segmented
    /// pickers, toggle tracks). Same adaptation principle as
    /// `cardSurface` but a touch lighter so the inset reads as
    /// "inside" the card rather than the same plane.
    static let insetSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 58/255, green: 42/255, blue: 76/255, alpha: 0.78)
            : UIColor(white: 1, alpha: 0.4)
    })

    /// Coral accent — active seat, action stamp.
    static let coral = Color(red: 210/255, green: 116/255, blue: 116/255)
    /// Brighter coral for highlight on the stamp button (top of the gradient).
    static let coralLight = Color(red: 238/255, green: 158/255, blue: 158/255)

    /// Coral darker — stamp drop shadow.
    static let coralDark = Color(red: 168/255, green: 88/255, blue: 88/255)

    /// Gold pip — coin value markers on safes.
    static let gold = Color(red: 201/255, green: 140/255, blue: 74/255)

    /// Gold for hairline marks — the crown and the palms on a crowned
    /// standing. `gold` is a mid-bronze that solid shapes carry fine,
    /// but the laurels are thin strokes sitting on a pale gold pill,
    /// and in dark mode the pill goes muddy tan and swallows them. So
    /// dark mode draws those marks in the highlight gold instead.
    static let goldMark = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 250/255, green: 219/255, blue: 150/255, alpha: 1)
            : UIColor(red: 201/255, green: 140/255, blue: 74/255, alpha: 1)
    })

    // MARK: - Pearl (golden, pearlescent — not metallic)

    /// Center cream highlight inside the pearl. Bright, diffuse — never a hot spot.
    static let pearlHighlight = Color(red: 254/255, green: 240/255, blue: 200/255)
    /// Mid amber, the pearl's body color.
    static let pearlCore = Color(red: 232/255, green: 192/255, blue: 130/255)
    /// Deeper amber on the pearl's rim.
    static let pearlEdge = Color(red: 196/255, green: 148/255, blue: 88/255)
    /// Outer halo — a soft golden-hour glow surrounding the pearl.
    static let pearlGlow = Color(red: 250/255, green: 220/255, blue: 170/255)

    /// Constant deep plum for text + borders on the peach treasure assets
    /// (safes, dice, vault chips). Doesn't invert in dark mode — these
    /// are physical objects, not chrome.
    static let treasureInk = Color(red: 74/255, green: 55/255, blue: 84/255)

    /// Constant cream for stamp button text on the coral fill.
    /// Doesn't invert — coral is constant, text on it is constant too.
    static let stampText = Color(red: 251/255, green: 231/255, blue: 208/255)

    /// Safe tile gradient stops (peach).
    static let safePeachLight = Color(red: 253/255, green: 233/255, blue: 208/255)
    static let safePeachDark = Color(red: 243/255, green: 214/255, blue: 184/255)

    /// Coin die face gradient stops (gold).
    static let coinGoldLight = Color(red: 250/255, green: 219/255, blue: 150/255)
    static let coinGoldDark = Color(red: 240/255, green: 201/255, blue: 122/255)

    /// Pale cream-gold for the lit edge of a shell sitting in relief on the
    /// coin. Brighter than coinGoldLight so the shell catches the highlight
    /// instead of blending into the coin face.
    static let shellHighlight = Color(red: 254/255, green: 240/255, blue: 196/255)

    // MARK: - Sky gradient stops

    /// Top of the golden-hour sky. Decoupled from `paper` so the upper
    /// edge can be a deeper apricot instead of washing out to cream.
    static let skyTop = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 50/255, green: 38/255, blue: 62/255, alpha: 1)
            : UIColor(red: 235/255, green: 198/255, blue: 165/255, alpha: 1)
    })

    static let skyMid = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 90/255, green: 69/255, blue: 113/255, alpha: 1)
            : UIColor(red: 245/255, green: 205/255, blue: 160/255, alpha: 1)
    })

    static let skyLavender = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 138/255, green: 106/255, blue: 138/255, alpha: 1)
            : UIColor(red: 210/255, green: 182/255, blue: 208/255, alpha: 1)
    })

    static let skyPlum = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 168/255, green: 154/255, blue: 184/255, alpha: 1)
            : UIColor(red: 165/255, green: 148/255, blue: 184/255, alpha: 1)
    })

    // MARK: - Architectural silhouette

    static let citySilhouette = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 50/255, green: 38/255, blue: 60/255, alpha: 0.85)
            : UIColor(red: 139/255, green: 100/255, blue: 136/255, alpha: 0.7)
    })

    static let citySilhouetteAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 70/255, green: 53/255, blue: 84/255, alpha: 0.85)
            : UIColor(red: 168/255, green: 128/255, blue: 165/255, alpha: 0.7)
    })

    // MARK: - Moon

    static let moonGlow = Color(red: 245/255, green: 212/255, blue: 155/255)
    static let moonCenter = Color(red: 255/255, green: 248/255, blue: 232/255)

    // MARK: - Turn-note tones (banner card backgrounds)

    /// Soft sea-foam green — used as the card fill on banners that read
    /// as "good for you" (you claimed a shell, a rival went bust).
    static let bannerPositive = Color(red: 196/255, green: 222/255, blue: 200/255)
    /// Deeper sage accent for the positive banner stroke.
    static let bannerPositiveAccent = Color(red: 96/255, green: 138/255, blue: 105/255)

    /// Muted rose — card fill on banners that hurt you (a rival took
    /// your shell). Distinct from coral so it reads as "bad news," not
    /// just another action stamp.
    static let bannerNegative = Color(red: 226/255, green: 165/255, blue: 165/255)
    /// Deeper crimson accent for the negative banner stroke.
    static let bannerNegativeAccent = Color(red: 162/255, green: 65/255, blue: 65/255)
}

// MARK: - Typography (Avenir Next, single-family)

enum AvenirWeight {
    case ultraLight, regular, medium, demiBold, bold

    func postScriptName(italic: Bool) -> String {
        switch (self, italic) {
        case (.ultraLight, false): return "AvenirNext-UltraLight"
        case (.ultraLight, true):  return "AvenirNext-UltraLightItalic"
        case (.regular, false):    return "AvenirNext-Regular"
        case (.regular, true):     return "AvenirNext-Italic"
        case (.medium, false):     return "AvenirNext-Medium"
        case (.medium, true):      return "AvenirNext-MediumItalic"
        case (.demiBold, false):   return "AvenirNext-DemiBold"
        case (.demiBold, true):    return "AvenirNext-DemiBoldItalic"
        case (.bold, false):       return "AvenirNext-Bold"
        case (.bold, true):        return "AvenirNext-BoldItalic"
        }
    }
}

extension Font {
    static func avenir(_ size: CGFloat, weight: AvenirWeight = .regular, italic: Bool = false) -> Font {
        .custom(weight.postScriptName(italic: italic), size: size)
    }

    // Legacy Phase 4 font helpers — redirected to Avenir so the existing code
    // builds against the MV typography while we migrate component-by-component.
    static func cochin(_ size: CGFloat) -> Font { .avenir(size, weight: .regular) }
    static func cochinItalic(_ size: CGFloat) -> Font { .avenir(size, weight: .medium, italic: true) }
    static func bodoni(_ size: CGFloat) -> Font { .avenir(size, weight: .demiBold) }
    static func bodoniItalic(_ size: CGFloat) -> Font { .avenir(size, weight: .demiBold, italic: true) }
}

// MARK: - PearlRow
//
// A row of golden pearls (the points-token sitting on a shell). Pearlescent,
// not metallic: warm amber body, diffuse cream highlight, soft outer halo. The
// glow is what carries the reward feeling, so the surface stays calm.

struct PearlRow: View {
    let count: Int
    var diameter: CGFloat = 5
    var spacing: CGFloat = 2

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<max(0, count), id: \.self) { _ in
                Pearl(diameter: diameter)
            }
        }
    }
}

struct Pearl: View {
    var diameter: CGFloat = 5
    var highlight: Color = .pearlHighlight
    var core: Color = .pearlCore
    var edge: Color = .pearlEdge
    var glow: Color = .pearlGlow

    var body: some View {
        ZStack {
            // Soft outer halo — golden-hour glow, never sharp.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [glow.opacity(0.55), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter
                    )
                )
                .frame(width: diameter * 1.9, height: diameter * 1.9)
                .blendMode(.plusLighter)

            // Pearl body — cream center diffusing into deeper amber on the rim.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [highlight, core, edge],
                        center: UnitPoint(x: 0.35, y: 0.32),
                        startRadius: 0,
                        endRadius: diameter / 2
                    )
                )
                .frame(width: diameter, height: diameter)
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - ShellCardShape
//
// The claimed-shell silhouette: scalloped crown across the top, straight
// parallel sides (REQUIRED for clean vertical stacking — see CLAUDE.md), and
// a small centered umbo nub at the bottom edge.

// MARK: - Wave line (countdown indicator on bust screen)

/// A continuous sine wave drawn across the host's width. Wavelength is
/// fixed (12pt by default), so as the host frame shrinks during a
/// countdown the visible wave count decreases — the same "draining"
/// read as a capsule, but feels like the tide pulling back.
struct WaveLine: Shape {
    var wavelength: CGFloat = 12
    var amplitude: CGFloat = 2.5
    var phase: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0 else { return path }
        let midY = rect.midY
        let steps = max(2, Int(rect.width))
        for i in 0...steps {
            let x = rect.width * CGFloat(i) / CGFloat(steps)
            let y = midY + amplitude * sin(2 * .pi * x / wavelength + phase)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

struct ShellCardShape: InsettableShape {
    var crownWaves: Int = 3
    var crownRatio: CGFloat = 0.07
    var bellyRatio: CGFloat = 0.09
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var p = Path()
        let crownH = r.height * crownRatio
        let bellyH = r.height * bellyRatio
        let bodyTop = r.minY + crownH
        let bodyBottom = r.maxY - bellyH

        p.move(to: CGPoint(x: r.minX, y: bodyTop))

        // Crown: N soft sinusoidal waves. Cubic bezier with horizontally-
        // spread symmetric controls gives rounded peaks (not parabolic
        // points), and a control y pushed slightly past minY lands the
        // visible apex right at the frame top.
        let waveW = r.width / CGFloat(crownWaves)
        let controlApexY = r.minY - crownH * (1.0 / 0.75 - 1.0)
        for i in 0..<crownWaves {
            let x0 = r.minX + CGFloat(i) * waveW
            let x1 = r.minX + CGFloat(i + 1) * waveW
            let c1 = CGPoint(x: x0 + waveW * 0.25, y: controlApexY)
            let c2 = CGPoint(x: x0 + waveW * 0.75, y: controlApexY)
            p.addCurve(
                to: CGPoint(x: x1, y: bodyTop),
                control1: c1,
                control2: c2
            )
        }

        // Right side: straight & parallel (REQUIRED for clean vertical
        // stacking — see CLAUDE.md).
        p.addLine(to: CGPoint(x: r.maxX, y: bodyBottom))

        // Bottom: one gentle bulge across the whole width (no protruding
        // nub). Quad control at 2× bellyH past bodyBottom so the apex
        // touches the frame's bottom edge.
        p.addQuadCurve(
            to: CGPoint(x: r.minX, y: bodyBottom),
            control: CGPoint(x: r.midX, y: bodyBottom + bellyH * 2)
        )

        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var s = self
        s.insetAmount += amount
        return s
    }
}

// MARK: - Stamp button (MV coral pill)

struct StampButtonStyle: ButtonStyle {
    var primary: Bool = true
    var invite: Bool = false
    /// When false the breathing halo is suppressed; only the shine band
    /// drifts across the face. Used on the in-game Roll On so the
    /// button has a quiet "you're up" cue without the come-hither halo.
    var inviteHalo: Bool = true

    @SwiftUI.State private var glowPulse: Bool = false
    @SwiftUI.State private var shineSwept: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.avenir(16, weight: .demiBold))
            .textCase(.uppercase)
            .tracking(3)
            .foregroundStyle(primary ? Color.stampText : Color.coral)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            primary
                                ? LinearGradient(
                                    colors: [Color.coinGoldLight, Color.coralLight, Color.coral, Color.coralDark],
                                    startPoint: .top,
                                    endPoint: .bottom
                                  )
                                : LinearGradient(
                                    colors: [Color.stampText, Color.stampText.opacity(0.88)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                  )
                        )
                        .overlay(
                            // Secondary buttons still get the coral
                            // outline since their face is cream and they
                            // need a clear edge. Primary buttons are
                            // border-less — the gradient itself defines
                            // the shape, no top "bar" effect.
                            primary
                                ? AnyView(EmptyView())
                                : AnyView(
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(Color.coral, lineWidth: 1.5)
                                )
                        )
                        // Soft white shine — a faint warm-light sweep that
                        // drifts across the face when invite is on. Half
                        // the opacity of the original so it reads as light,
                        // not as a stripe. Masked to the rounded corners.
                        .overlay {
                            if invite {
                                GeometryReader { geo in
                                    let bandWidth: CGFloat = 280
                                    Rectangle()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    .clear,
                                                    Color.white.opacity(0.18),
                                                    .clear
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: bandWidth, height: geo.size.height * 1.5)
                                        .rotationEffect(.degrees(10))
                                        .offset(x: shineSwept
                                                ? geo.size.width / 2 + bandWidth
                                                : -geo.size.width / 2 - bandWidth)
                                        .blendMode(.softLight)
                                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                                }
                                .mask(RoundedRectangle(cornerRadius: 14))
                                .allowsHitTesting(false)
                            }
                        }
                }
                // Hard-offset rim (echoes the tile depth recipe)
                .shadow(color: Color.coralDark.opacity(0.45), radius: 0, x: 0, y: 3)
                // Soft drop
                .shadow(color: Color.coralDark.opacity(0.3), radius: 10, x: 0, y: 7)
                // Invite halo — a warm gold glow that breathes when the
                // button is the come-hither moment (New Game on splash,
                // Play Again at the end of a game). Replaces the previous
                // shine-stripe animation, which read as a "bar" passing
                // across the face. The halo never crosses the face, so
                // there's no stripe artifact.
                .shadow(
                    color: (invite && inviteHalo) ? Color.coinGoldLight.opacity(glowPulse ? 0.88 : 0.22) : .clear,
                    radius: 28,
                    x: 0, y: 0
                )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.94 : 1.0)
            .task(id: invite) {
                guard invite else { return }
                // Kick the first beat off without any easing-in pause —
                // halo and shine both start animating on frame zero so
                // the button feels alive the instant it appears.
                while !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 1.1)) {
                        glowPulse = true
                    }
                    withAnimation(.easeInOut(duration: 2.0)) {
                        shineSwept = true
                    }
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    withAnimation(.easeInOut(duration: 1.1)) {
                        glowPulse = false
                    }
                    shineSwept = false
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
            }
    }
}

extension View {
    func stampButton(primary: Bool = true, invite: Bool = false, inviteHalo: Bool = true) -> some View {
        self.buttonStyle(StampButtonStyle(primary: primary, invite: invite, inviteHalo: inviteHalo))
    }
}

// MARK: - Tiny shadow modifier (legacy, soft now)

struct StampShadowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: Color.ink.opacity(0.22), radius: 0, x: 0, y: 3)
    }
}

extension View {
    func stampShadow() -> some View {
        modifier(StampShadowModifier())
    }
}
