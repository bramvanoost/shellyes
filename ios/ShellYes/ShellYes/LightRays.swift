import SwiftUI

/// Soft gold rays radiating from behind a celebration subject (the
/// claim chip in the AI event banner, the winning card on the tally
/// screen). Each ray is a tapered capsule with a gradient that fades
/// at both tips so the rays read as light, not solid spokes. A slow
/// continuous rotation keeps the halo from feeling static during the
/// celebration's dwell time.
///
/// Placed via `.background { LightRays(...) }` on the subject so the
/// inner portions stay hidden behind the subject's body and only the
/// outer ends radiate beyond its silhouette. The frame fixes the
/// rendered size: a sibling inside the subject's own ZStack would
/// instead force the ZStack to expand to the rays' larger frame.
struct LightRays: View {
    var rayCount: Int = 12
    var innerRadius: CGFloat = 8
    var outerRadius: CGFloat = 92
    var rayWidth: CGFloat = 18
    var rotationDuration: Double = 30
    var maxOpacity: Double = 0.65
    /// Set `false` when the surface behind the rays is constant (does
    /// not adapt to dark mode). The dark-mode dampening below assumes a
    /// `Color.paper` card that flips to deep plum — against a constant
    /// cream surface (like the shell-claim banner), the dampening
    /// would just wash the rays out.
    var adaptToColorScheme: Bool = true
    /// Set `false` where there is no time for the halo to arrive or
    /// turn: the share card is rendered by `ImageRenderer`, which
    /// takes one frame and never fires `onAppear`, so animated rays
    /// would come out of it as nothing at all.
    var animates: Bool = true
    /// The light itself. Cream-gold reads as a glow on the darker
    /// surfaces this started on; on a pale sunset sky it disappears,
    /// so the share card asks for the deeper gold instead.
    var color: Color = .coinGoldLight

    @Environment(\.colorScheme) private var colorScheme
    @SwiftUI.State private var visible: Bool = false
    @SwiftUI.State private var rotate: Double = 0

    /// Dark-mode adaptive card surfaces (`Color.paper`) are deep plum,
    /// so the cream-gold rays pop with much higher contrast than they
    /// do against the light-mode cream paper. Dampen the peak gradient
    /// alpha in dark mode so the visual weight roughly matches across
    /// both schemes — without this tuning the device (dark mode) reads
    /// the rays as harsh bars while the simulator (light mode) reads
    /// them as soft glow.
    private var effectiveMaxOpacity: Double {
        guard adaptToColorScheme else { return maxOpacity }
        return colorScheme == .dark ? maxOpacity * 0.55 : maxOpacity
    }

    var body: some View {
        ZStack {
            ForEach(0..<rayCount, id: \.self) { i in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                color.opacity(0.0),
                                color.opacity(effectiveMaxOpacity),
                                color.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: rayWidth, height: outerRadius - innerRadius)
                    .offset(y: -(innerRadius + (outerRadius - innerRadius) / 2))
                    .rotationEffect(.degrees(Double(i) / Double(rayCount) * 360 + rotate))
            }
        }
        .frame(width: outerRadius * 2, height: outerRadius * 2)
        // Slightly stronger blur than the original 0.6: the capsule
        // edges read as crisp bars at iPhone 3x pixel density (the
        // sub-pixel softness that simulator compositing provides
        // doesn't survive on-device), so soften them with a real blur.
        .blur(radius: 1.6)
        .opacity(animates ? (visible ? 1 : 0) : 1)
        .onAppear {
            guard animates else { return }
            withAnimation(.easeOut(duration: 0.55)) {
                visible = true
            }
            withAnimation(.linear(duration: rotationDuration).repeatForever(autoreverses: false)) {
                rotate = 360
            }
        }
    }
}
