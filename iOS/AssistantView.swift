import SwiftUI

struct AssistantView: View {
    @EnvironmentObject private var store: LibraryStore
    @AppStorage("aiBaseURL") private var baseURL = "https://api.openai.com/v1"
    @AppStorage("aiModel") private var model = "gpt-4.1-mini"
    @State private var selected: Set<UUID> = []
    @State private var question = "请总结这些记录中的要点、明确约定的待办，以及仍需确认的事情。"
    @State private var evidence: EvidenceBundle?
    @State private var review = false
    @State private var running = false
    @State private var answer: AIAnswer?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("从真实记录出发").font(.title2.bold())
                    Text("选择已转写片段，再提问或生成总结。只有你选择的文字会发给设置中的 AI 服务。")
                        .foregroundStyle(.secondary)
                    TextField("你想回顾什么？", text: $question, axis: .vertical).lineLimit(3...7)
                }
                Section("选择记录 · \(selected.count)") {
                    Button("选择今天的转写") {
                        selected = Set(store.clips.filter { Calendar.current.isDateInToday($0.startedAt) && !($0.transcript ?? "").isEmpty }.map(\.id))
                    }
                    Button("清空选择") { selected = [] }
                    ForEach(store.clips.filter { !($0.transcript ?? "").isEmpty }) { clip in
                        Button {
                            if selected.contains(clip.id) { selected.remove(clip.id) } else { selected.insert(clip.id) }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(clip.id) ? "checkmark.circle.fill" : "circle")
                                ClipRow(clip: clip)
                            }
                        }.foregroundStyle(.primary)
                    }
                }
                Section {
                    Button(running ? "正在生成…" : "查看发送内容") {
                        do {
                            evidence = try EvidenceBundle(clips: store.clips.filter { selected.contains($0.id) })
                            _ = try AIConfiguration(baseURL: baseURL, model: model).endpoint()
                            error = nil
                            review = true
                        } catch { self.error = error.localizedDescription }
                    }.disabled(running || selected.isEmpty || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if running { ProgressView() }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                if let answer {
                    Section("AI 回顾") {
                        Text(answer.text).textSelection(.enabled)
                        ShareLink("分享回答", item: answer.text)
                        Text("AI 可能理解错误，请核对原始录音。此回答仅在当前页面会话中保留。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("核对来源") {
                        if answer.sourceIDs.isEmpty { Text("回答没有可验证的片段引用，请谨慎核对。") }
                        ForEach(answer.sourceIDs, id: \.self) { id in
                            if let clip = store.clips.first(where: { $0.id == id }) {
                                NavigationLink { ClipDetailView(id: id) } label: { ClipRow(clip: clip) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("回顾")
            .sheet(isPresented: $review) {
                NavigationStack {
                    List {
                        Section("接收服务") { Text(baseURL); Text("模型：\(model)") }
                        Section("问题") { Text(question) }
                        Section("将发送的转写与时间") { Text(evidence?.text ?? "").textSelection(.enabled) }
                        Section {
                            Button("发送并生成") { send() }.buttonStyle(.borderedProminent)
                        } footer: { Text("发送的是以上文字、片段标识与时间，不包含原始音频。服务商可能收费并按其政策保留数据。") }
                    }
                    .navigationTitle("发送内容预览")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { review = false } } }
                }
            }
        }
    }

    private func send() {
        guard let evidence else { return }
        let prompt = question
        let config = AIConfiguration(baseURL: baseURL, model: model)
        review = false
        running = true
        answer = nil
        Task { @MainActor in
            defer { running = false }
            do { answer = try await AIService.ask(question: prompt, evidence: evidence, configuration: config) }
            catch { self.error = error.localizedDescription }
        }
    }
}
