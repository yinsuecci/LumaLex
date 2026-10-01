import AVKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum SubtitleMode: String, CaseIterable, Identifiable {
    case bilingual = "Bilingual"
    case english = "English"
    case difficult = "Difficult Words"
    case focus = "Focus"
    var id: Self { self }
}

struct PlayerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var player: AudioPlayerService
    @Query private var documents: [AudioDocument]
    @Query private var transcripts: [Transcript]
    @Query private var allSegments: [SubtitleSegment]
    @Query private var profiles: [UserProfile]
    @Query private var vocabulary: [VocabularyItem]
    @Query private var markedKnown: [KnownExpression]
    @State private var mode: SubtitleMode = .bilingual
    @State private var following = true
    @State private var importingTranscript = false
    @State private var transcribing = false
    @State private var translating = false
    @State private var confirmRemoteTranscription = false
    @State private var confirmTranslation = false
    @State private var errorMessage: String?
    @State private var vocabularyMessage: String?
    @State private var savedSegments: [SubtitleSegment]?
    @State private var importMessage: String?
    let documentID: UUID

    private var document: AudioDocument? { documents.first { $0.id == documentID } }
    private var transcript: Transcript? {
        transcripts.filter { $0.audioDocumentID == documentID }.max { $0.createdAt < $1.createdAt }
    }
    private var segments: [SubtitleSegment] {
        if let savedSegments { return savedSegments }
        guard let transcript else { return [] }
        return allSegments.filter { $0.transcriptID == transcript.id }.sorted { $0.startTime < $1.startTime }
    }
    private var activeIndex: Int? { SubtitleLookup.activeIndex(at: player.currentTime, in: segments) }
    private var difficultyContext: DifficultyContext {
        DifficultyContext(cefr: profiles.first?.cefrLevel ?? .b1,
                          estimatedVocabulary: profiles.first?.estimatedVocabulary ?? 3000,
                          knownLemmas: Set(vocabulary.filter { $0.status == .learned }.map { $0.lemma.lowercased() })
                            .union(markedKnown.map(\.lemma)))
    }

    var body: some View {
        VStack(spacing: 16) {
            if let document {
                Text(document.title).font(.title2.bold()).multilineTextAlignment(.center)
            }
            if let vocabularyMessage {
                Text(vocabularyMessage).font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel(vocabularyMessage)
            }

            if mode == .focus {
                Spacer()
                Image(systemName: "waveform")
                    .font(.system(size: 64, weight: .ultraLight))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Spacer()
            } else if segments.isEmpty {
                VStack(spacing: 16) {
                    ContentUnavailableView("No Subtitles", systemImage: "text.alignleft",
                                           description: Text("Import a timed SRT or VTT file for this audio. Bilingual files display immediately."))
                    Button("Import Timed Subtitles", systemImage: "text.badge.plus") {
                        importingTranscript = true
                    }
                    .buttonStyle(.borderedProminent)
                    if transcribing {
                        ProgressView("Transcribing on device")
                    } else {
                        Button("Generate English Instead") { generateTranscript() }
                        if BackendConfiguration.baseURL != nil {
                            Button("Transcribe with Server") { confirmRemoteTranscription = true }
                        }
                    }
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(segments.indices, id: \.self) { index in
                                SubtitleRow(segment: segments[index], mode: mode,
                                            isActive: index == activeIndex,
                                            difficultyContext: difficultyContext,
                                            savedPhrases: Set(vocabulary.filter { $0.lemma.contains(" ") }
                                                .map { $0.lemma.lowercased() }),
                                            savedLemmas: Set(vocabulary.map {
                                                OfflineDictionary.shared.lemma(for: $0.lemma)
                                            })) { word in
                                    addWord(word, from: segments[index])
                                }
                                .id(index)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in following = false })
                    .task(id: segments.map(\.id)) {
                        if following, let activeIndex {
                            proxy.scrollTo(activeIndex, anchor: .center)
                        }
                    }
                    .onChange(of: activeIndex) { _, index in
                        if following, let index {
                            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(index, anchor: .center) }
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !following {
                            Button("Follow Playback", systemImage: "arrow.down.to.line") {
                                following = true
                                if let activeIndex { proxy.scrollTo(activeIndex, anchor: .center) }
                            }
                            .buttonStyle(.borderedProminent)
                            .padding()
                        }
                    }
                }
            }

            controls
        }
        .padding(.top)
        .navigationTitle("Player")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Import Subtitles", systemImage: "text.badge.plus") { importingTranscript = true }
            if !segments.isEmpty {
                Button("Retranscribe", systemImage: "waveform.badge.mic") { generateTranscript() }
                    .disabled(transcribing)
                Button("Translate", systemImage: "character.book.closed") { confirmTranslation = true }
                    .disabled(translating || BackendConfiguration.baseURL == nil)
            }
        }
        .confirmationDialog("Send this audio to your configured server for transcription?",
                            isPresented: $confirmRemoteTranscription, titleVisibility: .visible) {
            Button("Send Audio") { remoteTranscribe() }
        } message: {
            Text("The server forwards audio to its speech provider. Avoid sending private audio unless you trust the server.")
        }
        .confirmationDialog("Send English subtitle text to your configured server for translation?",
                            isPresented: $confirmTranslation, titleVisibility: .visible) {
            Button("Send Text") { translate() }
        } message: {
            Text("The server forwards subtitle text to its translation provider.")
        }
        .fileImporter(isPresented: $importingTranscript,
                      allowedContentTypes: [.plainText, UTType(filenameExtension: "srt") ?? .plainText,
                                            UTType(filenameExtension: "vtt") ?? .plainText]) { result in
            switch result {
            case .success(let url): importTranscript(url)
            case .failure(let error):
                let value = error as NSError
                if value.domain != NSCocoaErrorDomain || value.code != NSUserCancelledError {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .alert("Could Not Complete Action", isPresented: Binding(get: { errorMessage != nil },
                                                                 set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .alert("Subtitles Imported", isPresented: Binding(get: { importMessage != nil },
                                                          set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) { importMessage = nil }
        } message: { Text(importMessage ?? "") }
        .onAppear {
            if let document { player.load(document) }
            player.setSubtitles(segments)
        }
        .onChange(of: segments.map(\.id)) { _, _ in player.setSubtitles(segments) }
        .onChange(of: Int(player.currentTime / 5)) { _, _ in
            if player.documentID == documentID, let document {
                document.lastPlaybackTime = player.currentTime
                document.lastPlayedAt = .now
                try? modelContext.save()
            }
        }
        .onDisappear {
            if player.documentID == documentID, let document {
                document.lastPlaybackTime = player.currentTime
                document.lastPlayedAt = .now
                try? modelContext.save()
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Picker("Subtitle Mode", selection: $mode) {
                ForEach(SubtitleMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)

            Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                   in: 0...max(player.duration, 1))
            HStack {
                Text(time(player.currentTime))
                Spacer()
                Text(time(player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            HStack(spacing: 28) {
                Button("Back 15 seconds", systemImage: "gobackward.15") { player.skip(-15) }
                Button(player.isPlaying ? "Pause" : "Play",
                       systemImage: player.isPlaying ? "pause.fill" : "play.fill") { player.togglePlayback() }
                    .font(.title)
                Button("Forward 15 seconds", systemImage: "goforward.15") { player.skip(15) }
            }
            .labelStyle(.iconOnly)
            HStack {
                Menu("Speed: \(player.rate.formatted())×") {
                    ForEach([Float(0.75), 1, 1.25, 1.5, 2], id: \.self) { speed in
                        Button("\(speed.formatted())×") { player.rate = speed }
                    }
                }
                Spacer()
                AirPlayButton().frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func time(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    private func addWord(_ word: String, from segment: SubtitleSegment) {
        let dictionary = OfflineDictionary.shared
        let lemma = dictionary.lemma(for: word)
        do {
            let existing = try modelContext.fetch(FetchDescriptor<VocabularyItem>())
            guard !existing.contains(where: { dictionary.lemma(for: $0.lemma) == lemma }) else {
                vocabularyMessage = "Already saved: \(word)"
                return
            }
            let entry = dictionary.lookup(word)
            let state = ReviewScheduler.initial(at: .now)
            let item = VocabularyItem(word: word, lemma: lemma,
                                      pronunciation: entry?.phonetic,
                                      partOfSpeech: entry?.pos,
                                      chineseMeaning: entry?.translation.replacingOccurrences(of: "\\n", with: "\n") ?? "暂无词典释义",
                                      englishDefinition: entry?.definition.replacingOccurrences(of: "\\n", with: "\n") ?? "",
                                      originalSentence: segment.english, sourceAudioID: documentID,
                                      reviewStage: state.stage, nextReviewDate: state.nextReviewDate)
            item.originalTranslation = segment.chinese
            item.originalStartTime = segment.startTime
            item.dictionarySource = entry == nil ? nil : "ECDICT (offline)"
            modelContext.insert(item)
            try modelContext.save()
            vocabularyMessage = entry == nil ? "Saved \(word); no offline entry" : "Saved: \(word)"
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            modelContext.rollback()
            vocabularyMessage = "Could not save: \(error.localizedDescription)"
        }
    }

    private func importTranscript(_ url: URL) {
        do {
            let text = try AudioStorage.readTranscript(from: url)
            let parsed = TranscriptParser.parse(text)
            guard !parsed.isEmpty else { throw TranscriptImportError.noTimedSegments }
            try saveTranscript(parsed, source: "imported")
            mode = .bilingual
            importMessage = "Imported \(parsed.count) timed subtitles for this audio."
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func generateTranscript() {
        guard let document else { return }
        transcribing = true
        Task {
            do {
                let parsed = try await OnDeviceTranscriptionService().transcribe(
                    AudioStorage.url(for: document.localRelativePath)
                )
                try saveTranscript(parsed, source: "on-device")
            } catch {
                modelContext.rollback()
                errorMessage = error.localizedDescription
            }
            transcribing = false
        }
    }

    private func remoteTranscribe() {
        guard let document else { return }
        transcribing = true
        Task {
            do {
                let parsed = try await BackendTranscriptionService().transcribe(
                    AudioStorage.url(for: document.localRelativePath)
                )
                try saveTranscript(parsed, source: "server")
            } catch {
                modelContext.rollback()
                errorMessage = error.localizedDescription
            }
            transcribing = false
        }
    }

    private func translate() {
        let untranslated = segments.filter { !$0.english.isEmpty && $0.chinese.isEmpty }
        guard !untranslated.isEmpty else { return }
        translating = true
        Task {
            do {
                let values = try await BackendTranslationService().translate(untranslated.map(\.english))
                for (segment, value) in zip(untranslated, values) { segment.chinese = value }
                try modelContext.save()
                player.setSubtitles(segments)
            } catch {
                modelContext.rollback()
                errorMessage = error.localizedDescription
            }
            translating = false
        }
    }

    private func saveTranscript(_ parsed: [ParsedSubtitle], source: String) throws {
        let transcript = Transcript(audioDocumentID: documentID, source: source)
        modelContext.insert(transcript)
        var inserted: [SubtitleSegment] = []
        for item in parsed {
            let segment = SubtitleSegment(transcriptID: transcript.id, startTime: item.start,
                                                endTime: item.end, english: item.english,
                                                chinese: item.chinese,
                                                tokens: item.english.split(separator: " ").map(String.init))
            modelContext.insert(segment)
            inserted.append(segment)
        }
        try modelContext.save()
        savedSegments = inserted.sorted { $0.startTime < $1.startTime }
        player.setSubtitles(savedSegments ?? [])
        following = true
    }
}

private enum TranscriptImportError: LocalizedError {
    case noTimedSegments
    var errorDescription: String? { "No valid timestamped subtitles were found. Use SRT or VTT." }
}

private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { AVRoutePickerView() }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
