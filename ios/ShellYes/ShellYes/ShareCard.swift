import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Where the app lives on the store. Travels in the share sheet's
/// message rather than being drawn on the card: a URL inside an image
/// is a thing to retype, a URL in the message is a thing to tap.
enum AppLink {
    static let appStore = URL(string: "https://apps.apple.com/app/id6805609705")!
}

/// Everything one share card says.
///
/// Built from a standing the player already holds, so the card can
/// never claim a rank the boards haven't confirmed. Plain values, no
/// GameKit and no views, which is what lets the whole thing be checked
/// in a test without a signed-in account.
struct ShareCardSubject: Equatable, Identifiable {
    /// "Top Banana" or "Big Kahuna".
    let title: String
    /// Drives the palms-instead-of-a-crown treatment, the same tier
    /// split the splash line makes.
    let isKahuna: Bool
    /// What to call the player, or nil when we were never told.
    ///
    /// Local only. The name comes from `GKLocalPlayer.displayName`,
    /// lives in `UserDefaults`, and is drawn straight into an image on
    /// the device. It is never a telemetry property and it never
    /// reaches a server of ours — the only way it leaves the phone is
    /// the player themselves choosing to send the picture.
    let name: String?
    /// "easy", "best streak", "biggest keep".
    let boardName: String
    /// "week of 8–14 Sep", or "all time".
    ///
    /// Weekly cards name their dates rather than saying "this week"
    /// because a card outlives the week it was made in. An all-time
    /// card says "all time" and stays true by definition.
    let windowLine: String
    /// "96 coins", "5 wins in a row". Nil for a board this build
    /// doesn't recognise, in which case the card simply omits the line.
    let scorePhrase: String?

    /// Identity for `.sheet(item:)`. The claim itself is the id:
    /// two cards that say the same thing are the same card.
    var id: String { "\(title)|\(boardName)|\(windowLine)" }

    /// The text the share sheet carries beside the picture, for the
    /// apps that show one. The link is the point: a picture of a rank
    /// is a nice thing to receive, and a nice thing to receive with a
    /// way to go and beat it is better.
    var message: String {
        "\(title) on Shell Yes — \(boardName), \(windowLine)."
    }

    /// The one filename every card shares. Deliberately not the
    /// player's name: the file travels to whoever they send it to, and
    /// a filename is a poor place to put a person.
    var filename: String {
        isKahuna ? "shell-yes-big-kahuna.png" : "shell-yes-top-banana.png"
    }

    /// The card for a standing, or nil when there is nothing to
    /// celebrate — anything below rank one has no claim to make.
    static func from(
        standing: BoardStanding,
        name: String?,
        now: Date = Date()
    ) -> ShareCardSubject? {
        guard let title = standing.crownTitle else { return nil }

        let window: String
        if standing.isWeekly {
            let id = WeeklyBests.weekID(for: now)
            // The dates are a nicety; a card without them still says
            // which week it was by saying "this week" the way the app
            // does. Better a vaguer card than no card.
            window = WeeklyBests.weekLabel(for: id, now: now)
                .map { "week of \($0)" } ?? "this week"
        } else {
            window = "all time"
        }

        return ShareCardSubject(
            title: title,
            isKahuna: standing.isKahuna,
            name: name,
            boardName: standing.boardName,
            windowLine: window,
            scorePhrase: standing.scorePhrase
        )
    }
}

// MARK: - The picture

/// The card itself, drawn at a fixed size so the render is the same
/// picture on every phone.
///
/// 4:5 because that is the tallest crop Messages, Instagram and
/// WhatsApp all show without cutting into it, and a portrait card
/// fills more of a phone screen than a square one.
struct ShareCardView: View {
    let subject: ShareCardSubject

    /// Points, not pixels. `ShareCardRenderer.scale` turns this into
    /// 1080×1350, which is enough for a full-screen look on any phone
    /// and still a file small enough to send over a bad connection.
    static let size = CGSize(width: 360, height: 450)

    /// The gold mark beside the title: a crown for the week, a pair of
    /// palms for all time. SF Symbols calls them laurels; on this
    /// beach they read as palm fronds, which is the better joke.
    private func mark(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: subject.isKahuna ? 26 : 23, weight: .medium))
            .foregroundStyle(Color.gold)
            .shadow(color: Color.coinGoldLight.opacity(0.8), radius: 10)
    }

    var body: some View {
        ZStack {
            // The beach sits lower here than it does on a phone. At
            // card size the default horizon puts a dune and two palms
            // straight through the middle of the type.
            Background(groundInset: 96)

            VStack(spacing: 0) {
                // Brand first and small. The claim below is what the
                // card is for; the wordmark is only there so somebody
                // who has never seen the game knows what they are
                // looking at.
                HStack(spacing: 10) {
                    ShellMedallion(size: 30)
                    Text("Shell Yes")
                        .font(.custom("Optima", size: 25).weight(.semibold))
                        .tracking(0.5)
                        .foregroundStyle(Color.ink)
                }
                .padding(.top, 34)

                Spacer(minLength: 0)

                if let name = subject.name {
                    Text(name)
                        .font(.avenir(27, weight: .demiBold, italic: true))
                        .tracking(1)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        // Gamertags run long. Shrinking beats wrapping,
                        // and the floor is high enough that a long name
                        // still reads as the biggest word on the card.
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 36)
                        .padding(.bottom, 16)
                }

                // The claim. Same pill as the splash line, at the size
                // of a thing worth photographing — and held at the top
                // of its breath, since a still image gets one frame and
                // may as well have the bright one.
                HStack(spacing: subject.isKahuna ? 8 : 10) {
                    mark(subject.isKahuna ? "laurel.leading" : "crown.fill")

                    Text(subject.title)
                        .font(.avenir(23, weight: .demiBold))
                        .tracking(3)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if subject.isKahuna { mark("laurel.trailing") }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 26)
                .background {
                    Capsule()
                        .fill(Color.coinGoldLight.opacity(subject.isKahuna ? 0.44 : 0.30))
                        .overlay(
                            Capsule().strokeBorder(
                                Color.gold.opacity(0.75),
                                lineWidth: subject.isKahuna ? 2 : 1.5
                            )
                        )
                        .shadow(
                            color: Color.gold.opacity(subject.isKahuna ? 0.6 : 0.45),
                            radius: subject.isKahuna ? 26 : 20
                        )
                        .shadow(color: Color.pearlGlow.opacity(0.5), radius: 5)
                }

                Text("\(subject.boardName), \(subject.windowLine)")
                    .font(.avenir(15, weight: .medium, italic: true))
                    .tracking(1.5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.ink.opacity(0.65))
                    .padding(.top, 18)
                    .padding(.horizontal, 30)

                if let score = subject.scorePhrase {
                    Text(score)
                        .font(.avenir(14, weight: .demiBold, italic: true))
                        .tracking(1.5)
                        .foregroundStyle(Color.ink.opacity(0.5))
                        .monospacedDigit()
                        .padding(.top, 6)
                }

                Spacer(minLength: 0)

                // Written on the sand, in sand colour. The dune is the
                // darkest thing on the card, so ink would fight it and
                // moving the line off the dune leaves it sitting in
                // the palms instead. Cream on the dune is the one
                // place on this card where a caption can be read
                // without argument.
                VStack(spacing: 4) {
                    Text("A beachy soft slow thinky game.")
                        .font(.avenir(12, weight: .demiBold, italic: true))
                        .tracking(1)
                        .foregroundStyle(Color.stampText.opacity(0.92))
                    Text("free on the App Store")
                        .font(.avenir(11, weight: .medium, italic: true))
                        .tracking(1)
                        .foregroundStyle(Color.stampText.opacity(0.7))
                }
                .multilineTextAlignment(.center)
                .shadow(color: Color.treasureInk.opacity(0.35), radius: 3, y: 1)
                .padding(.bottom, 26)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // Golden hour, always. The app follows the system into a night
        // palette, but a card is a piece of the game somebody else
        // sees first, and it should look like the game rather than
        // like the sender's display settings.
        .environment(\.colorScheme, .light)
    }
}

// MARK: - Turning it into a file

enum ShareCardError: Error {
    case renderFailed
}

/// A rendered card, ready for the share sheet. PNG rather than JPEG:
/// the card is flat colour and type, which is exactly what PNG is good
/// at and JPEG smears.
struct ShareCardImage: Transferable {
    let image: UIImage
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in
            guard let data = card.image.pngData() else {
                throw ShareCardError.renderFailed
            }
            return data
        }
        .suggestedFileName { $0.filename }
    }
}

@MainActor
enum ShareCardRenderer {
    /// 3× the layout, so the card lands at 1080×1350 — the size every
    /// social app wants and none of them upscale.
    static let scale: CGFloat = 3

    static func render(_ subject: ShareCardSubject) -> ShareCardImage? {
        let renderer = ImageRenderer(content: ShareCardView(subject: subject))
        renderer.scale = scale
        // No transparency to preserve: a solid card is a smaller file
        // and composites faster wherever it ends up.
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { return nil }
        return ShareCardImage(image: image, filename: subject.filename)
    }
}
