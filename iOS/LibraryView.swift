import SwiftUI
import AVFoundation

struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var recorder: SegmentRecorder
    @EnvironmentObject private var speech: TranscriptionService
    @AppStorage("speechLocale") private var locale = "zh-CN"
    @State private var search = ""
    @State private var onlyMarked = false
    @State private var batchRunning = false

    private var filtered: [Clip] {
        store.clips.filter { clip in
            (!onlyMarked || clip.marked) && (search.isEmpty || (clip.transcript ?? "").localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("把此刻留给未来的你").font(.title2.bold())
                        Text(recorder.isRecording ? "正在录音 · \(Int(recorder.elapsed)) 秒" : "开始一段录音，或等待手表同步。")
                            .foregroundStyle(.secondary)
                        HStack {
                            Button {
                                if recorder.isRecording { recorder.stop() }
                                else { Task { await recorder.start() } }
                            } label: {
                                Label(recorder.isRecording ? "停止录音" : "开始录音", systemImage: recorder.isRecording ? "stop.fill" : "mic.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(recorder.isRecording ? .red : .teal)
                            .disabled(speech.activeID != nil)
                            if recorder.isRecording {
                                Button { recorder.mark() } label: {
                                    Image(systemName: recorder.currentMarked ? "bookmark.fill" : "bookmark")
                                }.buttonStyle(.bordered).accessibilityLabel("标记当前片段")
                            }
                        }
                        if let error = recorder.error { Text(error).font(.caption).foregroundStyle(.red) }
                    }.padding(.vertical, 8)
                }
                Section {
                    Toggle("仅看已标记", isOn: $onlyMarked)
                    Button(batchRunning ? "正在逐段转写…" : "转写待处理录音") {
                        let pending = store.clips.filter { $0.transcript == nil }
                        batchRunning = true
                        Task { @MainActor in
                            defer { batchRunning = false }
                            for clip in pending {
                                guard store.clips.contains(where: { $0.id == clip.id }) else { continue }
                                await speech.transcribe(clip, store: store, locale: locale)
                            }
                        }
                    }.disabled(batchRunning || speech.activeID != nil || recorder.isRecording)
                } footer: {
                    Text("转写仅在设备上进行。搜索当前为文字匹配。录音前请征得参与者同意。")
                }
                Section("录音 · \(filtered.count)") {
                    if filtered.isEmpty {
                        ContentUnavailableView(search.isEmpty ? "还没有记录" : "没有匹配文字",
                                               systemImage: "waveform", description: Text("录音并完成转写后，即可搜索和回顾。"))
                    }
                    ForEach(filtered) { clip in
                        NavigationLink { ClipDetailView(id: clip.id) } label: { ClipRow(clip: clip) }
                    }
                }
            }
            .navigationTitle("DayEcho")
            .searchable(text: $search, prompt: "搜索转写文字")
            .alert("本地记录提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("知道了") { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
    }
}

struct ClipRow: View {
    let clip: Clip
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(clip.startedAt, format: .dateTime.month().day().hour().minute())
                if clip.marked { Image(systemName: "bookmark.fill").foregroundStyle(.teal) }
                Spacer()
                Text("\(Int(clip.duration))秒").foregroundStyle(.secondary)
            }.font(.subheadline)
            Text(clip.transcript ?? "待转写 · \(clip.source)").lineLimit(2)
                .foregroundStyle(clip.transcript == nil ? .secondary : .primary)
        }.padding(.vertical, 4)
    }
}

struct ClipDetailView: View {
    let id: UUID
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var speech: TranscriptionService
    @EnvironmentObject private var recorder: SegmentRecorder
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speechLocale") private var locale = "zh-CN"
    @State private var player: AVAudioPlayer?
    @State private var deleting = false
    @State private var error: String?
    private var clip: Clip? { store.clips.first { $0.id == id } }

    var body: some View {
        Group {
            if let clip {
                List {
                    Section {
                        Text(clip.startedAt, format: .dateTime.year().month().day().hour().minute())
                        Label("\(clip.source) · \(Int(clip.duration)) 秒", systemImage: "waveform")
                        HStack {
                            Button("从头播放", systemImage: "play.fill") {
                                do {
                                    let audio = AVAudioSession.sharedInstance()
                                    try audio.setCategory(.playback, mode: .default)
                                    try audio.setActive(true)
                                    player = try AVAudioPlayer(contentsOf: store.url(for: clip))
                                    player?.play()
                                } catch { self.error = error.localizedDescription }
                            }.disabled(recorder.isRecording)
                            Spacer()
                            Button("停止", systemImage: "stop.fill") { stopPlayback() }
                        }.buttonStyle(.borderless)
                        Button(clip.marked ? "取消标记" : "标记片段", systemImage: "bookmark") {
                            var updated = clip
                            updated.marked.toggle()
                            do { try store.update(updated) } catch { self.error = error.localizedDescription }
                        }
                    }
                    Section("转写文字") {
                        Text(clip.transcript ?? "尚未转写").textSelection(.enabled)
                        if let message = clip.transcriptionError { Text(message).font(.caption).foregroundStyle(.red) }
                        Button(speech.activeID == id ? "本地识别中…" : "在本机转写") {
                            stopPlayback()
                            Task { await speech.transcribe(clip, store: store, locale: locale) }
                        }.disabled(speech.activeID != nil || recorder.isRecording)
                    }
                    Section("导出") {
                        ShareLink("分享音频", item: store.url(for: clip))
                        if let text = clip.transcript { ShareLink("分享文字", item: text) }
                    }
                    Section {
                        Button("删除此片段", role: .destructive) { deleting = true }
                    } footer: { Text("删除本机音频与转写。已分享的文件以及 AI 服务商已接收的内容不受影响。") }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                .confirmationDialog("永久删除这段录音及其转写？", isPresented: $deleting, titleVisibility: .visible) {
                    Button("删除", role: .destructive) {
                        do { stopPlayback(); try store.delete(clip); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            } else { ContentUnavailableView("记录已删除", systemImage: "trash") }
        }
        .navigationTitle("录音详情")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { stopPlayback() }
    }

    private func stopPlayback() {
        guard player != nil else { return }
        player?.stop()
        player = nil
        if !recorder.isRecording { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
}
