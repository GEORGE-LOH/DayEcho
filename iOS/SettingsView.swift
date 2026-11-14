import SwiftUI

struct SettingsView: View {
    @AppStorage("aiBaseURL") private var savedURL = "https://api.openai.com/v1"
    @AppStorage("aiModel") private var savedModel = "gpt-4.1-mini"
    @AppStorage("speechLocale") private var locale = "zh-CN"
    @State private var baseURL = ""
    @State private var model = ""
    @State private var key = ""
    @State private var status: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("语言", selection: $locale) {
                        Text("普通话").tag("zh-CN")
                        Text("English (US)").tag("en-US")
                    }
                } header: { Text("本地转写") } footer: { Text("使用 Apple 设备端语音识别。设备或语言不支持时会报错，不会切换到云端识别。") }
                Section {
                    TextField("API 基础地址（包含 /v1）", text: $baseURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .onChange(of: baseURL) { _, _ in key = ""; status = nil }
                    TextField("模型名称", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("API Key（留空保留此地址已存密钥）", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("保存设置") {
                        do {
                            let config = AIConfiguration(baseURL: baseURL, model: model)
                            let endpoint = try config.endpoint()
                            if !key.isEmpty { try KeychainStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines), account: endpoint.absoluteString) }
                            savedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                            savedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
                            key = ""
                            status = KeychainStore.read(account: endpoint.absoluteString).isEmpty ? "地址已保存，尚未配置此地址的密钥。" : "设置和密钥已保存。"
                        } catch { status = error.localizedDescription }
                    }
                    Button("删除当前地址的密钥", role: .destructive) {
                        do {
                            let endpoint = try AIConfiguration(baseURL: baseURL, model: model).endpoint()
                            try KeychainStore.save("", account: endpoint.absoluteString)
                            key = ""
                            status = "密钥已删除。"
                        } catch { status = error.localizedDescription }
                    }
                    if let status { Text(status).font(.caption) }
                } header: { Text("AI 服务 · 兼容 OpenAI Chat Completions") } footer: {
                    Text("密钥仅存于本机 Keychain，按 API 地址隔离。更换地址需重新输入密钥。AI 费用由你选择的服务商收取。")
                }
                Section("关于本版本") {
                    LabeledContent("版本", value: "0.1 · 开发预览")
                    Text("录音、转写和索引保存在本机，不建立开发者云端账户。应用数据目录排除系统备份，请手动导出重要录音。")
                    Text("手表通过系统后台队列传输，可能延迟。长时间录音、锁屏运行、续航和系统中断行为需在真机上验证。")
                    Text("当前不包含健康数据分析、位置采集、语义向量搜索或长期记忆。")
                }
            }
            .navigationTitle("设置")
            .onAppear { baseURL = savedURL; model = savedModel }
        }
    }
}
