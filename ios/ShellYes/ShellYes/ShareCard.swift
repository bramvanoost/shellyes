import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Where the app lives on the store.
///
/// It used to ride in the share sheet's `message:`, which made it
/// tappable wherever the card landed. That had a price nobody spotted
/// until someone tried to keep their own card: a payload of image *plus*
/// text is not all-images, and Photos only offers "Save Image" when
/// every item is an image. So the link cost the player the one thing
/// they wanted to do with a picture of their own rank.
///
/// The link is off the share sheet now. Discovery rests on the card
/// art, which says "Shell Yes" and "Free on the App Store!" — a name to
/// search rather than a link to tap. If sharing stops converting, a QR
/// code or a short link drawn onto the card is the next thing to try;
/// putting the URL back in `message:` is not, because it silently takes
/// Save Image away again.
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
    /// How many players are on the board this card came from, so the
    /// board page can put a denominator under the rows.
    var total: Int = 0
    /// "easy, this week" — the board this card came from, as the second
    /// page's heading.
    var boardTitle: String = ""
    /// What the board counts, so the card can name the record in
    /// words — "Top Score" rather than the board's own terse "easy".
    /// Nil for a board this build doesn't recognise, which is the one
    /// case where the card falls back to the old one-line form.
    var kind: BoardKind?
    /// Set on weekly score boards only, where the number on the board
    /// is a sum of three games and reads as a bug without a sentence
    /// saying so. Apple's own sheet has no room to say it, which is
    /// half the reason we draw the board ourselves.
    var boardFootnote: String?
    /// The leaderboard this card came from, so the sheet's board page
    /// can go and fetch its rows. A raw id rather than the enum for
    /// the same reason `BoardStanding` stores one: a card built from a
    /// cached standing written by an older build must still carry the
    /// id through, even if this build has no case for it.
    var boardID: String = ""

    /// The record, named: "All Time Top Score", "This Week's Best
    /// Streak". Title case and up front, because the card is read by
    /// someone who has never seen the boards and needs to be told what
    /// was won before being told the number.
    var headline: String? {
        guard let kind else { return nil }
        let record: String
        switch kind {
        case .score:  record = "Top Score"
        case .streak: record = "Best Streak"
        case .keep:   record = "Biggest Keep"
        }
        return isKahuna ? "All Time \(record)" : "This Week's \(record)"
    }

    /// "on Easy". Only the score boards have a difficulty to name; the
    /// streak and keep boards are one board each, already named by the
    /// headline, and "on Streak" would be a line saying nothing.
    var difficultyLine: String? {
        guard kind == .score else { return nil }
        return "on \(boardName.capitalized)"
    }

    /// "96 Coins", "5 Wins in a Row". Same words as `scorePhrase`, in
    /// the title case the rest of the card's claim is set in.
    var scoreLine: String? {
        scorePhrase?
            .split(separator: " ")
            .map { $0.count > 2 ? $0.capitalized : String($0) }
            .joined(separator: " ")
    }

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
            window = WeeklyBests.weekLabel(for: id)
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
            scorePhrase: standing.scorePhrase,
            total: standing.total,
            // The middot form, so the board page's heading is the same
            // string the splash badge carried: "easy · this week",
            // "easy · all time". A comma here and a middot there read
            // as two different labels for one board.
            boardTitle: standing.contextLine,
            kind: standing.kind,
            boardFootnote: standing.isWeekly && standing.weeklyBoard?.kind == .score
                ? "your best three games this week, added up"
                : nil,
            boardID: standing.boardID
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
                HStack(spacing: 13) {
                    ShellMedallion(size: 42)
                    Text("Shell Yes")
                        .font(.custom("Optima", size: 33).weight(.semibold))
                        .tracking(0.5)
                        .foregroundStyle(Color.ink)
                }
                .padding(.top, 48)

                Spacer(minLength: 0)

                if let name = subject.name {
                    Text(name)
                        // Upright, unlike every other line on the card:
                        // a name is not a caption about the game, and
                        // the italic made it read as one.
                        .font(.avenir(27, weight: .demiBold))
                        .tracking(1)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        // Gamertags run long. Shrinking beats wrapping,
                        // and the floor is high enough that a long name
                        // still reads as the biggest word on the card.
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 36)
                        .padding(.bottom, 16)
                        // The pill comes after the name in this stack,
                        // so its rays — which reach well past the
                        // capsule — paint over the name by default.
                        // The name wins.
                        .zIndex(1)
                }

                ClaimBadge(title: subject.title, isKahuna: subject.isKahuna)

                // What was won, in three short lines instead of one
                // run-on. "All Time Top Score / on Easy / 96 Coins"
                // reads top to bottom the way the news actually
                // arrives: the record, the board, the number. A board
                // this build doesn't recognise has no record to name,
                // so it keeps the old single line.
                if let headline = subject.headline {
                    VStack(spacing: 5) {
                        Text(headline)
                            .font(.avenir(18, weight: .demiBold, italic: true))
                            .tracking(1.5)
                            .foregroundStyle(Color.ink.opacity(0.72))

                        if let difficulty = subject.difficultyLine {
                            Text(difficulty)
                                .font(.avenir(15, weight: .medium, italic: true))
                                .tracking(1.5)
                                .foregroundStyle(Color.ink.opacity(0.55))
                        }

                        if let score = subject.scoreLine {
                            Text(score)
                                // Same size as the headline above it:
                                // the record and its number are one
                                // claim in two lines, and a step in
                                // type size made the number look like
                                // a separate, louder thing.
                                .font(.avenir(18, weight: .demiBold, italic: true))
                                .tracking(1.5)
                                .foregroundStyle(Color.ink.opacity(0.72))
                                .monospacedDigit()
                                .padding(.top, 2)
                        }

                        // Weekly cards still name their dates: a card
                        // outlives the week it was made in, and
                        // "This Week's" alone stops being true.
                        if !subject.isKahuna {
                            Text(subject.windowLine)
                                .font(.avenir(12, weight: .medium, italic: true))
                                .tracking(1.5)
                                .foregroundStyle(Color.ink.opacity(0.45))
                                .padding(.top, 2)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 18)
                    .padding(.horizontal, 30)
                    // Holds the claim off the sand line. Without it the
                    // score and the tagline share one band of space and
                    // the card reads as two paragraphs run together.
                    .padding(.bottom, 24)
                } else {
                    Text("\(subject.boardName), \(subject.windowLine)")
                        .font(.avenir(15, weight: .medium, italic: true))
                        .tracking(1.5)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.ink.opacity(0.65))
                        .padding(.top, 18)
                        .padding(.horizontal, 30)
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
                    Text("Free on the App Store!")
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

/// The claim pill: a pair of crowns around "Top Banana" for the week,
/// a pair of palms around "Big Kahuna" for all time.
///
/// Its own view so both tiers are measurably one shape. The tier
/// differences are colour and mark, never size: a Big Kahuna badge that
/// came out a few points taller than a Top Banana one read as a
/// mistake rather than as a rank.
struct ClaimBadge: View {
    let title: String
    let isKahuna: Bool

    /// One line box for both marks, so the taller symbol cannot push
    /// the capsule open. SF Symbols calls them laurels; on this beach
    /// they read as palm fronds, which is the better joke.
    private func mark(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 21, weight: .medium))
            .foregroundStyle(Color.gold)
            .frame(width: 21, height: 22)
            .shadow(color: Color.coinGoldLight.opacity(0.8), radius: 10)
    }

    var body: some View {
        HStack(spacing: 9) {
            mark(isKahuna ? "laurel.leading" : "crown.fill")

            Text(title)
                .font(.avenir(19, weight: .demiBold))
                .tracking(3)
                .textCase(.uppercase)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                // All caps, so the glyphs fill only the top of their
                // line box and the descender space below parks them
                // visibly above the capsule's middle. A point and a
                // half down is what it takes for the eye to read them
                // as centred.
                .offset(y: 1.5)

            // Both marks come in pairs, matching the splash badge in
            // `StandingLine`. A lone leading crown left the Top Banana
            // pill lopsided while the Big Kahuna one was symmetrical,
            // which read as the weekly tier being half-dressed rather
            // than as a lesser rank.
            mark(isKahuna ? "laurel.trailing" : "crown.fill")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 22)
        .background {
            Capsule()
                .fill(Color.coinGoldLight.opacity(isKahuna ? 0.44 : 0.30))
                .overlay(
                    Capsule().strokeBorder(
                        Color.gold.opacity(0.75),
                        lineWidth: isKahuna ? 2 : 1.5
                    )
                )
                .shadow(
                    color: Color.gold.opacity(isKahuna ? 0.6 : 0.45),
                    radius: isKahuna ? 26 : 20
                )
                .shadow(color: Color.pearlGlow.opacity(0.5), radius: 5)
        }
        // Rays for the Big Kahuna only. Top of an all-time board is the
        // rarer of the two crowns and the card should look like it: the
        // weekly one keeps the plain pill so the difference is visible
        // at a glance.
        //
        // Static, not turning: `ImageRenderer` takes a single frame and
        // never runs `onAppear`, so the animated form would render as
        // an empty halo.
        .background {
            if isKahuna {
                LightRays(
                    rayCount: 12,
                    innerRadius: 30,
                    outerRadius: 96,
                    rayWidth: 20,
                    maxOpacity: 0.4,
                    adaptToColorScheme: false,
                    animates: false,
                    color: .gold
                )
                .allowsHitTesting(false)
            }
        }
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
        // The image proxy goes FIRST, and that ordering is the whole
        // point. A `TransferRepresentation` builder is a preference
        // list, not a set: the share sheet takes the first one it can
        // use and describes the item by it. With the PNG data first
        // the card arrived as a *file*, so Photos never offered itself
        // and the only destinations were Files and whatever else eats
        // documents. 1.3 added this proxy but left it second, which
        // changed nothing on a device.
        ProxyRepresentation { Image(uiImage: $0.image) }

        // Still vended, second: anything that would rather have a
        // named PNG than an image object gets one.
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
