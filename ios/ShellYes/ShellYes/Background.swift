import SwiftUI

/// Golden-hour Balearic backdrop. Sky gradient + distant headland, sea band,
/// dune, and a couple of palm silhouettes. Used by every screen so all the
/// foreground chrome floats on the same atmosphere.
struct Background: View {
    /// Set by `PhoneCanvas`. Inside one the canvas has already drawn
    /// this beach at window shape, underneath the whole screen, so a
    /// screen drawing its own would only put a phone-shaped scene
    /// inside an iPad-shaped one.
    @Environment(\.phoneCanvas) private var canvas

    /// How much of the bottom edge the beach occupies. The default is
    /// the phone screen's, where the scene has a whole display to sit
    /// in; a small fixed canvas like the share card needs the horizon
    /// pushed further down or the dune climbs into the type.
    var groundInset: CGFloat = 130

    var body: some View {
        if canvas != nil {
            Color.clear
        } else {
            scene
        }
    }

    private var scene: some View {
        ZStack {
            // Sky gradient
            LinearGradient(
                stops: [
                    .init(color: .skyTop, location: 0.0),
                    .init(color: .skyMid, location: 0.35),
                    .init(color: .skyLavender, location: 0.70),
                    .init(color: .skyPlum, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Distant beach silhouette anchored near the bottom edge so the
            // top 2/3 of the screen stays clear for UI.
            GeometryReader { geo in
                BeachScene(horizonY: geo.size.height - groundInset)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black, location: 0.55),
                                .init(color: .black, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

/// Layered beach: far headland on the horizon, narrow sea band, lonely
/// sailboat, foreground dune with two palm silhouettes planted in it.
private struct BeachScene: View {
    let horizonY: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let groundHeight = max(h - horizonY, 130)

            ZStack(alignment: .topLeading) {
                // Far headland — distant rolling hills hugging the horizon.
                FarHeadland(width: w)
                    .opacity(0.38)
                    .offset(y: horizonY - 18)

                // Sea band — thin cooler strip below the horizon.
                SeaBand(width: w)
                    .offset(y: horizonY)

                // Sailboat — tiny lateen sail catching the last light.
                Sailboat()
                    .opacity(0.55)
                    .offset(x: w * 0.62, y: horizonY - 11)

                // Dune — wavy foreground hill filling everything below
                // the horizon line.
                Dune(width: w, height: groundHeight)
                    .offset(y: horizonY)

                // Foreground palms — taller one leans gently inland on
                // the left, smaller cousin on the right.
                Palm(height: 110, leanDegrees: -8)
                    .frame(width: 140, height: 110)
                    .offset(x: w * 0.16 - 70, y: horizonY - 66)

                Palm(height: 84, leanDegrees: 10)
                    .frame(width: 116, height: 84)
                    .offset(x: w * 0.76 - 58, y: horizonY - 46)
            }
        }
    }
}

/// Far headland: low rolling silhouette right on the horizon line.
private struct FarHeadland: View {
    let width: CGFloat

    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 18))
            p.addCurve(
                to: CGPoint(x: width * 0.32, y: 4),
                control1: CGPoint(x: width * 0.10, y: 16),
                control2: CGPoint(x: width * 0.22, y: 2)
            )
            p.addCurve(
                to: CGPoint(x: width * 0.68, y: 9),
                control1: CGPoint(x: width * 0.46, y: 10),
                control2: CGPoint(x: width * 0.58, y: 16)
            )
            p.addCurve(
                to: CGPoint(x: width, y: 14),
                control1: CGPoint(x: width * 0.82, y: 2),
                control2: CGPoint(x: width * 0.92, y: 8)
            )
            p.addLine(to: CGPoint(x: width, y: 22))
            p.addLine(to: CGPoint(x: 0, y: 22))
            p.closeSubpath()
        }
        .fill(Color.citySilhouette)
        .frame(height: 22)
    }
}

/// Sea band: ~8pt strip where the water meets the shore. Slight cool wash
/// over the sky color so it reads as water, not a stripe.
private struct SeaBand: View {
    let width: CGFloat

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.skyLavender.opacity(0.55),
                        Color.skyMid.opacity(0.25)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: width, height: 8)
    }
}

/// Tiny lateen sailboat triangle on the horizon.
private struct Sailboat: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 4, y: 0))
            p.addLine(to: CGPoint(x: 4, y: 11))
            p.addLine(to: CGPoint(x: 0, y: 11))
            p.closeSubpath()
            p.move(to: CGPoint(x: 4.6, y: 1))
            p.addLine(to: CGPoint(x: 9, y: 11))
            p.addLine(to: CGPoint(x: 4.6, y: 11))
            p.closeSubpath()
        }
        .fill(Color.citySilhouette)
        .frame(width: 9, height: 12)
    }
}

/// Dune: wavy foreground hill from horizon to bottom edge. Subtle gradient
/// fade from crest to base so the foreground doesn't read as a flat slab.
private struct Dune: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 28))
                p.addCurve(
                    to: CGPoint(x: width * 0.42, y: 6),
                    control1: CGPoint(x: width * 0.14, y: 20),
                    control2: CGPoint(x: width * 0.28, y: 2)
                )
                p.addCurve(
                    to: CGPoint(x: width, y: 34),
                    control1: CGPoint(x: width * 0.62, y: 12),
                    control2: CGPoint(x: width * 0.82, y: 44)
                )
                p.addLine(to: CGPoint(x: width, y: height))
                p.addLine(to: CGPoint(x: 0, y: height))
                p.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [
                        Color.citySilhouette.opacity(0.72),
                        Color.citySilhouette.opacity(0.5)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Lit crest accent — a thin warm line along the top of the dune,
            // catching the last of the sun.
            Path { p in
                p.move(to: CGPoint(x: 0, y: 28))
                p.addCurve(
                    to: CGPoint(x: width * 0.42, y: 6),
                    control1: CGPoint(x: width * 0.14, y: 20),
                    control2: CGPoint(x: width * 0.28, y: 2)
                )
                p.addCurve(
                    to: CGPoint(x: width, y: 34),
                    control1: CGPoint(x: width * 0.62, y: 12),
                    control2: CGPoint(x: width * 0.82, y: 44)
                )
            }
            .stroke(Color.citySilhouetteAccent.opacity(0.7), lineWidth: 1.2)
        }
    }
}

/// Procedural palm silhouette: gently curved trunk + seven drooping fronds
/// radiating from the crown. `leanDegrees` tilts the whole tree at the base
/// so the two palms in the scene have different attitudes.
private struct Palm: View {
    var height: CGFloat
    var leanDegrees: Double = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let trunkBaseX = w * 0.5
            let trunkBaseY = h
            let crownY = h * 0.36
            let crownX = trunkBaseX + sin(leanDegrees * .pi / 180) * (h - crownY) * 0.6

            let trunkWidthBase = max(3.5, height / 26)
            let trunkWidthTop = max(2.0, height / 44)

            ZStack {
                // Trunk — slightly curved, narrows toward the crown.
                Path { p in
                    p.move(to: CGPoint(x: trunkBaseX - trunkWidthBase, y: trunkBaseY))
                    p.addQuadCurve(
                        to: CGPoint(x: crownX - trunkWidthTop, y: crownY),
                        control: CGPoint(
                            x: (trunkBaseX + crownX) / 2 - trunkWidthBase * 1.6,
                            y: (trunkBaseY + crownY) / 2
                        )
                    )
                    p.addLine(to: CGPoint(x: crownX + trunkWidthTop, y: crownY))
                    p.addQuadCurve(
                        to: CGPoint(x: trunkBaseX + trunkWidthBase, y: trunkBaseY),
                        control: CGPoint(
                            x: (trunkBaseX + crownX) / 2 + trunkWidthBase * 0.4,
                            y: (trunkBaseY + crownY) / 2
                        )
                    )
                    p.closeSubpath()
                }
                .fill(Color.citySilhouette)

                // Fronds — seven leaves sweeping out from the crown, each
                // drooping at the tip.
                ForEach(0..<frondAngles.count, id: \.self) { i in
                    frond(
                        crownX: crownX,
                        crownY: crownY,
                        angle: frondAngles[i],
                        length: frondLengths[i] * (height / 110)
                    )
                }

                // Crown dot — tightens the trunk-to-fronds junction.
                Circle()
                    .fill(Color.citySilhouette)
                    .frame(width: trunkWidthTop * 3, height: trunkWidthTop * 3)
                    .position(x: crownX, y: crownY)
            }
        }
    }

    // Six fat fronds fanning across the upper hemisphere only — chunky
    // enough to read as a palm crown even at distance.
    private let frondAngles: [Double] = [-160, -125, -90, -55, -20, 15]
    private let frondLengths: [CGFloat] = [40, 48, 52, 50, 44, 38]

    private func frond(crownX: CGFloat, crownY: CGFloat, angle: Double, length: CGFloat) -> some View {
        let rad = angle * .pi / 180
        let straightTipX = crownX + cos(rad) * length
        let straightTipY = crownY + sin(rad) * length

        // Side-pointing fronds droop more; near-vertical fronds barely droop.
        let horizontality = abs(cos(rad))
        let droop = length * 0.32 * horizontality + 4
        let tipX = straightTipX
        let tipY = straightTipY + droop

        return Path { p in
            // Wide tapered leaf: 10pt at the base, point at the tip. The
            // belly bulges downward so the silhouette reads as a hanging
            // frond rather than a rigid spike.
            let baseWidth: CGFloat = 10
            let perpX = -sin(rad) * baseWidth / 2
            let perpY = cos(rad) * baseWidth / 2

            p.move(to: CGPoint(x: crownX - perpX, y: crownY - perpY))
            p.addQuadCurve(
                to: CGPoint(x: tipX, y: tipY),
                control: CGPoint(
                    x: (crownX + tipX) / 2 - perpX * 0.3,
                    y: (crownY + tipY) / 2 - perpY * 0.3 + droop * 0.6
                )
            )
            p.addQuadCurve(
                to: CGPoint(x: crownX + perpX, y: crownY + perpY),
                control: CGPoint(
                    x: (crownX + tipX) / 2 + perpX * 0.3,
                    y: (crownY + tipY) / 2 + perpY * 0.3 + droop
                )
            )
            p.closeSubpath()
        }
        .fill(Color.citySilhouette)
    }
}

#Preview {
    Background()
}
