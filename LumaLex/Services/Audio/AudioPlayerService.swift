import AVFoundation
import MediaPlayer
import SwiftData
import SwiftUI

@MainActor
final class AudioPlayerService: ObservableObject {
    @Published private(set) var documentID: UUID?
    @Published private(set) var title = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var playbackMode = PlaybackMode(rawValue: UserDefaults.standard.string(forKey: "playbackMode") ?? "") ?? .sequential {
        didSet { UserDefaults.standard.set(playbackMode.rawValue, forKey: "playbackMode") }
    }
    @Published var repeatSentences = UserDefaults.standard.bool(forKey: "repeatSentences") {
        didSet {
            UserDefaults.standard.set(repeatSentences, forKey: "repeatSentences")
            configureSentenceRepeat(restartSentence: repeatSentences)
        }
    }
    private var sentenceRepeat = SentenceRepeatState()
    private var seekGeneration = 0
    private var isSeeking = false
    private var modelContext: ModelContext?
    private var currentDocument: AudioDocument?
    private var lastCheckpoint = -1

    func configurePersistence(in context: ModelContext) { modelContext = context }

    func saveProgress() {
        guard let currentDocument else { return }
        currentDocument.lastPlaybackTime = currentTime
        currentDocument.lastPlayedAt = .now
        UserDefaults.standard.set(currentDocument.id.uuidString, forKey: "lastAudioDocumentID")
        try? modelContext?.save()
    }

    func restoreLastDocument() {
        guard documentID == nil else { return }
        let stored = UserDefaults.standard.string(forKey: "lastAudioDocumentID").flatMap { UUID(uuidString: $0) }
        let document = queue.first { $0.id == stored } ?? queue.filter { $0.lastPlayedAt != nil }
            .max { ($0.lastPlayedAt ?? .distantPast) < ($1.lastPlayedAt ?? .distantPast) }
        if let document { load(document) }
    }
    @Published var rate: Float = 1 {
        didSet { if isPlaying { player?.rate = rate }; updateNowPlaying() }
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var queue: [AudioDocument] = []
    private var subtitles: [ParsedSubtitle] = []
    private var lastSubtitleIndex: Int?
    private var lastMetadataSubtitleIndex: Int?
    private let liveActivity = LiveActivityCoordinator()

    init() {
        configureRemoteCommands()
    }

    func setQueue(_ documents: [AudioDocument]) {
        queue = documents
    }

    func load(_ document: AudioDocument, startAt position: TimeInterval? = nil) {
        if documentID == document.id { return }
        stop()
        let url = AudioStorage.url(for: document.localRelativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { return }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        documentID = document.id
        currentDocument = document
        lastCheckpoint = -1
        title = document.title
        duration = document.duration
        seek(to: position ?? document.lastPlaybackTime)
        if let modelContext {
            let transcripts = (try? modelContext.fetch(FetchDescriptor<Transcript>())) ?? []
            if let transcript = transcripts.filter({ $0.audioDocumentID == document.id }).max(by: { $0.createdAt < $1.createdAt }) {
                let segments = (try? modelContext.fetch(FetchDescriptor<SubtitleSegment>())) ?? []
                setSubtitles(segments.filter { $0.transcriptID == transcript.id }.sorted { $0.startTime < $1.startTime })
            }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard time.seconds.isFinite else { return }
                guard self?.documentID == document.id, self?.isSeeking == false else { return }
                self?.currentTime = time.seconds
                if let self, self.isPlaying {
                    let checkpoint = Int(time.seconds / 5)
                    if checkpoint != self.lastCheckpoint {
                        self.lastCheckpoint = checkpoint
                        self.saveProgress()
                    }
                }
                self?.updateSubtitleActivity()
            }
        }
        let endingDocumentID = document.id
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.documentID == endingDocumentID else { return }
                self?.handlePlaybackEnded()
            }
        }
        updateNowPlaying()
    }

    private func handlePlaybackEnded() {
        guard isPlaying, let documentID else { return }
        guard !isSeeking else { return }
        if repeatSentences, let index = sentenceRepeat.index, subtitles.indices.contains(index) {
            let endedAt = min(subtitles[index].end, duration)
            if let target = sentenceRepeat.advance(subtitles: subtitles) {
                applySentenceEnd()
                seekPrecisely(to: target)
                return
            }
            applySentenceEnd()
            if endedAt < duration - 0.05 {
                seekPrecisely(to: endedAt)
                return
            }
        }
        if playbackMode == .repeatOne { restartCurrentArticle(); return }
        let available = queue.filter { FileManager.default.fileExists(atPath: AudioStorage.url(for: $0.localRelativePath).path) }
        if let index = available.firstIndex(where: { $0.id == documentID }),
           let nextIndex = playbackMode.nextIndex(after: index, count: available.count) {
            let next = available[nextIndex]
            if next.id == documentID { restartCurrentArticle(); return }
            load(next, startAt: 0)
            togglePlayback()
        } else {
            player?.pause()
            isPlaying = false
            currentTime = duration
            saveProgress()
            updateNowPlaying()
            liveActivity.end()
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            if duration > 0 && currentTime >= duration - 0.25 { seek(to: 0) }
            player.rate = rate
        }
        isPlaying.toggle()
        saveProgress()
        updateNowPlaying()
        updateSubtitleActivity(force: true)
    }

    func seek(to seconds: TimeInterval) {
        let bounded = min(max(0, seconds), duration)
        sentenceRepeat.reset(at: bounded, subtitles: subtitles)
        applySentenceEnd()
        seekPrecisely(to: bounded)
    }

    func skip(_ seconds: TimeInterval) { seek(to: currentTime + seconds) }

    func stop() {
        seekGeneration += 1
        isSeeking = false
        sentenceRepeat = SentenceRepeatState()
        saveProgress()
        currentDocument = nil
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
        documentID = nil
        isPlaying = false
        currentTime = 0
        subtitles = []
        lastSubtitleIndex = nil
        lastMetadataSubtitleIndex = nil
        liveActivity.end()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func setSubtitles(_ segments: [SubtitleSegment]) {
        let parsed = segments.map { ParsedSubtitle(start: $0.startTime, end: $0.endTime,
                                                   english: $0.english, chinese: $0.chinese) }
        guard parsed != subtitles else { return }
        subtitles = parsed
        configureSentenceRepeat(restartSentence: false)
        lastSubtitleIndex = nil
        lastMetadataSubtitleIndex = nil
        updateSubtitleActivity()
    }

    private func restartCurrentArticle() {
        seek(to: 0)
    }

    private func configureSentenceRepeat(restartSentence: Bool) {
        sentenceRepeat.reset(at: currentTime, subtitles: subtitles)
        applySentenceEnd()
        if restartSentence, let index = sentenceRepeat.index {
            seekPrecisely(to: subtitles[index].start)
        }
    }

    private func applySentenceEnd() {
        guard let item = player?.currentItem else { return }
        if repeatSentences, let index = sentenceRepeat.index, subtitles.indices.contains(index) {
            item.forwardPlaybackEndTime = CMTime(seconds: min(subtitles[index].end, duration), preferredTimescale: 600)
        } else { item.forwardPlaybackEndTime = .invalid }
    }

    private func seekPrecisely(to target: TimeInterval) {
        guard let player else { return }
        let bounded = min(max(0, target), duration)
        seekGeneration += 1
        let generation = seekGeneration
        isSeeking = true
        currentTime = bounded
        saveProgress()
        updateSubtitleActivity(force: true)
        player.seek(to: CMTime(seconds: bounded, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
            Task { @MainActor in
                guard let self, self.seekGeneration == generation else { return }
                self.isSeeking = false
                if completed, self.isPlaying { self.player?.rate = self.rate }
                self.updateNowPlaying()
            }
        }
    }

    func refreshLockScreenPresentation() {
        updateNowPlaying()
        if UserDefaults.standard.bool(forKey: "lockScreenSubtitles") {
            lastSubtitleIndex = nil
            updateSubtitleActivity(force: true)
        } else {
            liveActivity.end()
        }
    }

    private func updateSubtitleActivity(force: Bool = false) {
        let active = TranscriptParser.activeIndex(at: currentTime, in: subtitles)
        if active != lastMetadataSubtitleIndex || force {
            lastMetadataSubtitleIndex = active
            updateNowPlaying()
        }
        guard let index = active,
              index != lastSubtitleIndex || force else { return }
        let segment = subtitles[index]
        if liveActivity.update(title: title, english: segment.english, chinese: segment.chinese,
                               elapsed: currentTime, isPlaying: isPlaying) {
            lastSubtitleIndex = index
        }
    }

    private func updateNowPlaying() {
        guard documentID != nil else { return }
        let active = TranscriptParser.activeIndex(at: currentTime, in: subtitles)
        let subtitle = active.map { subtitles[$0] }
        let showSubtitles = UserDefaults.standard.bool(forKey: "lockScreenSubtitles")
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0
        ]
        if showSubtitles, let subtitle {
            info[MPMediaItemPropertyTitle] = subtitle.english.isEmpty ? title : subtitle.english
            info[MPMediaItemPropertyArtist] = subtitle.chinese
            info[MPMediaItemPropertyAlbumTitle] = title
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == false { self?.togglePlayback() } }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == true { self?.togglePlayback() } }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(15) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(-15) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }
}
