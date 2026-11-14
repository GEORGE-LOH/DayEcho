import Speech
import Combine

@MainActor
final class TranscriptionService: ObservableObject {
    @Published private(set) var activeID: UUID?
    private var task: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    private var continuation: CheckedContinuation<String, Error>?
    private var recognitionID: UUID?

    func transcribe(_ clip: Clip, store: LibraryStore, locale: String) async {
        guard activeID == nil else { return }
        activeID = clip.id
        defer { activeID = nil }
        var updated = clip
        do {
            let permission = await withCheckedContinuation { result in
                SFSpeechRecognizer.requestAuthorization { result.resume(returning: $0) }
            }
            guard permission == .authorized else { throw DayEchoError.message("请在系统设置中允许语音识别。") }
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
                  recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
                throw DayEchoError.message("当前设备或语言暂不支持本地识别。请在设置中更换语言并检查系统语言资源。不会自动上传音频。")
            }
            let request = SFSpeechURLRecognitionRequest(url: store.url(for: clip))
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = false
            updated.transcript = try await withCheckedThrowingContinuation { result in
                let runID = UUID()
                recognitionID = runID
                continuation = result
                task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    let text = result?.isFinal == true ? result?.bestTranscription.formattedString : nil
                    let message = error?.localizedDescription
                    Task { @MainActor in
                        if let text { self?.finish(.success(text), id: runID) }
                        else if let message { self?.finish(.failure(DayEchoError.message(message)), id: runID) }
                    }
                }
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(90)) }
                    catch { return }
                    self?.finish(.failure(DayEchoError.message("本地识别超时，请重试。")), id: runID)
                }
            }
            updated.transcriptionError = nil
        } catch { updated.transcriptionError = error.localizedDescription }
        // Preserve edits made while speech recognition was running; do not resurrect deletions.
        if var latest = store.clips.first(where: { $0.id == clip.id }) {
            latest.transcript = updated.transcript
            latest.transcriptionError = updated.transcriptionError
            do { try store.update(latest) } catch { store.error = error.localizedDescription }
        }
    }

    private func finish(_ result: Result<String, Error>, id: UUID) {
        guard recognitionID == id, let pending = continuation else { return }
        recognitionID = nil
        continuation = nil
        timeout?.cancel()
        timeout = nil
        task?.cancel()
        task = nil
        pending.resume(with: result)
    }
}
