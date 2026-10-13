import SwiftUI

/// Top-billed cast row for a movie or episode, with a button that opens the full credits.
struct CastSection: View {
    @Environment(\.appTheme) private var theme
    let item: MediaItem
    @State private var showingAll = false

    private var actors: [CastMember] { item.cast.filter { $0.role == .actor } }
    private var topBilled: [CastMember] { Array(actors.prefix(10)) }

    var body: some View {
        if !item.cast.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                header
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(topBilled.isEmpty ? Array(item.cast.prefix(10)) : topBilled) { CastCard(member: $0) }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollClipDisabled()
                viewMoreButton
            }
            .sheet(isPresented: $showingAll) { FullCastSheet(item: item) }
        }
    }

    private var header: some View {
        HStack {
            Text("Top Billed Cast").font(.title3.weight(.bold))
            Spacer()
            if item.imdbId != nil {
                Text("IMDb").font(.caption.weight(.heavy))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.yellow, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .foregroundStyle(.black)
                    .accessibilityHidden(true)
            }
        }
    }

    private var viewMoreButton: some View {
        Button {
            showingAll = true
        } label: {
            HStack {
                Text("View full cast & crew")
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(theme.accent)
            .padding(14)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct CastCard: View {
    let member: CastMember

    var body: some View {
        VStack(spacing: 6) {
            CastAvatar(member: member, size: 84)
            Text(member.name)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let caption = member.caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(width: 92)
        .accessibilityElement(children: .combine)
    }
}

private struct CastAvatar: View {
    @Environment(\.appTheme) private var theme
    let member: CastMember
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(theme.gradient.opacity(0.35))
            Text(member.initials)
                .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                .foregroundStyle(theme.accent)
            if let url = member.imageURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    }
                }
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

private struct FullCastSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let item: MediaItem

    private var groups: [(CastMember.Role, [CastMember])] {
        let order: [CastMember.Role] = [.actor, .director, .writer, .producer, .other]
        return order.compactMap { role in
            let members = item.cast.filter { $0.role == role }
            return members.isEmpty ? nil : (role, members)
        }
    }

    private var imdbURL: URL? {
        item.imdbId.flatMap { URL(string: "https://www.imdb.com/title/\($0)/fullcredits") }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.0) { role, members in
                    Section(role.title) {
                        ForEach(members) { FullCastRow(member: $0) }
                    }
                }
                if let imdbURL {
                    Section {
                        Button {
                            openURL(imdbURL)
                        } label: {
                            Label("Open on IMDb", systemImage: "arrow.up.right.square")
                        }
                    } footer: {
                        Text("Credits come from your Jellyfin server's metadata.")
                    }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

private struct FullCastRow: View {
    let member: CastMember

    var body: some View {
        HStack(spacing: 12) {
            CastAvatar(member: member, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name).font(.body.weight(.medium))
                if let caption = member.caption {
                    Text(caption).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
