# DayEcho — iPhone + Apple Watch 原生开发预览

独立实现的个人录音与回顾应用。参考公开的产品需求，不包含 Auday 源码、品牌素材或私有接口。

**状态：0.1 开发预览，已通过云端 Xcode 16.4 的 iPhone / Watch 模拟器构建和全部 7 项 XCTest。尚未真机验证，不是可安装到真机的 IPA，也不是功能齐全的 Auday 替代品。**

[查看成功构建与下载产物](https://github.com/GEORGE-LOH/DayEcho/actions/runs/43577343588) · [验证记录](docs/VALIDATION.md)

## 当前代码覆盖

- iPhone / Apple Watch 手动开始、停止录音，约 50 秒一段，标记当前片段。
- Apple Watch 离线保存，WatchConnectivity 队列传输；iPhone 持久化后回执，手表收到回执才移除副本。
- iPhone 记录列表、本地音频播放、文字匹配搜索、标记、音频/文字分享与删除。
- 使用 Apple Speech 的设备端转写；不支持时明确报错，不自动改用云识别。
- 选择转写片段，预览将发送的文本，调用兼容 OpenAI Chat Completions 的服务完成总结或问答。
- 仅把匹配已选片段 UUID 的引用展示为可跳转来源。引用存在不意味着 AI 结论已被验证。
- API Key 保存在本机 Keychain，并按 API 地址隔离。拒绝 HTTP 和重定向，避免自动转发密钥和文字。
- 本地删除墓碑防止迟到的手表重复传输恢复已删除记录；启动时恢复未索引音频。

## 没有 Mac：使用云端构建

仓库包含 `.github/workflows/apple-build.yml`，在 GitHub 的 macOS 运行器上编译手机与手表 App，并运行 XCTest。推送代码即可触发，也可在 Actions 手动运行。详细步骤与产物限制见 `docs/CLOUD_BUILD.md`。模拟器构建不需要 Apple 开发者账号，不能直接安装到真机。

## 在 Mac 上打开

需要 Xcode 16 或更新版本及对应 iOS / watchOS SDK。最低系统 iOS 17、watchOS 10。

```bash
brew install xcodegen
cd DayEcho
xcodegen generate
open DayEcho.xcodeproj
```

1. 在两个 App target 的 Signing & Capabilities 中选择自己的 Development Team。
2. 将 `project.yml` 中三个 bundle ID / companion ID 替换成自己的唯一标识后重新生成。iPhone ID 与 `WKCompanionAppBundleIdentifier` 必须一致，Watch ID 以 iPhone ID 为前缀。
3. 安装到已配对的 iPhone 和 Apple Watch，首次使用时授予麦克风权限；手机转写时授予语音识别权限。
4. 先在手机录一段中文或英文，停止，执行本机转写和播放。然后测试手表录音传到手机。
5. 设置 AI 基础地址（默认 `https://api.openai.com/v1`）、可用模型和自己的 API Key。默认模型只是可编辑配置，不保证每个账户都能调用。
6. 在“回顾”选择已转写片段，预览发送内容，再发起问答。

未调用任何真实 AI 服务，未创建账户或产生费用。无应用后端依赖。

## 在 Mac 上验证

```bash
xcodebuild -list -project DayEcho.xcodeproj
xcodebuild -project DayEcho.xcodeproj -scheme DayEcho \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project DayEcho.xcodeproj -target DayEchoWatch \
  -sdk watchsimulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -showdestinations -project DayEcho.xcodeproj -scheme DayEcho
# 使用上一步实际存在的 iPhone Simulator UDID：
xcodebuild -project DayEcho.xcodeproj -scheme DayEcho \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' test
```

测试源码覆盖重复导入、删除后重传、损坏索引保护、AI 输入上限、引用过滤和 HTTPS 地址校验。7 项测试已在 GitHub macOS 运行器上的 iPhone 模拟器执行，全部通过。

模拟器不能替代手表真机音频、转写模型、后台运行和离线传输测试。详见 `docs/ACCEPTANCE.md`。

## 已知边界

- 录音器切换片段可能产生短暂间隙。不是无缝音频归档实现。
- 配置了音频后台模式，但锁屏、手腕放下、分段切换与长时间运行仍须真机验证。系统终止可能导致最后一个音频文件不完整；恢复逻辑不能修复损坏的音频内容。
- 存储无容量上限或自动清理。32 kbps 编码理论音频量约 14.4 MB/小时，实际以设备测量为准；不能据此推断电池续航。
- 手机必须打开并手动执行转写；系统语言模型和设备支持情况决定能否本地识别。
- 搜索是文字匹配，尚未实现向量语义搜索。
- 每次问答发送显式选中的文本，限制为 24,000 字符；超限报错，不会悄悄截断。不同模型仍可能有更小上下文限制。
- AI 回答仅在当前页面内存中保留，没有长期记忆、聊天历史或自动每日总结任务。
- 健康数据、压力估计、位置与运动时间线尚未实现；当前没有请求这些权限。
- 无 App Store 图标、上架文案、订阅、商店签名或发布配置。

## 数据与隐私

音频与索引位于 Application Support/DayEcho，目录排除设备备份，卸载会失去录音；重要内容请手动导出。手表保留未获手机保存确认的录音副本。密钥使用 `WhenUnlockedThisDeviceOnly` Keychain 项；卸载不保证清理 Keychain，请在设置中显式删除密钥。

AI 只在用户主动发送时接收选中片段的文字、时间、片段 ID 和问题。无开发者分析 SDK。外部 AI 服务商的数据处理政策由用户选择的服务商决定。删除本机录音不会撤回已发送给外部服务的文字或已分享文件。录音前应获得参与者同意。

## 工程结构

```text
Shared/    录音数据模型、分段录音器
Watch/     手表界面、离线队列和保存回执
iOS/       本地库、同步、转写、AI、安全存储、SwiftUI 页面
Tests/     XCTest 行为测试
docs/      架构、验收与后续产品范围
project.yml  XcodeGen 工程定义
```
