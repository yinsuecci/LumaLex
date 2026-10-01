import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var player: AudioPlayerService
    @Query private var profiles: [UserProfile]
    @Query private var audio: [AudioDocument]
    @Query private var transcripts: [Transcript]
    @Query private var segments: [SubtitleSegment]
    @Query private var vocabulary: [VocabularyItem]
    @Query private var known: [KnownExpression]
    @Query private var reviews: [ReviewRecord]
    @AppStorage("backendURL") private var backendURL = ""
    @AppStorage("lockScreenSubtitles") private var lockScreenSubtitles = false
    @State private var backendToken = ""
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Vocabulary") {
                NavigationLink("Known Words") { KnownExpressionsView() }
            }
            Section("Offline Dictionary") {
                Text("ECDICT · 50,000 entries")
                Text("Dictionary definitions are general meanings, not AI-selected meanings in context.")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink("Dictionary License") {
                    ScrollView {
                        Text(dictionaryLicense).font(.footnote).padding()
                    }
                    .navigationTitle("ECDICT License")
                }
            }
            Section("Optional AI Server") {
                TextField("https://api.example.com", text: $backendURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                SecureField("Access token", text: $backendToken)
                Button("Save Access Token") { BackendConfiguration.token = backendToken }
                Text("The server receives only content you choose to explain, translate, or transcribe. Audio and transcripts remain local otherwise.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Toggle("Show subtitles on Lock Screen", isOn: $lockScreenSubtitles)
                Text("When enabled, the current sentence may appear in a Live Activity while audio plays.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Delete All Local Data", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle("Profile")
        .onAppear { backendToken = BackendConfiguration.token ?? "" }
        .onChange(of: lockScreenSubtitles) { _, _ in player.refreshLockScreenPresentation() }
        .confirmationDialog("Delete all audio, transcripts, known words, vocabulary, and review history?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) { deleteAll() }
        }
        .alert("Could Not Delete Data", isPresented: Binding(get: { errorMessage != nil },
                                                              set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func deleteAll() {
        let paths = audio.map(\.localRelativePath)
        player.stop()
        for item in reviews { modelContext.delete(item) }
        for item in vocabulary { modelContext.delete(item) }
        for item in known { modelContext.delete(item) }
        for item in segments { modelContext.delete(item) }
        for item in transcripts { modelContext.delete(item) }
        for item in audio { modelContext.delete(item) }
        for item in profiles { modelContext.delete(item) }
        do {
            try modelContext.save()
            for path in paths { try? FileManager.default.removeItem(at: AudioStorage.url(for: path)) }
            backendURL = ""
            backendToken = ""
            lockScreenSubtitles = false
            UserDefaults.standard.set(false, forKey: "didSeedDemo")
            BackendConfiguration.token = nil
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private var dictionaryLicense: String {
        guard let url = Bundle.main.url(forResource: "ECDICT-LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "License unavailable" }
        return text
    }
}
