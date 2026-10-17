import AVFAudio
import Foundation
import Speech

enum ListeningState: Equatable {
    case idle
    case requestingPermission
    case listening
    case unavailable
    case failed

    var label: String {
        switch self {
        case .idle: return "Ready"
        case .requestingPermission: return "Preparing"
        case .listening: return "Listening"
        case .unavailable: return "Speech unavailable"
        case .failed: return "Audio unavailable"
        }
    }
}

@MainActor
final class SpeechSession: NSObject, ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var scoringTranscript = ""
    @Published private(set) var state: ListeningState = .idle
    @Published private(set) var failureReason: String?
    @Published private(set) var confidence: Float?
    @Published private(set) var showsLowConfidenceWarning = false
    @Published private(set) var inputLevel: Float = 0

    private let scoringWindowLength = 16_000
    private let lowConfidenceThreshold: Float = 0.35
    private let lowConfidenceGracePeriod: TimeInterval = 3

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var smoothedConfidence: Float?
    private var lowConfidenceSince: Date?
    private var startGeneration = 0
    private var transcriptAssembler = SpeechTranscriptAssembler()
    private var rotationTask: Task<Void, Never>?
    private var hasInstalledTap = false
    private var streamingStop: (() -> Void)?
    private var streamingTranscript = StreamingSpeechTranscript()
    private var streamingBase = ""
    private var lastInputLevelUpdateUptime: TimeInterval = 0

    var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    var isScoringCompacted: Bool { transcript.count > scoringWindowLength }

    func start(
        mode: AnalysisPrivacyMode,
        locale: SpeechLocale = .englishUS,
        contextualStrings: [String] = [],
        mixesWithOtherAudio: Bool = false
    ) async {
        stop(deactivateAudioSession: !audioEngine.isRunning)
        startGeneration += 1
        let generation = startGeneration
        failureReason = nil
        confidence = nil
        showsLowConfidenceWarning = false
        scoringTranscript = String(transcript.suffix(scoringWindowLength))
        smoothedConfidence = nil
        lowConfidenceSince = nil
        guard !isSimulator else {
            state = .listening
            return
        }

        state = .requestingPermission
        guard await requestSpeechAuthorization() == .authorized,
              await requestMicrophoneAuthorization() else {
            guard generation == startGeneration else { return }
            state = .unavailable
            failureReason = "Microphone and speech permissions are required to transcribe this session."
            return
        }
        guard generation == startGeneration else { return }


        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Keep external speech playback audible during rehearsal recognition.
            // Other recording workflows retain the microphone-only category.
            let options: AVAudioSession.CategoryOptions = mixesWithOtherAudio
                ? [.mixWithOthers, .defaultToSpeaker]
                : []
            let category: AVAudioSession.Category = mixesWithOtherAudio ? .playAndRecord : .record
            // Video mode favors the camera-facing microphone. Nearby playback
            // and audio from another app need the normal microphone route.
            try audioSession.setCategory(category, mode: mixesWithOtherAudio ? .default : .videoRecording, options: options)
            try audioSession.setActive(true)

            // Prefer Apple's long-form, on-device engine when its assets are
            // already installed. Never download a model at rehearsal entry.
            if #available(iOS 26.0, *), SpeechTranscriber.isAvailable,
               let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale.rawValue)),
               await SpeechTranscriber.installedLocales.contains(supported) {
                guard generation == startGeneration else { return }
                do {
                    try await startStreaming(locale: supported, contextualStrings: contextualStrings, generation: generation)
                    return
                } catch {
                    guard generation == startGeneration else { return }
                    streamingStop?()
                    streamingStop = nil
                    transcriptAssembler = SpeechTranscriptAssembler()
                    _ = transcriptAssembler.observe(transcript, start: nil, end: nil, isFinal: true)
                    audioEngine.stop()
                    if hasInstalledTap {
                        audioEngine.inputNode.removeTap(onBus: 0)
                        hasInstalledTap = false
                    }
                    // Both backends honor the same privacy choice.
                }
            }
            guard generation == startGeneration else { return }
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale.rawValue)) else {
                stop()
                state = .unavailable
                failureReason = "Apple’s speech recognizer is unavailable on this device."
                return
            }
            if mode == .onDeviceOnly, !recognizer.supportsOnDeviceRecognition {
                stop()
                state = .unavailable
                failureReason = "On-device speech recognition is not available for this device or language. Recognition stopped without switching to network processing. Manual checklist controls remain available."
                return
            }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = mode == .onDeviceOnly
            request.taskHint = .dictation
            request.contextualStrings = SpeechVocabulary.phrases(keywords: contextualStrings, context: [])
            self.request = request

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                Task { @MainActor in
                    guard let self, generation == self.startGeneration else { return }
                    if let result {
                        let segments = result.bestTranscription.segments
                        // Partial hypotheses commonly contain zero-confidence
                        // segments despite recognized words. Zero means there is
                        // no usable quality estimate for this warning.
                        let recentConfidence = segments.suffix(6).map(\.confidence).filter { $0 > 0 }
                        if !recentConfidence.isEmpty {
                            let rawConfidence = recentConfidence.reduce(0, +) / Float(recentConfidence.count)
                            self.updateConfidence(rawConfidence)
                        }
                        if let text, !text.isEmpty {
                            let fullText = self.transcriptAssembler.observe(
                                text,
                                start: segments.first?.timestamp,
                                end: segments.last.map { $0.timestamp + $0.duration },
                                isFinal: result.isFinal
                            )
                            self.scoringTranscript = String(fullText.suffix(self.scoringWindowLength))
                            self.transcript = fullText
                        }
                    }
                    if error != nil {
                        self.stop()
                        self.state = .failed
                        self.failureReason = mode == .onDeviceOnly
                            ? "On-device speech recognition stopped. No network fallback was used. Retry listening or continue with manual controls."
                            : "Speech recognition stopped. Your live checklist remains available for manual updates."
                    }
                    if result?.isFinal == true, error == nil, generation == self.startGeneration {
                        await self.start(
                            mode: mode,
                            locale: locale,
                            contextualStrings: contextualStrings,
                            mixesWithOtherAudio: mixesWithOtherAudio
                        )
                    }
                }
            }

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else {
                throw AudioSessionError.noInputRoute
            }
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request, weak self] buffer, _ in
                request?.append(buffer)
                let level = Self.normalizedInputLevel(buffer)
                let uptime = ProcessInfo.processInfo.systemUptime
                Task { @MainActor [weak self] in
                    guard let self, generation == self.startGeneration else { return }
                    guard uptime - self.lastInputLevelUpdateUptime >= 0.2 else { return }
                    self.lastInputLevelUpdateUptime = uptime
                    self.inputLevel = level
                }
            }
            hasInstalledTap = true
            audioEngine.prepare()
            try audioEngine.start()
            state = .listening
            // Speech tasks can end after about a minute of audio. Rotate before
            // that limit and retain the assembled transcript across requests.
            rotationTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(50)) } catch { return }
                guard let self, generation == self.startGeneration, self.state == .listening else { return }
                await self.start(mode: mode, locale: locale, contextualStrings: contextualStrings,
                                 mixesWithOtherAudio: mixesWithOtherAudio)
            }
        } catch {
            guard generation == startGeneration else { return }
            stop()
            state = .failed
            if (error as NSError).code == 561017449 {
                failureReason = "iPhone is giving microphone priority to another audio session. End any call, recording, Siri session, or screen recording, then try again."
            } else {
                failureReason = "The microphone could not be started: \(error.localizedDescription). Check audio permissions and try again."
            }
        }
    }

    func stop(deactivateAudioSession: Bool = true) {
        startGeneration += 1
        rotationTask?.cancel()
        rotationTask = nil
        if streamingStop != nil {
            streamingStop?()
            streamingStop = nil
            // Seed the legacy assembler so a later fallback retains this speech.
            transcriptAssembler = SpeechTranscriptAssembler()
            _ = transcriptAssembler.observe(transcript, start: nil, end: nil, isFinal: true)
        }
        transcriptAssembler.finishTask()
        transcript = transcriptAssembler.transcript
        scoringTranscript = String(transcript.suffix(scoringWindowLength))
        audioEngine.stop()
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        state = .idle
        confidence = nil
        inputLevel = 0
        lastInputLevelUpdateUptime = 0
        showsLowConfidenceWarning = false
        smoothedConfidence = nil
        lowConfidenceSince = nil
        if deactivateAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    @available(iOS 26.0, *)
    private func startStreaming(locale: Locale, contextualStrings: [String], generation: Int) async throws {
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence])
        let analyzer = SpeechAnalyzer(modules: [transcriber],
            options: .init(priority: .userInitiated, modelRetention: .lingering))
        var started = false
        defer {
            if !started { Task { await analyzer.cancelAndFinishNow() } }
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw AudioSessionError.noInputRoute
        }
        let context = AnalysisContext()
        context.contextualStrings[.general] = SpeechVocabulary.phrases(keywords: contextualStrings, context: [])
        try await analyzer.setContext(context)
        try await analyzer.prepareToAnalyze(in: format)
        try Task.checkCancellation()
        guard generation == startGeneration else {
            await analyzer.cancelAndFinishNow()
            return
        }
        let input = audioEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0,
              let converter = AVAudioConverter(from: inputFormat, to: format) else {
            throw AudioSessionError.noInputRoute
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        streamingBase = transcript
        streamingTranscript = StreamingSpeechTranscript()
        let resultTask = Task { @MainActor [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self, generation == self.startGeneration, !Task.isCancelled else { return }
                    let text = String(result.text.characters)
                    let recognized = self.streamingTranscript.observe(text,
                        start: result.range.start.seconds, end: result.range.end.seconds, isFinal: result.isFinal)
                    let full = [self.streamingBase, recognized].filter { !$0.isEmpty }.joined(separator: " ")
                    if self.transcript != full {
                        self.scoringTranscript = String(full.suffix(self.scoringWindowLength))
                        self.transcript = full
                    }
                    let quality = result.text.runs.compactMap { $0.transcriptionConfidence }.filter { $0 > 0 }
                    if !quality.isEmpty { self.updateConfidence(Float(quality.reduce(0, +) / Double(quality.count))) }
                }
            } catch {
                guard let self, generation == self.startGeneration, !Task.isCancelled else { return }
                self.stop()
                self.state = .failed
                self.failureReason = "On-device speech recognition stopped. Retry listening or use manual controls."
            }
        }
        streamingStop = {
            continuation.finish()
            resultTask.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
        // Conversion also copies tap-owned audio before handing it to the async
        // analyzer. The converter is used only on the serial audio callback.
        input.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, _ in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * format.sampleRate / inputFormat.sampleRate)) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, inputStatus in
                if supplied { inputStatus.pointee = .noDataNow; return nil }
                supplied = true
                inputStatus.pointee = .haveData
                return buffer
            }
            if status != .error, converted.frameLength > 0 { continuation.yield(AnalyzerInput(buffer: converted)) }
            let level = Self.normalizedInputLevel(buffer)
            let uptime = ProcessInfo.processInfo.systemUptime
            Task { @MainActor [weak self] in
                guard let self, generation == self.startGeneration,
                      uptime - self.lastInputLevelUpdateUptime >= 0.2 else { return }
                self.lastInputLevelUpdateUptime = uptime
                self.inputLevel = level
            }
        }
        hasInstalledTap = true
        try await analyzer.start(inputSequence: stream)
        guard generation == startGeneration else { return }
        audioEngine.prepare()
        try audioEngine.start()
        state = .listening
        started = true
        // SpeechAnalyzer supports continuous sessions; no minute-long rotation.
    }

    private func updateConfidence(_ rawConfidence: Float) {
        let previous = smoothedConfidence ?? rawConfidence
        let blended = (previous * 0.65) + (rawConfidence * 0.35)
        smoothedConfidence = blended
        confidence = blended

        if blended < lowConfidenceThreshold {
            lowConfidenceSince = lowConfidenceSince ?? Date()
            showsLowConfidenceWarning = Date().timeIntervalSince(lowConfidenceSince ?? Date()) >= lowConfidenceGracePeriod
        } else {
            lowConfidenceSince = nil
            showsLowConfidenceWarning = false
        }
    }

    nonisolated private static func normalizedInputLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData,
              buffer.frameLength > 0,
              buffer.format.channelCount > 0 else { return 0 }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var sumSquares = 0.0
        for channel in 0..<channelCount {
            let samples = channels[channel]
            for frame in 0..<frames {
                let sample = Double(samples[frame])
                sumSquares += sample * sample
            }
        }
        let rms = sqrt(sumSquares / Double(frames * channelCount))
        let decibels = 20 * log10(max(rms, 0.00001))
        return Float(min(1, max(0, (decibels + 60) / 60)))
    }

    private enum AudioSessionError: LocalizedError {
        case noInputRoute

        var errorDescription: String? {
            "No microphone input route is currently available"
        }
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
