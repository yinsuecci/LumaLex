import AVFoundation
import MediaPlayer
import SwiftUI

@MainActor
final class AudioPlayerService: ObservableObject {
    @Published private(set) var documentID: UUID?
    @Published private(set) var title = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
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
        title = document.title
        duration = document.duration
        seek(to: position ?? document.lastPlaybackTime)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard time.seconds.isFinite else { return }
                self?.currentTime = time.seconds
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
        if let index = queue.firstIndex(where: { $0.id == documentID }),
           let next = queue.dropFirst(index + 1).first(where: {
               FileManager.default.fileExists(atPath: AudioStorage.url(for: $0.localRelativePath).path)
           }) {
            load(next, startAt: 0)
            togglePlayback()
        } else {
            player?.pause()
            isPlaying = false
            currentTime = duration
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
        updateNowPlaying()
        updateSubtitleActivity(force: true)
    }

    func seek(to seconds: TimeInterval) {
        let bounded = min(max(0, seconds), duration)
        player?.seek(to: CMTime(seconds: bounded, preferredTimescale: 600))
        currentTime = bounded
        updateNowPlaying()
        updateSubtitleActivity()
    }

    func skip(_ seconds: TimeInterval) { seek(to: currentTime + seconds) }

    func stop() {
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
        subtitles = segments.map { ParsedSubtitle(start: $0.startTime, end: $0.endTime,
                                                   english: $0.english, chinese: $0.chinese) }
        lastSubtitleIndex = nil
        lastMetadataSubtitleIndex = nil
        updateSubtitleActivity()
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
