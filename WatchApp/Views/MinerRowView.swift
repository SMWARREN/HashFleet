import HashFleetWatchCore
import SwiftUI

struct MinerRowView: View {
    let store: WatchFleetStore
    let miner: WatchMiner

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            RowContent(snapshot: MinerSnapshot(miner: miner, store: store, now: context.date), now: context.date)
        }
    }
}

private struct RowContent: View {
    let snapshot: MinerSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.miner.name)
                .font(.headline)
                .lineLimit(2)
            Text(WatchFormat.hashrate(snapshot.reading?.hashrateGHs))
                .font(.footnote)
                .foregroundStyle(snapshot.status == .current ? Color.hashGold : .secondary)
            Label(statusText, systemImage: snapshot.status.symbol)
                .font(.footnote)
                .foregroundStyle(snapshot.status.tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel)
        .privacySensitive()
    }

    private var statusText: String {
        guard let reading = snapshot.reading else { return snapshot.status.title }
        let age = WatchFormat.age(of: reading.observedAt, now: now)
        switch snapshot.status {
        case .unreachable: return "Can't reach. Saved \(age)"
        case .stale: return "Stale, \(age)"
        case .current, .notChecked: return age.capitalizedFirst
        }
    }

    private var spokenLabel: String {
        var parts = [snapshot.miner.name, "hashrate \(WatchFormat.hashrate(snapshot.reading?.hashrateGHs))"]
        parts.append(statusText)
        return parts.joined(separator: ", ")
    }
}

extension String {
    fileprivate var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
