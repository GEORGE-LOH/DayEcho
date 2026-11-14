import Foundation

struct Clip: Codable, Identifiable, Equatable {
    let id: UUID
    let sessionID: UUID
    let startedAt: Date
    let duration: TimeInterval
    let source: String
    let filename: String
    var transcript: String?
    var transcriptionError: String?
    var marked: Bool

    var citation: String { id.uuidString }
}

struct RecordedSegment {
    let url: URL
    let clip: Clip
}

enum DayEchoError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

enum LocalFiles {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DayEcho", isDirectory: true)
    }

    static func prepare(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
