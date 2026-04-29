import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.ttsProvider) private var provider: TTSProvider = .iOSVoices

    var body: some View {
        NavigationStack {
            Form {
                Section("Voice") {
                    Picker("Provider", selection: $provider) {
                        ForEach(TTSProvider.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }

                    if provider == .elevenLabs {
                        NavigationLink("ElevenLabs Configuration") {
                            ElevenLabsSettingsView()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct ElevenLabsSettingsView: View {
    @State private var apiKey: String = Keychain.read(SettingsKey.elevenLabsAPIKey) ?? ""
    @State private var testStatus: TestStatus = .idle

    enum TestStatus: Equatable {
        case idle
        case testing
        case success(label: String)
        case failure(message: String)
    }

    var body: some View {
        Form {
            Section {
                SecureField("API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: apiKey) { _, newValue in
                        if newValue.isEmpty {
                            Keychain.delete(SettingsKey.elevenLabsAPIKey)
                        } else {
                            Keychain.write(SettingsKey.elevenLabsAPIKey, newValue)
                        }
                        testStatus = .idle
                    }
            } header: {
                Text("API key")
            } footer: {
                Text("Stored in the device Keychain.")
            }

            Section {
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Text("Test Connection")
                        if case .testing = testStatus {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(apiKey.isEmpty || testStatus == .testing)

                switch testStatus {
                case .idle, .testing:
                    EmptyView()
                case .success(let label):
                    Label(label, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failure(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("ElevenLabs")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func testConnection() async {
        testStatus = .testing
        guard let url = URL(string: "https://api.elevenlabs.io/v1/user") else {
            testStatus = .failure(message: "Bad URL.")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                testStatus = .failure(message: "No response.")
                return
            }
            switch http.statusCode {
            case 200:
                let label = parseSuccessLabel(data) ?? "Connected."
                testStatus = .success(label: label)
            case 401:
                testStatus = .failure(message: "Invalid API key.")
            default:
                testStatus = .failure(message: "Server returned \(http.statusCode).")
            }
        } catch {
            testStatus = .failure(message: error.localizedDescription)
        }
    }

    private func parseSuccessLabel(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let subscription = json["subscription"] as? [String: Any],
           let tier = subscription["tier"] as? String {
            return "Connected (tier: \(tier))."
        }
        return "Connected."
    }
}
