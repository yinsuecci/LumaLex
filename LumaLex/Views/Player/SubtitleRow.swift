import SwiftUI

struct SubtitleRow: View {
    let segment: SubtitleSegment
    let mode: SubtitleMode
    let isActive: Bool
    let difficultyContext: DifficultyContext
    let savedPhrases: Set<String>
    let savedLemmas: Set<String>
    let selectWord: (String) -> Void

    private let difficulty = HeuristicVocabularyDifficultyService()
    private var words: [SubtitleToken] {
        SubtitleTokenizer.tokenize(segment.english, savedPhrases: savedPhrases)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 4) {
                ForEach(words.indices, id: \.self) { index in
                    let raw = words[index].display
                    let word = words[index].lookup
                        Text(raw)
                            .font(.body)
                            .fontWeight(emphasize(word) ? .semibold : .regular)
                            .foregroundStyle(emphasize(word) ? Color.accentColor : .primary)
                            .padding(.horizontal, 2)
                            .background(isSaved(word) ? Color.accentColor.opacity(0.14) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { if !word.isEmpty { selectWord(word) } }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("Double-tap to add to Vocabulary")
                            .accessibilityAction(named: "Add to Vocabulary") {
                                if !word.isEmpty { selectWord(word) }
                            }
                }
            }
            if mode == .bilingual, !segment.chinese.isEmpty {
                Text(segment.chinese).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .opacity(isActive ? 1 : 0.6)
        .accessibilityElement(children: .contain)
    }

    private func emphasize(_ word: String) -> Bool {
        isSaved(word) || (mode == .difficult && [VocabularyDifficulty.difficult, .specialized]
            .contains(difficulty.classify(word, context: difficultyContext)))
    }

    private func isSaved(_ word: String) -> Bool {
        savedLemmas.contains(OfflineDictionary.shared.lemma(for: word))
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: proposal.height),
                             subviews: subviews)
        for (view, point) in zip(subviews, result.points) {
            view.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return (CGSize(width: width, height: y + lineHeight), points)
    }
}
