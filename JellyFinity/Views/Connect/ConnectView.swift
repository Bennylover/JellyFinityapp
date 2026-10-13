import SwiftUI

struct ConnectView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.appTheme) private var theme

    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var foundServer: (url: URL, name: String, version: String?)?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focused: Field?

    enum Field { case address, username, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                brand
                formCard
                demoButton
                Text("Your password is sent only to your server. Access tokens are kept safely in your iPhone's Keychain.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(ConnectBackground())
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: foundServer?.url)
    }

    private var brand: some View {
        VStack(spacing: 14) {
            Image("JellyLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: Color.blue.opacity(0.45), radius: 24, y: 12)
                .accessibilityHidden(true)
            Text("JellyFinity")
                .font(.largeTitle.weight(.bold))
            Text("Movies, music and audiobooks —\nbeautifully yours.")
                .font(.headline.weight(.regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(foundServer == nil ? "Connect to your server" : "Sign in")
                .font(.title3.weight(.bold))
            if let server = foundServer {
                serverBadge(server.name, version: server.version)
                credentialFields
            } else {
                field("Server address", text: $address, icon: "server.rack", field: .address)
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit { Task { await findServer() } }
                Text("e.g. 192.168.1.20:8096 or https://media.example.com")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
            }
            primaryButton
        }
        .padding(22)
        .cardSurface(radius: 28)
    }

    private var credentialFields: some View {
        VStack(spacing: 12) {
            field("Username", text: $username, icon: "person.fill", field: .username)
                .textContentType(.username)
                .submitLabel(.next)
                .onSubmit { focused = .password }
            HStack(spacing: 12) {
                Image(systemName: "lock.fill").foregroundStyle(theme.accent).frame(width: 22)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await signIn() } }
            }
            .padding(14)
            .background(theme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func field(_ title: String, text: Binding<String>, icon: String, field: Field) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(theme.accent).frame(width: 22)
            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: field)
        }
        .padding(14)
        .background(theme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func serverBadge(_ name: String, version: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(version.map { "Jellyfin \($0)" } ?? "Jellyfin server")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Change") {
                foundServer = nil
                errorMessage = nil
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var primaryButton: some View {
        let title = foundServer == nil ? "Continue" : "Sign In"
        let disabled = isWorking || (foundServer == nil ? address.isEmpty : username.isEmpty)
        return Button {
            Task {
                if foundServer == nil { await findServer() } else { await signIn() }
            }
        } label: {
            HStack {
                if isWorking { ProgressView().tint(.white) }
                Text(title).font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(theme.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(disabled ? 0.5 : 1)
        }
        .disabled(disabled)
    }

    private var demoButton: some View {
        Button {
            session.startDemo()
        } label: {
            Label("Explore the demo library", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(theme.surface.opacity(0.8), in: Capsule())
        }
    }

    // MARK: - Actions

    private func findServer() async {
        guard !address.isEmpty, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let (url, info) = try await JellyfinClient.discover(address: address, deviceId: session.deviceId)
            foundServer = (url, info.serverName ?? url.host() ?? "Jellyfin", info.version)
            focused = .username
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func signIn() async {
        guard let server = foundServer, !username.isEmpty, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await session.signIn(serverURL: server.url, serverName: server.name,
                                     username: username, password: password)
            password = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ConnectBackground: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            theme.background
            Circle()
                .fill(theme.accent.opacity(0.28))
                .frame(width: 360)
                .blur(radius: 90)
                .offset(x: -120, y: -260)
            Circle()
                .fill(theme.secondary.opacity(0.22))
                .frame(width: 320)
                .blur(radius: 90)
                .offset(x: 140, y: 280)
        }
        .ignoresSafeArea()
    }
}
