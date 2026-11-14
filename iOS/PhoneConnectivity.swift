import Foundation
import WatchConnectivity

final class PhoneConnectivity: NSObject, WCSessionDelegate {
    private let inbox = LocalFiles.root.appendingPathComponent("Inbox", isDirectory: true)
    private let store: LibraryStore

    @MainActor init(store: LibraryStore) {
        self.store = store
        super.init()
        do { try LocalFiles.prepare(inbox) }
        catch { store.error = error.localizedDescription }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        drainInbox()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error { Task { @MainActor in store.error = error.localizedDescription } }
        else { Task { @MainActor in self.drainInbox() } }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        do {
            guard let data = file.metadata?["clip"] as? Data else { throw DayEchoError.message("手表录音缺少元数据。") }
            let clip = try JSONDecoder().decode(Clip.self, from: data)
            guard clip.filename == clip.id.uuidString + ".m4a" else { throw DayEchoError.message("录音文件名无效。") }
            let audio = inbox.appendingPathComponent(clip.filename)
            // WCSession owns its temporary URL only until this delegate method returns.
            if !FileManager.default.fileExists(atPath: audio.path) { try FileManager.default.copyItem(at: file.fileURL, to: audio) }
            try data.write(to: inbox.appendingPathComponent(clip.id.uuidString + ".json"), options: .atomic)
            Task { @MainActor in self.drainInbox() }
        } catch { Task { @MainActor in store.error = "接收手表录音失败：\(error.localizedDescription)" } }
    }

    @MainActor func drainInbox() {
        do {
            for metadata in try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil) where metadata.pathExtension == "json" {
                let clip = try JSONDecoder().decode(Clip.self, from: Data(contentsOf: metadata))
                let audio = inbox.appendingPathComponent(clip.filename)
                try store.add(RecordedSegment(url: audio, clip: clip))
                guard WCSession.default.activationState == .activated else { continue }
                // Acknowledge only after the phone has durably committed the recording.
                WCSession.default.transferUserInfo(["receivedClipID": clip.id.uuidString])
                try FileManager.default.removeItem(at: metadata)
                try FileManager.default.removeItem(at: audio)
            }
        } catch { store.error = "导入待处理录音失败：\(error.localizedDescription)" }
    }
}
