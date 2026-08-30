import SwiftUI
import ShellYesEngine

struct StatsView: View {
    let stats: StatsStore

    var body: some View {
        ZStack {
            Background()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("statistics")
                        .font(.avenir(34, weight: .ultraLight))
                        .tracking(2)
                        .foregroundStyle(Color.ink)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    glassCard {
                        StatsSection(title: "overview") {
                            StatRow(label: "Games played", value: "\(stats.gamesPlayed)")
                            StatRow(label: "Wins", value: winsValue)
                            StatRow(label: "Win streak", value: streakValue)
                            StatRow(label: "Best score", value: bestScoreValue)
                        }
                    }

                    glassCard {
                        StatsSection(title: "details") {
                            StatRow(label: "Biggest keep", value: biggestKeepValue)
                            StatRow(label: "Steals", value: "\(stats.steals)")
                            StatRow(label: "Busts", value: "\(stats.busts)")
                            StatRow(label: "Hot face", value: hotFaceValue)
                        }
                    }

                    if !stats.bestRuns.isEmpty {
                        glassCard {
                            StatsSection(title: "personal bests") {
                                ForEach(Array(stats.bestRuns.enumerated()), id: \.element.id) { i, run in
                                    BestRunRow(rank: i + 1, run: run, isTop: i == 0)
                                }
                            }
                        }
                    }

                    glassCard {
                        StatsSection(title: "by difficulty") {
                            ForEach(Difficulty.allCases, id: \.self) { d in
                                StatRow(
                                    label: d.rawValue.capitalized,
                                    value: modeValue(
                                        wins: stats.winsByDifficulty[d.rawValue] ?? 0,
                                        games: stats.gamesByDifficulty[d.rawValue] ?? 0
                                    )
                                )
                            }
                        }
                    }

                    glassCard {
                        StatsSection(title: "by pace") {
                            ForEach(GameSpeed.allCases, id: \.self) { p in
                                StatRow(
                                    label: p.rawValue.capitalized,
                                    value: modeValue(
                                        wins: stats.winsByPace[p.rawValue] ?? 0,
                                        games: stats.gamesByPace[p.rawValue] ?? 0
                                    )
                                )
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 18)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var winsValue: String {
        if let rate = stats.winRate {
            let pct = Int((rate * 100).rounded())
            return "\(stats.wins) · \(pct)%"
        }
        return "\(stats.wins)"
    }

    private var streakValue: String {
        if stats.bestStreak > stats.winStreak && stats.bestStreak > 0 {
            return "\(stats.winStreak) · best \(stats.bestStreak)"
        }
        return "\(stats.winStreak)"
    }

    private var bestScoreValue: String {
        stats.bestScore > 0 ? "\(stats.bestScore)" : "—"
    }

    private var biggestKeepValue: String {
        stats.biggestKeep > 0 ? "\(stats.biggestKeep)" : "—"
    }

    private var hotFaceValue: String {
        guard let face = stats.hotFace else { return "—" }
        return face == .coin ? "$" : "\(face.rawValue)"
    }

    private func modeValue(wins: Int, games: Int) -> String {
        guard games > 0 else { return "—" }
        let pct = Int((Double(wins) / Double(games) * 100).rounded())
        return "\(wins)/\(games) · \(pct)%"
    }

    @ViewBuilder
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.ink.opacity(0.18), lineWidth: 1)
        )
        .padding(.bottom, 12)
    }
}

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.avenir(15, weight: .medium))
                .foregroundStyle(Color.ink)
            Spacer()
            Text(value)
                .font(.avenir(15, weight: .demiBold))
                .foregroundStyle(Color.ink.opacity(0.85))
                .monospacedDigit()
        }
        .padding(.vertical, 8)
    }
}

/// One leaderboard line: rank and score on the left, the run's story
/// (day, then the settings it was played under) stacked on the right.
/// The top record gets the coral treatment so the card has a peak
/// instead of five identical rows.
private struct BestRunRow: View {
    let rank: Int
    let run: ScoreRecord
    let isTop: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(rank)")
                .font(.avenir(13, weight: .medium, italic: true))
                .foregroundStyle(Color.dimInk)
                .frame(width: 14, alignment: .leading)

            Text("\(run.score)")
                .font(.avenir(isTop ? 26 : 20, weight: .demiBold))
                .foregroundStyle(isTop ? Color.coral : Color.ink)
                .monospacedDigit()
                .frame(width: 46, alignment: .leading)

            if run.won {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.coinGoldLight)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                Text(run.dayLabel)
                    .font(.avenir(13, weight: .medium))
                    .foregroundStyle(Color.ink.opacity(0.85))
                Text(run.settingLabel)
                    .font(.avenir(11, weight: .medium, italic: true))
                    .tracking(0.5)
                    .foregroundStyle(Color.dimInk)
            }
        }
        .padding(.vertical, isTop ? 10 : 7)
    }
}

private struct StatsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.prefix(1).uppercased() + title.dropFirst())
                .font(.avenir(15, weight: .medium, italic: true))
                .tracking(1.5)
                .foregroundStyle(Color.coral)
                .padding(.bottom, 8)
            content()
        }
    }
}
