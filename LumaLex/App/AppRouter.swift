import SwiftData
import SwiftUI

struct AppRouter: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var player: AudioPlayerService
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingPlayer = false
    @State private var setupError: String?
    @State private var importingBatch = false

    var body: some View {
        mainTabs
        .task {
            do { try DemoContentSeeder.seedIfNeeded(in: modelContext) }
            catch { setupError = error.localizedDescription }
            await importBatch()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await importBatch() } }
        }
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
