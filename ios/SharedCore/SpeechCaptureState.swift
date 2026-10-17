import Foundation

/// A recognition result may describe only the current part of a longer request.
/// Keep earlier parts while allowing the recognizer to revise its current phrase.
struct SpeechTranscriptAssembler {
    private(set) var committedText = ""
    private(set) var currentPhrase = ""
    private var taskBaseText = ""
    private var earliestTaskStart: TimeInterval?
    private var currentStart: TimeInterval?
    private var currentEnd: TimeInterval?

    var transcript: String {
        [committedText, currentPhrase].filter { !$0.isEmpty }.joined(separator: " ")
    }

    @discardableResult
    mutating func observe(_ text: String, start: TimeInterval?, end: TimeInterval?, isFinal: Bool) -> String {
        let incoming = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incoming.isEmpty else { return transcript }
        if earliestTaskStart == nil { earliestTaskStart = start }

        // A final result can contain the whole request after partial results
        // supplied separate pieces. Prefer that final wording once, not those
        // pieces followed by a duplicate copy of the same speech.
        if isFinal, let start, let earliestTaskStart, start <= earliestTaskStart + 0.25 {
            committedText = taskBaseText
            currentPhrase = incoming
            commitCurrentPhrase()
            taskBaseText = committedText
            self.earliestTaskStart = nil
            return transcript
        }

        if currentPhrase.isEmpty {
            currentPhrase = incoming
        } else {
            let oldWords = words(in: currentPhrase)
            let newWords = words(in: incoming)
            let sharedStart = zip(oldWords, newWords).prefix { $0.0 == $0.1 }.count
            let overlap = suffixPrefixOverlap(oldWords, newWords)
            let hasTiming = start != nil && currentStart != nil
            let startedLater = start.flatMap { newStart in
                currentStart.map { newStart > $0 + 0.75 }
            } ?? false
            let laterAudio = start.flatMap { newStart in
                currentEnd.map { newStart >= $0 - 0.15 }
            } ?? false

            // Apple's partial results can move their first timestamp forward as
            // the hypothesis grows. A textual prefix still describes the same
            // phrase, even when its timings look like later audio.
            if !oldWords.isEmpty, sharedStart == oldWords.count,
               newWords.count >= oldWords.count {
                currentPhrase = incoming
            } else if !newWords.isEmpty, sharedStart == newWords.count,
                      oldWords.count > newWords.count, !isFinal {
                // Do not replace a longer partial with a temporary regression.
            } else if (laterAudio && sharedStart < 2 && overlap < 2)
                        || (sharedStart < 2 && overlap < 2 && oldWords.count >= 2
                            && (!hasTiming || startedLater)) {
                commitCurrentPhrase()
                currentPhrase = incoming
            } else if sharedStart >= 2 {
                currentPhrase = incoming
            } else if overlap >= 2 {
                let additional = incoming.split(whereSeparator: \.isWhitespace).dropFirst(overlap).joined(separator: " ")
                if !additional.isEmpty { currentPhrase += " " + additional }
            } else if newWords.count > 1 || currentPhrase.isEmpty {
                // A one-word replacement is too weak to erase an earlier phrase.
                currentPhrase = incoming
            }
        }

        if let start { currentStart = min(currentStart ?? start, start) }
        currentEnd = end ?? currentEnd
        if isFinal {
            commitCurrentPhrase()
            taskBaseText = committedText
            earliestTaskStart = nil
        }
        return transcript
    }

    mutating func finishTask() {
        commitCurrentPhrase()
        taskBaseText = committedText
        earliestTaskStart = nil
    }

    private mutating func commitCurrentPhrase() {
        guard !currentPhrase.isEmpty else { return }
        committedText = [committedText, currentPhrase].filter { !$0.isEmpty }.joined(separator: " ")
        currentPhrase = ""
        currentStart = nil
        currentEnd = nil
    }

    private func words(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
    }

    private func suffixPrefixOverlap(_ old: [String], _ new: [String]) -> Int {
        guard !old.isEmpty, !new.isEmpty else { return 0 }
        for count in stride(from: min(old.count, new.count), through: 1, by: -1) {
            if old.suffix(count).elementsEqual(new.prefix(count)) { return count }
        }
        return 0
    }
}

/// Measure quiet microphone intervals, not gaps between recognition callbacks.
struct MicrophonePauseTracker {
    private let audibleLevel: Float = 0.08
    private var hasHeardAudio = false
    private var quietStartedAt: TimeInterval?
    private(set) var longestSeconds = 0
    private(set) var longPauseCount = 0

    mutating func observe(level: Float, at uptime: TimeInterval) {
        if level >= audibleLevel {
            endQuietPeriod(at: uptime)
            hasHeardAudio = true
        } else if hasHeardAudio && quietStartedAt == nil {
            quietStartedAt = uptime
        }
    }

    mutating func stop(at uptime: TimeInterval) {
        endQuietPeriod(at: uptime)
    }

    mutating func resume() {
        hasHeardAudio = false
        quietStartedAt = nil
    }

    private mutating func endQuietPeriod(at uptime: TimeInterval) {
        defer { quietStartedAt = nil }
        guard let quietStartedAt else { return }
        let duration = max(0, uptime - quietStartedAt)
        guard duration >= 3 else { return }
        longestSeconds = max(longestSeconds, Int(duration.rounded(.down)))
        longPauseCount += 1
    }
}

/// SpeechAnalyzer revises audio ranges, rather than a cumulative request string.
/// Keep finalized segments and replace overlapping volatile guesses exactly once.
struct StreamingSpeechTranscript {
    private struct Segment {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
        let isFinal: Bool
    }
    private var segments: [Segment] = []
    var transcript: String { segments.map(\.text).joined(separator: " ") }

    mutating func observe(_ text: String, start: TimeInterval, end: TimeInterval, isFinal: Bool) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, start.isFinite, end.isFinite, end > start else { return transcript }
        // Late volatile guesses cannot overwrite finalized audio.
        if !isFinal, segments.contains(where: { $0.isFinal && $0.start < end && start < $0.end }) {
            return transcript
        }
        segments.removeAll { $0.start < end && start < $0.end }
        segments.append(Segment(start: start, end: end, text: text, isFinal: isFinal))
        segments.sort { $0.start < $1.start }
        return transcript
    }
}

/// Apple's contextual vocabulary accepts at most 100 short phrases. Long cue
/// descriptions bias dictation poorly; keywords and short names get priority.
enum SpeechVocabulary {
    static func phrases(keywords: [String], context: [String]) -> [String] {
        var seen: Set<String> = []
        return (keywords + context).compactMap { phrase in
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            let words = trimmed.split(whereSeparator: \.isWhitespace)
            guard (1...3).contains(words.count), trimmed.count <= 64,
                  seen.insert(trimmed.lowercased()).inserted else { return nil }
            return trimmed
        }.prefix(100).map { $0 }
    }
}
