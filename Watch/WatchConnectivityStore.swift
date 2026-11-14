import Foundation
import Combine
import WatchConnectivity

@MainActor
final class WatchConnectivityStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var pendingCount = 0
    @Published private(set) var status = "等待连接 iPhone"
    let directory = LocalFiles.root.appendingPathComponent("Outbox", isDirectory: true)

    override init() {
        super.init()
        do {
            try LocalFiles.prepare(directory)
            try recoverUnindexedAudio()
        }
        catch { status = error.localizedDescription }
        WCSession.default.delegate = self
        WCSession.default.activate()
        refreshCount()
    }

    func enqueue(_ segment: RecordedSegment) throws {
        let data = try JSONEncoder().encode(segment.clip)
        try data.write(to: directory.appendingPathComponent(segment.clip.id.uuidString + ".json"), options: .atomic)
        retry()
    }

    func retry() {
        refreshCount()
        let session = WCSession.default
        guard session.activationState == .activated else { status = "等待配对连接激活"; return }
        do {
            let active = Set(session.outstandingFileTransfers.map { $0.file.fileURL.lastPathComponent })
            for metadata in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where metadata.pathExtension == "json" {
                let data = try Data(contentsOf: metadata)
                let clip = try JSONDecoder().decode(Clip.self, from: data)
                let audio = directory.appendingPathComponent(clip.filename)
                guard FileManager.default.fileExists(atPath: audio.path), !active.contains(clip.filename) else { continue }
                session.transferFile(audio, metadata: ["clip": data])
            }
            status = pendingCount == 0 ? "已同步" : "\(pendingCount) 段等待系统传输"
        } catch { status = error.localizedDescription }
    }

    private func refreshCount() {
        pendingCount = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.count
    }

    private func recoverUnindexedAudio() throws {
        for audio in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) where audio.pathExtension == "m4a" {
            let metadata = audio.deletingPathExtension().appendingPathExtension("json")
            guard !FileManager.default.fileExists(atPath: metadata.path),
                  let id = UUID(uuidString: audio.deletingPathExtension().lastPathComponent) else { continue }
            let date = (try? audio.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            let clip = Clip(id: id, sessionID: id, startedAt: date, duration: 0,
                            source: "Apple Watch · 恢复", filename: audio.lastPathComponent, marked: false)
            try JSONEncoder().encode(clip).write(to: metadata, options: .atomic)
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let message = error?.localizedDescription
        Task { @MainActor in
            if let message { self.status = message } else { self.retry() }
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let message = error?.localizedDescription
        Task { @MainActor in
            if let message { self.status = "传输未完成，文件已保留：\(message)"; return }
            self.status = "传输完成，等待 iPhone 保存确认"
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let raw = userInfo["receivedClipID"] as? String, let id = UUID(uuidString: raw) else { return }
        Task { @MainActor in
            do {
                for ext in ["m4a", "json"] {
                    let url = self.directory.appendingPathComponent(id.uuidString).appendingPathExtension(ext)
                    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                }
                self.refreshCount()
                self.status = self.pendingCount == 0 ? "已同步" : "还有 \(self.pendingCount) 段待传输"
            } catch { self.status = error.localizedDescription }
        }
    }
}
