import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var clips: [Clip] = []
    @Published var error: String?
    let audioDirectory: URL
    private let indexURL: URL
    private let deletedURL: URL
    private var deleted: Set<UUID> = []
    private var loaded = false

    init(root: URL = LocalFiles.root) {
        audioDirectory = root.appendingPathComponent("Audio", isDirectory: true)
        indexURL = root.appendingPathComponent("library.json")
        deletedURL = root.appendingPathComponent("deleted.json")
        do {
            try LocalFiles.prepare(audioDirectory)
            if FileManager.default.fileExists(atPath: indexURL.path) {
                clips = try JSONDecoder().decode([Clip].self, from: Data(contentsOf: indexURL))
            }
            if FileManager.default.fileExists(atPath: deletedURL.path) {
                deleted = try JSONDecoder().decode(Set<UUID>.self, from: Data(contentsOf: deletedURL))
            }
            clips.removeAll { deleted.contains($0.id) }
            loaded = true
            try recoverUnindexedAudio()
        } catch { self.error = "无法读取本地记录，未覆盖原文件：\(error.localizedDescription)" }
    }

    func url(for clip: Clip) -> URL { audioDirectory.appendingPathComponent(clip.filename) }

    func add(_ segment: RecordedSegment) throws {
        guard loaded else { throw DayEchoError.message("记录库尚未成功加载。") }
        guard !clips.contains(where: { $0.id == segment.clip.id }), !deleted.contains(segment.clip.id) else { return }
        let destination = url(for: segment.clip)
        if segment.url.standardizedFileURL != destination.standardizedFileURL {
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: segment.url, to: destination)
            }
        }
        var updated = clips
        updated.append(segment.clip)
        try commit(updated)
    }

    func update(_ clip: Clip) throws {
        guard let index = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        var updated = clips
        updated[index] = clip
        try commit(updated)
    }

    func delete(_ clip: Clip) throws {
        // Tombstones prevent a delayed duplicate Watch transfer from restoring a deleted clip.
        deleted.insert(clip.id)
        try JSONEncoder().encode(deleted).write(to: deletedURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try commit(clips.filter { $0.id != clip.id })
        let file = url(for: clip)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    private func commit(_ updated: [Clip]) throws {
        guard loaded else { throw DayEchoError.message("记录库尚未成功加载。") }
        let ordered = updated.sorted { $0.startedAt > $1.startedAt }
        try JSONEncoder().encode(ordered).write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        clips = ordered
    }

    private func recoverUnindexedAudio() throws {
        for url in try FileManager.default.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: [.creationDateKey]) where url.pathExtension == "m4a" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  !clips.contains(where: { $0.id == id }) else { continue }
            if deleted.contains(id) { try FileManager.default.removeItem(at: url); continue }
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            // Crash recovery retains audio; unknown duration is shown as zero until playback.
            try add(RecordedSegment(url: url, clip: Clip(id: id, sessionID: id, startedAt: date,
                duration: 0, source: "恢复的录音", filename: url.lastPathComponent, marked: false)))
        }
    }
}
