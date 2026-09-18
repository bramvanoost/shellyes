import SwiftUI
import UIKit

/// Every screen in this app is drawn for a phone. Roughly eighty call
/// sites hardcode a width, a height or a padding against a 393x852
/// canvas, and the game screen's root `VStack` has a floor it cannot
/// compress below: give it less height than it wants and it overflows
/// its `ZStack`, which then centres itself in the window and clips the
/// chrome bar off the top and the ROLL button off the bottom. That is
/// exactly what iPad showed in compatibility mode.
///
/// So iPad keeps the phone canvas rather than learning size classes.
/// The canvas is laid out at its design size, scaled to fit whatever
/// window it has been given (aspect-fit, so nothing distorts) and
/// centred over a full-bleed `Background`, so the letterbox is beach
/// rather than black. A big canvas simply makes the game bigger, which
/// is what a tablet is for.
///
/// Phones are left completely alone — same frames, same screenshots.
/// The scaling exists to serve a canvas the layout was never designed
/// for, and the phone is the one it was.
struct PhoneCanvas<Content: View>: View {
    /// iPhone 16 Pro logical points. Everything hardcoded in the app
    /// was measured against this.
    private static var designSize: CGSize { CGSize(width: 393, height: 852) }

    @ViewBuilder var content: Content

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            GeometryReader { geo in
                let design = Self.designSize
                // The safe area is consumed here, by the canvas, rather
                // than left for the screens inside it. Leave it to them
                // and every `Background` in the app expands past the
                // canvas it was framed to — its gradient laid out over a
                // box 44pt taller than the one you see — and the sky
                // inside the canvas comes out a different colour from
                // the sky beside it, with two hard vertical edges where
                // they meet.
                let insets = geo.safeAreaInsets
                let safe = CGSize(
                    width: geo.size.width - insets.leading - insets.trailing,
                    height: geo.size.height - insets.top - insets.bottom
                )
                // Fit, never fill: filling would crop a layout that has
                // no margin to spare on either axis.
                let scale = min(
                    safe.width / design.width,
                    safe.height / design.height
                )

                ZStack {
                    // The letterbox beach is the same beach at the same
                    // zoom: a window-sized canvas measured in design
                    // points, scaled with everything else. Drawn at
                    // window scale instead, its palms and its dune come
                    // out a third the size of the ones inside the canvas
                    // and the edge reads as a seam.
                    Background()
                        .frame(
                            width: geo.size.width / scale,
                            height: geo.size.height / scale
                        )
                        .scaleEffect(scale, anchor: .center)

                    content
                        .frame(width: design.width, height: design.height)
                        // Flattened before the scale. Without it the
                        // canvas's outer edge antialiases against the
                        // white a NavigationStack paints behind itself,
                        // and a pale hairline runs down both sides.
                        .compositingGroup()
                        .scaleEffect(scale, anchor: .center)
                        // Centred in the safe rect rather than in the
                        // window, so the chrome bar clears the status
                        // bar the way it does on a phone.
                        .offset(y: (insets.top - insets.bottom) / 2)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()
        } else {
            content
        }
    }
}
