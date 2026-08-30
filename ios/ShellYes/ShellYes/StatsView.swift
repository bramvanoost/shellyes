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
                            if let best = stats.bestRuns.first {
                                BestScoreRow(run: best)
                            } else {
                                StatRow(label: "Best score", value: bestScoreValue)
                            }
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

/// Best score with its story on one line: the number (crowned if that
/// run was a win) over the day it happened and the settings it was
/// played under. A bare "34" says nothing about where it came from.
private struct BestScoreRow: View {
    let run: ScoreRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Best score")
                .font(.avenir(15, weight: .medium))
                .foregroundStyle(Color.ink)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 5) {
                    if run.won {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.coinGoldLight)
                    }
                    Text("\(run.score)")
                        .font(.avenir(15, weight: .demiBold))
                        .foregroundStyle(Color.ink.opacity(0.85))
                        .monospacedDigit()
                }
                Text("\(run.dayLabel) · \(run.settingLabel)")
                    .font(.avenir(11, weight: .medium, italic: true))
                    .tracking(0.5)
                    .foregroundStyle(Color.dimInk)
            }
        }
        .padding(.vertical, 8)
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
