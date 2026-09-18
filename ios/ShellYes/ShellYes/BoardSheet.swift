import SwiftUI

/// Everything the board sheet needs to know, built from a standing the
/// player already holds.
///
/// A rank is a rank: tapping any of them opens this, and the board it
/// came from is on page one. What changes with the rank is whether
/// there is a second page — `card` is set only for a held number one,
/// because that is the only standing with a claim to make, and a
/// twelfth place offered a "share your crown" button would be a joke at
/// the player's expense.
///
/// Plain values, no GameKit and no views, so the whole thing is
/// checkable in a test without a signed-in account.
struct BoardSheetSubject: Equatable, Identifiable {
    /// The leaderboard the rows come from. A raw id rather than the
    /// enum, for the same reason `BoardStanding` stores one: a standing
    /// cached by a later build must still carry its id through.
    let boardID: String
    /// The page's heading: "easy · this week".
    let title: String
    /// How many players the board holds, for the denominator.
    let total: Int
    /// The player's own place on it, for telemetry.
    let rank: Int
    /// Which window this board measures, for telemetry.
    let period: StandingPeriod
    /// The board's short name, for telemetry.
    let boardKey: String
    /// Set on weekly score boards, where the number needs explaining.
    let footnote: String?
    /// The share card, or nil below a held number one.
    let card: ShareCardSubject?

    var id: String { "\(boardID)|\(period.rawValue)|\(rank)" }

    /// What the player is, in one word, for telemetry: the two crowns,
    /// or a plain ranked player.
    var tier: String {
        guard let card else { return "ranked" }
        return card.isKahuna ? "big_kahuna" : "top_banana"
    }

    static func from(
        standing: BoardStanding,
        name: String?,
        now: Date = Date()
    ) -> BoardSheetSubject {
        BoardSheetSubject(
            boardID: standing.boardID,
            // The middot form, so the sheet's heading is the same
            // string the splash badge carried: "easy · this week".
            title: standing.contextLine,
            total: standing.total,
            rank: standing.rank,
            period: standing.period,
            boardKey: standing.shortKey,
            footnote: standing.boardFootnote,
            card: ShareCardSubject.from(standing: standing, name: name, now: now)
        )
    }
}

/// The screen a tapped standing opens: the board it came from, and —
/// for a held number one — the card that celebrates it a swipe below.
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
/// board so it needs no explaining. Below rank one there is no page
/// two and no peek — one page that ends where the board ends, rather
/// than a pager with a missing half. The plain Leaderboards button on
/// the splash still goes straight to Apple's screen, for anyone who
/// only wants the real thing, and `open in Game Center` on the board
/// page does the same.
///
/// There is no Save button. The share sheet already offers Save Image,
/// which means the card can reach Photos without the app ever asking
/// for the photo library — one fewer permission prompt, and nothing
/// for the filed App Privacy answers to change.
struct BoardSheet: View {
    let subject: BoardSheetSubject
    /// Called after this sheet closes, to open Apple's board.
    let onSeeBoard: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// Rendered once, on appear, and only when there is a card to
    /// render. A card is a few hundred kilobytes of PNG and the render
    /// is not free; re-rendering it on every layout pass would be paid
    /// for in a stutter as the sheet slides up.
    @SwiftUI.State private var card: ShareCardImage?

    /// Which crowd the board page is reading: everybody, or the
    /// player's Game Center friends.
    @SwiftUI.State private var scope: BoardScope = .everyone

    /// One fetched board per scope, kept so a player swinging between
    /// the two words pays for each read once. A missing entry means
    /// "not asked yet", which is why this is a dictionary of optionals
    /// rather than two arrays: an empty board and a board that has not
    /// answered yet are different pieces of news, and saying "no scores
    /// yet" to somebody who is on the board would be a lie held for as
    /// long as the network takes.
    @SwiftUI.State private var pages: [BoardScope: BoardPage] = [:]

    /// Scopes already counted, so `board_scope_viewed` is once per
    /// scope per sheet however often the toggle is tapped.
    @SwiftUI.State private var trackedScopes: Set<BoardScope> = []

    private var page: BoardPage? { pages[scope] }

    /// The denominator. A global board falls back to the cached
    /// standing's total, which is what it always used and is only ever
    /// minutes stale; a friends board has no cached number to fall back
    /// on and uses what the fetch returned.
    private var total: Int {
        guard let page else { return scope == .everyone ? subject.total : 0 }
        if page.total > 0 { return page.total }
        return scope == .everyone ? subject.total : 0
    }

    /// So the card page counts once per sheet however often somebody
    /// swings between the two pages.
    @SwiftUI.State private var didTrackCard = false

    /// How big the preview can be drawn here. The card is a fixed
    /// 360×450 picture, so it is scaled rather than re-laid-out — what
    /// the player sees has to be the file, not a version of it that
    /// fits better. The two limits are the sheet's width and a little
    /// under two thirds of its height, which keeps the share button and
    /// the board link on screen on the smallest phone we support.
    ///
    /// Floored at zero. The first layout pass can propose a size of
    /// nothing, and `(0 - 48) / 360` is a negative scale, which reaches
    /// `.frame(width:)` as "Invalid frame dimension" in the console.
    private func previewScale(in size: CGSize) -> CGFloat {
        let byWidth = (size.width - 48) / ShareCardView.size.width
        let byHeight = (size.height * 0.62) / ShareCardView.size.height
        return max(0, min(1, byWidth, byHeight))
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

    /// How tall the board page is. A page with a card under it stops
    /// short so the card's top edge shows; a page with nothing under it
    /// is the whole sheet.
    private func boardHeight(in size: CGSize) -> CGFloat {
        // Floored for the same reason `previewScale` is: a first pass
        // proposing nothing would otherwise ask for a page 148pt tall
        // in the negative direction.
        max(0, subject.card == nil ? size.height : size.height - peek)
    }

    /// How tall the rows may grow before the list starts scrolling.
    ///
    /// The card's own chrome — heading, denominator, footnote, the Game
    /// Center link — plus the scope toggle and the way down to the card
    /// come to about 300pt, and all of it is set in fixed sizes, so
    /// subtracting a constant is honest here in a way it would not be
    /// under Dynamic Type. The fraction is the floor that keeps the
    /// smallest phone sane: on an SE the subtraction alone would leave
    /// room for five names.
    private func rowsMaxHeight(in size: CGSize) -> CGFloat {
        let page = boardHeight(in: size)
        return max(page * 0.38, page - 300)
    }

    /// Non-nil on iPad, where this is a full-window cover rather than
    /// a sheet. Only the top padding cares.
    @Environment(\.phoneCanvas) private var canvas

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
                .canvasFullBleed()

            if let cardSubject = subject.card {
                // Two pages, vertical. The board is page one, because
                // that is what a tap on a rank implies and it is the
                // page with something to read; the card is a swipe
                // below it, with its top edge showing so nobody has to
                // guess it is there.
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            boardPage(in: geo.size, goToCard: {
                                trackCardReached(via: "link")
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    proxy.scrollTo(Page.card, anchor: .top)
                                }
                            })
                            .frame(height: boardHeight(in: geo.size))
                            .id(Page.board)

                            cardPage(
                                cardSubject,
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
                    // Without this the sheet can open at the bottom of
                    // the content instead of the top, which put the
                    // card on screen first and left the board behind an
                    // upward swipe — the opposite of the intended
                    // order.
                    .defaultScrollAnchor(.top)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollIndicators(.hidden)
                    // iPad only: the pager stops taking drags, so the
                    // rows are the only thing under a finger — or a
                    // trackpad, which hands its scroll to the outer
                    // view whatever the rows would rather do — that can
                    // move. The written affordances are the way between
                    // the pages there, and they scroll programmatically,
                    // which this does not block.
                    .scrollDisabled(canvas != nil)
                    #if DEBUG
                    .task {
                        guard ScreenshotMode.startsOnShareCard else { return }
                        proxy.scrollTo(Page.card, anchor: .top)
                    }
                    #endif
                }
            } else {
                // Nothing to crown, so nothing below: one page, no
                // pager, no peek. The rows inside it still scroll when
                // there are more of them than fit — that list is the
                // only scroll on the screen, which is the whole reason
                // this branch is not a one-page scroll view with a
                // second scroll view inside it.
                boardPage(in: geo.size, goToCard: nil)
                    .frame(height: geo.size.height)
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
            guard let cardSubject = subject.card else { return }
            card = ShareCardRenderer.render(cardSubject)
        }
        .task(id: scope) {
            await loadRows(for: scope)
        }
        }
    }

    // ------------------------------------------- page one: the board

    @ViewBuilder
    private func boardPage(
        in size: CGSize,
        goToCard: (() -> Void)?
    ) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            BoardCard(
                title: subject.title,
                rows: page?.rows ?? [],
                total: total,
                scope: scope,
                footnote: subject.footnote,
                isLoading: page == nil,
                rowsMaxHeight: rowsMaxHeight(in: size),
                onOpenGameCenter: {
                    dismiss()
                    onSeeBoard()
                }
            )

            scopeToggle

            Spacer(minLength: 0)

            // A tap target for the same move the peek already
            // suggests. The card edge below is the affordance; this is
            // for the thumb that would rather press a word than drag.
            // Absent below rank one, where there is no card to go to.
            if let goToCard {
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
        }
        .padding(.horizontal, 24)
        // On a phone this page opens as a sheet, below a gap and a
        // grabber, so 24 clears the close button on its own. On iPad it
        // opens as a cover that starts at the top of the window, where
        // 24 puts the board's top corner right under the glyph — so it
        // borrows the card page's 70.
        .padding(.top, canvas == nil ? 24 : 70)
        .padding(.bottom, 8)
    }

    /// Two words under the board. Not a segmented control: this is a
    /// change of view, not a setting, and the board it belongs to is
    /// drawn in the app's own hand rather than the system's.
    ///
    /// It shows whatever the scope returns, including nothing —
    /// "no friends on this board yet" is an honest answer and the only
    /// one available until enough accounts have read it to say whether
    /// GameKit hands friends over ungated at all.
    private var scopeToggle: some View {
        HStack(spacing: 6) {
            ForEach(BoardScope.allCases) { option in
                let selected = option == scope
                Button {
                    guard !selected else { return }
                    withAnimation(.easeOut(duration: 0.2)) { scope = option }
                } label: {
                    Text(option.label)
                        .font(.avenir(12, weight: selected ? .demiBold : .medium, italic: true))
                        .tracking(1.5)
                        .foregroundStyle(Color.ink.opacity(selected ? 0.85 : 0.45))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(selected ? Color.paper.opacity(0.75) : Color.clear)
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    Color.ink.opacity(selected ? 0.25 : 0),
                                    lineWidth: 1
                                )
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.top, 12)
    }

    // -------------------------------------------- page two: the card

    @ViewBuilder
    private func cardPage(
        _ subject: ShareCardSubject,
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
                        // No `message:`. Adding text alongside the card
                        // makes the payload image-plus-text, and Photos
                        // drops "Save Image" from the sheet unless every
                        // item is an image. `subject:` is safe — it is
                        // metadata for the destination (a mail subject
                        // line), not a second item in the payload. See
                        // `AppLink` for where the store link went.
                        ShareLink(
                            item: card,
                            subject: Text(subject.message),
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
            "tier": subject.tier,
        ])
    }

    /// Goes and gets the rows the board page draws.
    ///
    /// Fetched here rather than alongside the ranks on the splash: the
    /// splash needs one number per board and gets it from a range of
    /// one, while this needs a whole board's rows, and asking for all
    /// of them up front would be five larger round trips for a page
    /// most launches never open.
    private func loadRows(for scope: BoardScope) async {
        // Already fetched this sheet: the toggle is a redraw, not a
        // second round trip.
        guard pages[scope] == nil else { return }
        #if DEBUG
        if ScreenshotMode.seedsBoardRows {
            let rows = BoardCard.mockRows(
                me: GameCenter.shared.playerFirstName,
                count: ScreenshotMode.boardRowCount
            )
            pages[scope] = BoardPage(
                rows: scope == .friends ? Array(rows.prefix(4)) : rows,
                total: scope == .friends ? 4 : subject.total
            )
            return
        }
        #endif
        let fetched = await GameCenter.shared.loadBoardRows(
            for: subject.boardID,
            scope: scope
        )
        pages[scope] = fetched
        guard trackedScopes.insert(scope).inserted else { return }
        // The experiment: does `.friendsOnly` return anything without
        // the friends-authorization grant? `rows` against `scope` in
        // the dashboard is the answer.
        Telemetry.shared.track("board_scope_viewed", props: [
            "scope": scope.rawValue,
            "rows": fetched.rows.count,
            "total": fetched.total,
        ])
    }
}
