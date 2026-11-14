import SwiftUI

@main
struct DayEchoWatchApp: App {
    @StateObject private var connectivity: WatchConnectivityStore
    @StateObject private var recorder: SegmentRecorder

    init() {
        let connection = WatchConnectivityStore()
        let audio = SegmentRecorder(directory: connection.directory, source: "Apple Watch")
        audio.onSegment = { try connection.enqueue($0) }
        _connectivity = StateObject(wrappedValue: connection)
        _recorder = StateObject(wrappedValue: audio)
    }

    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(spacing: 12) {
                    Label("DayEcho", systemImage: "waveform")
                        .foregroundStyle(.mint)
                    Text(recorder.isRecording ? "录音中" : "记录此刻")
                        .font(.headline)
                    Text(Duration.seconds(recorder.elapsed).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(.title2, design: .monospaced))
                    Button {
                        if recorder.isRecording { recorder.stop() }
                        else { Task { await recorder.start() } }
                    } label: {
                        Label(recorder.isRecording ? "停止并保存" : "开始录音",
                              systemImage: recorder.isRecording ? "stop.fill" : "mic.fill")
                    }
                    .tint(recorder.isRecording ? .red : .mint)
                    if recorder.isRecording {
                        Button(recorder.currentMarked ? "已标记" : "标记当前片段") { recorder.mark() }
                    }
                    Text(connectivity.status).font(.caption2).foregroundStyle(.secondary)
                    if let error = recorder.error { Text(error).font(.caption2).foregroundStyle(.orange) }
                    Button("重试同步") { connectivity.retry() }.font(.caption)
                }
            }
        }
    }
}
