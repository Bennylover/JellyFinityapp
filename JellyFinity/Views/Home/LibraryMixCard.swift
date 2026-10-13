import SwiftUI
import Charts

struct LibraryMixCard: View {
    @Environment(\.appTheme) private var theme
    let counts: LibraryCounts

    private struct Slice: Identifiable {
        let id: String
        let value: Int
        let color: Color
    }

    private var slices: [Slice] {
        [
            Slice(id: "Movies", value: counts.movies, color: theme.accent),
            Slice(id: "Shows", value: counts.series, color: theme.secondary),
            Slice(id: "Albums", value: counts.albums, color: theme.accent.opacity(0.5)),
            Slice(id: "Books", value: counts.audiobooks, color: theme.secondary.opacity(0.5))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Library Mix").font(.title3.weight(.bold))
                Text("What lives on your server").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 20) {
                donut
                legend
            }
        }
        .padding(20)
        .cardSurface(radius: 26)
    }

    private var donut: some View {
        let items = slices.filter { $0.value > 0 }
        return Chart(items) { slice in
            SectorMark(angle: .value("Count", slice.value), innerRadius: .ratio(0.64), angularInset: 2.5)
                .cornerRadius(5)
                .foregroundStyle(slice.color)
        }
        .chartLegend(.hidden)
        .frame(width: 130, height: 130)
        .overlay {
            VStack(spacing: 0) {
                Text(counts.total, format: .number).font(.title3.weight(.bold).monospacedDigit())
                Text("titles").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(slices) { slice in
                HStack(spacing: 8) {
                    Circle().fill(slice.color).frame(width: 10, height: 10)
                    Text(slice.id).font(.subheadline)
                    Spacer()
                    Text(slice.value, format: .number)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
            }
        }
    }
}
