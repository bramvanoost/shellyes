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
                        .environment(\.phoneCanvas, nil)

                    content
                        .environment(
                            \.phoneCanvas,
                            PhoneCanvasMetrics(
                                scale: scale,
                                size: geo.size,
                                yOffset: (insets.top - insets.bottom) / 2
                            )
                        )
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

/// What a `PhoneCanvas` is doing to the screen inside it: how much it
/// scaled the phone canvas by, the size of the window it scaled into,
/// and how far off centre it pushed the canvas to clear the status bar.
///
/// Read by `Background`, which simply stands down (the canvas draws the
/// beach at window shape itself), and by `canvasFullBleed`, which is how
/// a full-screen scrim reaches the edges of the WINDOW rather than the
/// edges of the canvas.
struct PhoneCanvasMetrics: Equatable {
    let scale: CGFloat
    let size: CGSize
    let yOffset: CGFloat
}

private struct PhoneCanvasKey: EnvironmentKey {
    static let defaultValue: PhoneCanvasMetrics? = nil
}

extension EnvironmentValues {
    var phoneCanvas: PhoneCanvasMetrics? {
        get { self[PhoneCanvasKey.self] }
        set { self[PhoneCanvasKey.self] = newValue }
    }
}

/// Grows a full-screen fill to cover the window it is being scaled
/// into, without changing what it measures.
///
/// `ignoresSafeArea` alone only reaches the edges of the phone canvas,
/// so on iPad a scrim or a bust wash came out as a phone-shaped column
/// with the beach still bright either side of it. The overlay is what
/// keeps this honest: the fill overflows its parent on purpose, while
/// the parent still measures the canvas — a scrim that MEASURED window
/// width would widen the stack it sits in and push the board off both
/// edges of the screen.
private struct CanvasFullBleed: ViewModifier {
    @Environment(\.phoneCanvas) private var canvas

    func body(content: Content) -> some View {
        if let canvas, canvas.scale > 0.01 {
            Color.clear
                .overlay {
                    content
                        .frame(
                            width: canvas.size.width / canvas.scale,
                            height: canvas.size.height / canvas.scale
                        )
                        .offset(y: -canvas.yOffset / canvas.scale)
                }
        } else {
            content
        }
    }
}

extension View {
    /// For full-screen fills only — scrims, washes, flashes. Pairs with
    /// `ignoresSafeArea`, which handles the phone.
    func canvasFullBleed() -> some View {
        modifier(CanvasFullBleed())
    }
}
