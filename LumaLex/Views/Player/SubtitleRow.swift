import SwiftUI

struct SubtitleRow: View {
    let segment: SubtitleSegment
    let mode: SubtitleMode
    let isActive: Bool
    let difficultyContext: DifficultyContext
    let savedPhrases: Set<String>
    let savedLemmas: Set<String>
    let toggleWord: (String) -> Void

    private static let difficulty = HeuristicVocabularyDifficultyService()
    private var words: [SubtitleToken] {
        SubtitleTokenizer.tokenize(segment.english, savedPhrases: savedPhrases)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 4) {
                let tokens = words
                ForEach(tokens.indices, id: \.self) { index in
                    let raw = tokens[index].display
                    let word = tokens[index].lookup
                    let saved = isSaved(word)
                    let highlighted = saved || (mode == .difficult &&
                        [VocabularyDifficulty.difficult, .specialized].contains(
                            Self.difficulty.classify(word, context: difficultyContext)))
                    Text(raw)
                        .font(.body)
                        .fontWeight(highlighted ? .semibold : .regular)
                        .foregroundStyle(highlighted ? Color.accentColor : .primary)
                        .padding(.horizontal, 2)
                        .background(saved ? Color.accentColor.opacity(0.14) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { if !word.isEmpty { toggleWord(word) } }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(Text(saved ? "Double-tap to remove from Vocabulary" :
                            "Double-tap to add to Vocabulary"))
                        .accessibilityAction(named: Text(saved ? "Remove from Vocabulary" : "Add to Vocabulary")) {
                            if !word.isEmpty { toggleWord(word) }
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
