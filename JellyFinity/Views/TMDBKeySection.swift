import SwiftUI

/// Settings section where the user pastes their own TMDB API key (stored in the Keychain, never in the app).
struct TMDBKeySection: View {
    @State private var draft = ""
    @State private var isConnected = TMDBClient.hasKey
    @State private var showError = false

    var body: some View {
        Section {
            if isConnected {
                Label("Connected", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                Button("Remove Key", role: .destructive) {
                    KeychainStore.delete(account: TMDBClient.keyAccount)
                    isConnected = false
                }
            } else {
                SecureField("TMDB API key or read token", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                Button("Save Key", action: save).disabled(draft.isEmpty)
                if showError {
                    Text("That doesn't look like a valid TMDB key.").font(.footnote).foregroundStyle(.red)
                }
            }
            if let url = URL(string: "https://www.themoviedb.org/settings/api") {
                Link("Get a free key at themoviedb.org", destination: url)
            }
        } header: {
            Text("Cast Info (TMDB)")
        } footer: {
            Text("Add your own free TMDB key to show cast and crew with photos on movie and show pages. Without one, JellyFinity falls back to IMDb and then your server.")
        }
    }

    private func save() {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TMDBClient.isValid(key), KeychainStore.save(key, account: TMDBClient.keyAccount) else {
            showError = true
            return
        }
        draft = ""
        showError = false
        isConnected = true
    }
}
