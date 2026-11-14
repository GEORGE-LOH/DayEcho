import AVFoundation
import Combine
import Foundation

/// Short files keep local speech requests bounded and allow incremental Watch transfer.
/// Segments can have a small gap while the recorder rotates; this is not gapless archival audio.
@MainActor
final class SegmentRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var isStarting = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var error: String?
    @Published private(set) var currentMarked = false
    var onSegment: ((RecordedSegment) throws -> Void)?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var sessionID = UUID()
    private var clipID = UUID()
    private var startedAt = Date()
    private var segmentStart = Date()
    private var notificationTokens: [NSObjectProtocol] = []
    private let directory: URL
    private let source: String

    init(directory: URL, source: String) {
        self.directory = directory
        self.source = source
        super.init()
        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue {
                Task { @MainActor in
                    self?.stop()
                    self?.error = "录音被系统或来电打断，已保存完成的片段。请手动重新开始。"
                }
            }
        })
    }

    func start() async {
        guard !isRecording, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        error = nil
        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard granted else { error = "请在系统设置中允许麦克风访问。"; return }
        do {
            try LocalFiles.prepare(directory)
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .default, options: [])
            try audio.setActive(true)
            sessionID = UUID()
            startedAt = Date()
            elapsed = 0
            try beginSegment()
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } catch {
            self.error = error.localizedDescription
            stop()
        }
    }

    func mark() { if isRecording { currentMarked = true } }

    func stop() {
        timer?.invalidate()
        timer = nil
        finishSegment()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func tick() {
        guard isRecording else { return }
        elapsed = Date().timeIntervalSince(startedAt)
        if Date().timeIntervalSince(segmentStart) >= 50 {
            finishSegment()
            do { try beginSegment() }
            catch { self.error = error.localizedDescription; stop() }
        }
    }

    private func beginSegment() throws {
        clipID = UUID()
        segmentStart = Date()
        currentMarked = false
        let url = directory.appendingPathComponent(clipID.uuidString).appendingPathExtension("m4a")
        let audio = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000
        ])
        audio.delegate = self
        guard audio.prepareToRecord(), audio.record() else {
            throw DayEchoError.message("无法启动录音，请检查可用存储与麦克风。")
        }
        recorder = audio
    }

    private func finishSegment() {
        guard let audio = recorder else { return }
        let duration = audio.currentTime
        audio.stop()
        recorder = nil
        guard duration > 0.2 else { try? FileManager.default.removeItem(at: audio.url); return }
        let clip = Clip(id: clipID, sessionID: sessionID, startedAt: segmentStart,
                        duration: duration, source: source, filename: audio.url.lastPathComponent,
                        marked: currentMarked)
        do { try onSegment?(RecordedSegment(url: audio.url, clip: clip)) }
        catch { self.error = "音频仍保留在设备，索引保存失败：\(error.localizedDescription)" }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let message = error?.localizedDescription ?? "录音编码失败"
        Task { @MainActor in self.stop(); self.error = message }
    }
}
