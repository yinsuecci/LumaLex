import SwiftData
import SwiftUI

struct AppRouter: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var player: AudioPlayerService
    @State private var showingPlayer = false
    @State private var setupError: String?

    var body: some View {
        mainTabs
        .task {
            do { try DemoContentSeeder.seedIfNeeded(in: modelContext) }
            catch { setupError = error.localizedDescription }
        }
        .alert("Demo Setup Failed", isPresented: Binding(get: { setupError != nil },
                                                           set: { if !$0 { setupError = nil } })) {
            Button("OK", role: .cancel) { setupError = nil }
        } message: { Text(setupError ?? "") }
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
