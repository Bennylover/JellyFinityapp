import SwiftUI

struct MoviesView: View {
    var body: some View {
        NavigationStack {
            ComingSoonView(symbol: "film.stack",
                           title: "Your Cinema",
                           message: "A sleek, card-based movie library with filters, genres and collections is coming next.")
                .navigationTitle("Movies")
        }
    }
}

struct MusicView: View {
    var body: some View {
        NavigationStack {
            ComingSoonView(symbol: "music.note",
                           title: "Music, Elevated",
                           message: "Albums, artists, playlists and a gorgeous now-playing screen are tuning up.")
                .navigationTitle("Music")
        }
    }
}

struct AudiobooksView: View {
    var body: some View {
        NavigationStack {
            ComingSoonView(symbol: "headphones",
                           title: "Your Bookshelf",
                           message: "Chapters, sleep timers, playback speed and progress for every story — on the way.")
                .navigationTitle("Audiobooks")
        }
    }
}
