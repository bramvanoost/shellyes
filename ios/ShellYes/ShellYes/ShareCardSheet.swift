import SwiftUI

/// The screen a tapped crown opens: two vertical pages, the board the
/// crown came from and the card that celebrates it.
///
/// Why this sits between the splash and Apple's leaderboard screen at
/// all: Apple's `GKGameCenterViewController` is built for modal
/// presentation and cannot be themed, so handing the player straight
/// to it means leaving our own look at the exact moment they feel best
/// about the game. The rows behind it were always ours —
/// `loadEntries` returns the top entries next to the local player's —
/// so we draw the board instead, and it gets to say the thing Apple's
/// sheet has no room for: that a weekly score is three games added up.
///
/// The board is page one, because that is what a tap on a rank
/// implies. The card is page two, with its top edge showing under the
/// board so it needs no explaining. The plain Leaderboards button on
/// the splash still goes straight to Apple's screen, for anyone who
/// only wants the real thing, and `open in Game Center` on the board
/// page does the same.
///
/// There is no Save button. The share sheet already offers Save Image,
/// which means the card can reach Photos without the app ever asking
/// for the photo library — one fewer permission prompt, and nothing
/// for the filed App Privacy answers to change.
struct ShareCardSheet: View {
    let subject: ShareCardSubject
    /// Called after this sheet closes, to open Apple's board.
    let onSeeBoard: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// Rendered once, on appear. A card is a few hundred kilobytes of
    /// PNG and the render is not free; re-rendering it on every layout
    /// pass would be paid for in a stutter as the sheet slides up.
    @SwiftUI.State private var card: ShareCardImage?

    /// The board page's rows, and whether they are still coming. The
    /// two are separate because an empty board and a board that has
    /// not answered yet are different pieces of news, and saying "no
    /// scores yet" to somebody who is on the board would be a lie held
    /// for as long as the network takes.
    @SwiftUI.State private var rows: [BoardRow] = []
    @SwiftUI.State private var isLoadingRows = true

    /// So the card page counts once per sheet however often somebody
    /// swings between the two pages.
    @SwiftUI.State private var didTrackCard = false

    /// How big the preview can be drawn here. The card is a fixed
    /// 360×450 picture, so it is scaled rather than re-laid-out — what
    /// the player sees has to be the file, not a version of it that
    /// fits better. The two limits are the sheet's width and a little
    /// under two thirds of its height, which keeps the share button and
    /// the board link on screen on the smallest phone we support.
    private func previewScale(in size: CGSize) -> CGFloat {
        let byWidth = (size.width - 48) / ShareCardView.size.width
        let byHeight = (size.height * 0.62) / ShareCardView.size.height
        return min(1, byWidth, byHeight)
    }

    /// Page identities for the scroll proxy. Plain constants rather
    /// than a `scrollPosition(id:)` binding: that binding never
    /// resolved the `.id()` on two statically-declared children, so
    /// the sheet opened wherever layout timing left it — the board when
    /// presented one way, the card when presented another. A proxy and
    /// an explicit anchor are deterministic.
    private enum Page: Hashable {
        case board, card
    }

    /// How much of the card page shows under the board. The point of
    /// the peek is that page two needs no explaining: a card edge
    /// coming up off the bottom of the screen is the only affordance
    /// that cannot be missed, where a chevron can.
    ///
    /// It is also why this is `.viewAligned` rather than `.paging`.
    /// Paging snaps in whole screenfuls, so every page has to be
    /// exactly the container's height and a peek is impossible;
    /// view-aligned snaps to the pages themselves, which are free to be
    /// different heights.
    private let peek: CGFloat = 148

    var body: some View {
        GeometryReader { geo in
        let scale = previewScale(in: geo.size)
        ZStack {
            Background()
            // The card carries the same beach. Without a veil the two
            // scenes read as one busy picture and the card stops
            // looking like an object.
            Color.paper.opacity(0.45)
                .ignoresSafeArea()

            // Two pages, vertical. The board is page one, because that
            // is what a tap on a rank implies and it is the page with
            // something to read; the card is a swipe below it, with its
            // top edge showing so nobody has to guess it is there.
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        boardPage(goToCard: {
                            trackCardReached(via: "link")
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo(Page.card, anchor: .top)
                            }
                        })
                        .frame(height: geo.size.height - peek)
                        .id(Page.board)

                        cardPage(
                            scale: scale,
                            goToCard: {
                                trackCardReached(via: "peek")
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    proxy.scrollTo(Page.card, anchor: .top)
                                }
                            },
                            goToBoard: {
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    proxy.scrollTo(Page.board, anchor: .top)
                                }
                            }
                        )
                        .frame(height: geo.size.height)
                        .id(Page.card)
                    }
                    .scrollTargetLayout()
                }
                // Without this the sheet can open at the bottom of the
                // content instead of the top, which put the card on
                // screen first and left the board behind an upward
                // swipe — the opposite of the intended order.
                .defaultScrollAnchor(.top)
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                #if DEBUG
                .task {
                    guard ScreenshotMode.startsOnShareCard else { return }
                    proxy.scrollTo(Page.card, anchor: .top)
                }
                #endif
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink.opacity(0.55))
                    .frame(width: 32, height: 32)
                    // The card comes right up under this button on the
                    // second page, and an unbacked glyph sitting on a
                    // sunset gradient was both hard to see and easy to
                    // believe was decoration.
                    .background(
                        Circle()
                            .fill(Color.paper.opacity(0.82))
                            .overlay(Circle().strokeBorder(Color.ink.opacity(0.10), lineWidth: 1))
                    )
                    .contentShape(Circle())
                    .padding(12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .task {
            card = ShareCardRenderer.render(subject)
        }
        .task {
            await loadRows()
        }
        }
    }

    // ------------------------------------------- page one: the board

    @ViewBuilder
    private func boardPage(goToCard: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            BoardCard(
                title: subject.boardTitle,
                rows: rows,
                total: subject.total,
                footnote: subject.boardFootnote,
                isLoading: isLoadingRows,
                onOpenGameCenter: {
                    dismiss()
                    onSeeBoard()
                }
            )

            Spacer(minLength: 0)

            // A tap target for the same move the peek already
            // suggests. The card edge below is the affordance; this is
            // for the thumb that would rather press a word than drag.
            Button(action: goToCard) {
                VStack(spacing: 2) {
                    Text("share your crown")
                        .font(.avenir(13, weight: .medium, italic: true))
                        .tracking(2)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color.ink.opacity(0.55))
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    // -------------------------------------------- page two: the card

    @ViewBuilder
    private func cardPage(
        scale: CGFloat,
        goToCard: @escaping () -> Void,
        goToBoard: @escaping () -> Void
    ) -> some View {
            // Top-aligned, not centred: the top of this page is what
            // shows in the peek under the board, so the card itself has
            // to be the thing up there. Centred, the peek would be a
            // strip of empty sand.
            VStack(spacing: 22) {
                // The card at its own aspect ratio, sized to the sheet.
                // What the player sees here is the file, pixel for
                // pixel, so there is never a surprise in what lands in
                // the message.
                ShareCardView(subject: subject)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Color.ink.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.treasureInk.opacity(0.25), radius: 18, y: 8)
                    .scaleEffect(scale)
                    .frame(
                        width: ShareCardView.size.width * scale,
                        height: ShareCardView.size.height * scale
                    )
                    .contentShape(Rectangle())
                    // The peek is a sliver of this same view, so a tap
                    // on the card edge under the board brings the card
                    // up. On the card page itself the tap scrolls to
                    // where it already is, which costs nothing and
                    // saves explaining that the edge is the only
                    // tappable part.
                    .onTapGesture(perform: goToCard)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(subject.message)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Shows the whole card")

                VStack(spacing: 14) {
                    if let card {
                        ShareLink(
                            item: card,
                            subject: Text(subject.message),
                            // The link rides in the message rather than
                            // on the picture, so it is tappable
                            // wherever the card ends up.
                            message: Text("\(subject.message) \(AppLink.appStore.absoluteString)"),
                            preview: SharePreview(
                                subject.message,
                                image: Image(uiImage: card.image)
                            )
                        ) {
                            Text("Share")
                        }
                        .stampButton(primary: true, invite: true)
                        .frame(maxWidth: 280)
                    }

                    // Back up to the board. The system's swipe-down
                    // dismisses the sheet from the first page only, so
                    // on this page there is no gesture that means
                    // "back" and it has to be a word.
                    Button(action: goToBoard) {
                        VStack(spacing: 2) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 11, weight: .semibold))
                            Text("back to the board")
                                .font(.avenir(13, weight: .medium, italic: true))
                                .tracking(2)
                        }
                        .foregroundStyle(Color.ink.opacity(0.5))
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 24)
            // Clear of the close button, which floats over both pages.
            // Enough that the card's corner is not under the glyph, and
            // little enough that what peeks under the board is still
            // card rather than sand.
            .padding(.top, 70)
            .padding(.bottom, 24)
    }

    /// Fired the first time the card page is reached by one of the
    /// affordances we can see. A bare swipe is invisible from here —
    /// there is no scroll position to observe without the binding that
    /// would not resolve — so this is a floor on how many people got
    /// to the card, never a total. Once per sheet.
    private func trackCardReached(via: String) {
        guard !didTrackCard else { return }
        didTrackCard = true
        Telemetry.shared.track("share_card_viewed", props: [
            "via": via,
            "tier": subject.isKahuna ? "big_kahuna" : "top_banana",
        ])
    }

    /// Goes and gets the rows the board page draws.
    ///
    /// Fetched here rather than alongside the ranks on the splash: the
    /// splash needs one number per board and gets it from a range of
    /// one, while this needs eight rows from a single board, and
    /// asking for all of them up front would be five larger round
    /// trips for a page most launches never open.
    private func loadRows() async {
        #if DEBUG
        if ScreenshotMode.seedsBoardRows {
            rows = BoardCard.mockRows(me: GameCenter.shared.playerFirstName)
            isLoadingRows = false
            return
        }
        #endif
        rows = await GameCenter.shared.loadBoardRows(for: subject.boardID)
        isLoadingRows = false
    }
}
