import SwiftData
import SwiftUI

struct AppRouter: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var player: AudioPlayerService
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \AudioDocument.importedAt, order: .reverse) private var audio: [AudioDocument]
    @State private var showingPlayer = false
    @State private var setupError: String?
    @State private var importingBatch = false
    @State private var mediaReady = false

    var body: some View {
        mainTabs
        .task {
            do {
                try MediaCleanupService.clearExistingMediaOnce(in: modelContext)
                try DemoContentSeeder.seedIfNeeded(in: modelContext)
                mediaReady = true
                player.configurePersistence(in: modelContext)
                player.setQueue(audio)
                await importBatch()
                player.setQueue(try modelContext.fetch(FetchDescriptor<AudioDocument>(sortBy: [SortDescriptor(\AudioDocument.importedAt, order: .reverse)])))
                player.restoreLastDocument()
            } catch { setupError = error.localizedDescription }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player.saveProgress() }
            if phase == .active && mediaReady { Task { await importBatch() } }
        }
        .onChange(of: audio.map(\.id)) { _, _ in player.setQueue(audio) }
        .overlay {
            if importingBatch {
                ProgressView("Importing audio and subtitles…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .alert("Library Setup Failed", isPresented: Binding(get: { setupError != nil },
                                                           set: { if !$0 { setupError = nil } })) {
            Button("OK", role: .cancel) { setupError = nil }
        } message: { Text(setupError ?? "") }
    }

    private func importBatch() async {
        guard !importingBatch else { return }
        importingBatch = true
        defer { importingBatch = false }
        do { try await BatchImportService.run(in: modelContext) }
        catch { setupError = error.localizedDescription }
    }

    private var mainTabs: some View {
        TabView {
            NavigationStack {
                TodayView()
                    .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
            }
            .tabItem { Label("Today", systemImage: "sun.max") }

            NavigationStack {
                LibraryView()
                    .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }

            NavigationStack {
                VocabularyView()
                    .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
            }
            .tabItem { Label("Vocabulary", systemImage: "text.book.closed") }

            NavigationStack {
                ProfileView()
                    .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .sheet(isPresented: $showingPlayer) {
            if let id = player.documentID { PlayerView(documentID: id) }
        }
    }

    @ViewBuilder
    private var miniPlayer: some View {
        if player.documentID != nil {
            MiniPlayerView { showingPlayer = true }
        }
    }
}
