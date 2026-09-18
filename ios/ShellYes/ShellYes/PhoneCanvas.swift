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
                //
                // Floored above zero because SwiftUI proposes a zero
                // size on the first pass of some presentations, and a
                // scale of zero turns the window-size division below
                // into infinity — which reaches `BeachScene`'s
                // GeometryReader as a non-finite frame and traps.
                let scale = max(
                    0.0001,
                    min(
                        safe.width / design.width,
                        safe.height / design.height
                    )
                )

                ZStack {
                    // One beach, shaped to the window. The screens
                    // inside stand their own down (see `Background`), so
                    // there is no phone-shaped scene sitting inside an
                    // iPad-shaped one.
                    //
                    // The flag is forced off here: a sheet or cover
                    // inherits the presenter's environment, so its own
                    // canvas would otherwise think it was inside
                    // another one and draw no beach at all.
                    // Forced off for the canvas's own beach: a sheet or
                    // cover inherits the presenter's environment, so
                    // its canvas would otherwise think it was inside
                    // another one and draw nothing at all.
                    Background()
                        .environment(\.isInsidePhoneCanvas, false)

                    content
                        .environment(\.isInsidePhoneCanvas, true)
                        .frame(width: design.width, height: design.height)
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

private struct IsInsidePhoneCanvasKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True for everything drawn inside a `PhoneCanvas`. Only
    /// `Background` reads it, to stand its own phone-shaped scene down
    /// in favour of the window-shaped one the canvas draws.
    var isInsidePhoneCanvas: Bool {
        get { self[IsInsidePhoneCanvasKey.self] }
        set { self[IsInsidePhoneCanvasKey.self] = newValue }
    }
}
