import Foundation

enum PlaybackMode: String, CaseIterable, Identifiable {
    case sequential, repeatOne, repeatAll
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sequential: return "Sequential"
        case .repeatOne: return "Repeat This Article"
        case .repeatAll: return "Repeat Library"
        }
    }
    func nextIndex(after index: Int, count: Int) -> Int? {
        guard count > 0, index >= 0, index < count else { return nil }
        if self == .repeatOne { return index }
        if index + 1 < count { return index + 1 }
        return self == .repeatAll ? 0 : nil
    }
}
