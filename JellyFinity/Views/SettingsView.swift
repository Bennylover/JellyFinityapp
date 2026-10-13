import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DownloadManager.convertKey) private var convertDownloads = true
    @AppStorage(JellyfinClient.bitrateKey) private var maxBitrate = JellyfinClient.defaultBitrateMbps
    @AppStorage("jl.theme") private var themeRaw = AppTheme.aurora.rawValue
    @AppStorage("jl.appearance") private var appearanceRaw = AppearanceMode.system.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    ForEach(AppTheme.allCases) { option in
                        ThemeRow(option: option, isSelected: option.rawValue == themeRaw) {
                            withAnimation(.easeInOut) { themeRaw = option.rawValue }
                        }
                    }
                }
                Section("Appearance") {
                    Picker("Mode", selection: $appearanceRaw) {
                        ForEach(AppearanceMode.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
                TMDBKeySection()
                Section {
                    Picker("Maximum bitrate", selection: $maxBitrate) {
                        ForEach([8, 20, 40, 60, 80, 120, 200], id: \.self) { Text("\($0) Mbps").tag($0) }
                    }
                } header: {
                    Text("Video Quality")
                } footer: {
                    Text("Higher values keep more detail but need a faster connection. Lower it if videos buffer on cellular. Applies to the next video you start.")
                }
                Section {
                    Toggle("Convert for iPhone", isOn: $convertDownloads)
                } header: {
                    Text("Downloads")
                } footer: {
                    Text("When a file wouldn't play on iPhone (like MKV), your server converts it to MP4 or MP3 while it downloads. Conversion uses your server's processing power and can take a while.")
                }
                accountSection
            }
            .scrollContentBackground(.hidden)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var accountSection: some View {
        Section("Server") {
            if let s = session.session {
                LabeledContent("Server", value: s.serverName)
                LabeledContent("Signed in as", value: s.userName)
                LabeledContent("Address", value: s.serverURL.host() ?? s.serverURL.absoluteString)
                Button("Sign Out", role: .destructive) { session.signOut() }
            } else {
                LabeledContent("Library", value: "Demo")
                Button("Connect Your Server") { session.signOut() }
            }
        }
    }
}

private struct ThemeRow: View {
    let option: AppTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(option.gradient)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name).font(.headline).foregroundStyle(.primary)
                    Text(option.tagline).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? option.accent : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
