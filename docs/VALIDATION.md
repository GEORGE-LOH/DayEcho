# 验证记录

## 已完成的 Apple 云端验证

- 构建：[GitHub Actions #1](https://github.com/GEORGE-LOH/DayEcho/actions/runs/43577343588)
- 源码提交：`a3230c85617f106631e03db8635a8a576fbd602e`
- 运行器：macOS 15；Xcode 16.4（16F6）
- iPhone 模拟器编译：通过
- Watch 模拟器编译：通过
- XCTest：7 项通过，0 项失败
- 模拟器 App、日志和 xcresult 已打包上传为 `DayEcho-build-1`，保留 7 天

测试覆盖空转写拒绝、超长内容拒绝、来源引用过滤、HTTPS endpoint 校验、重复导入与删除墓碑重载、损坏索引保护。

此外，本地已完成 13 个 Swift 文件的语法解析、工作流 YAML 校验、scheme 核对、模拟器选择逻辑检查及源码归档校验。

## 已知构建警告

麦克风权限使用的 AVAudioSession.requestRecordPermission 已弃用，但在当前 SDK 仍可编译运行；后续可迁移至 AVAudioApplication。工作流固定的 checkout/upload-artifact 版本收到 Node 20 弃用提示，GitHub 本次强制使用 Node 24 并成功运行。AppIntents 元数据提取提示没有对应框架，本应用目前没有 AppIntents 功能。这些警告未导致本次构建或测试失败。

## 尚未验证

尚未进行真实 iPhone/Apple Watch 签名安装、真机录音、蓝牙或离线 WatchConnectivity 传输、后台续航、系统中断、本地语音模型可用性或联网 AI 请求测试。7 项单元测试不代表上述设备功能已通过验收。

完整产品的下一步是配置 Apple 分发签名 / TestFlight，并按 ACCEPTANCE.md 进行配对真机验证。源码及构建日志目前在公开仓库，不包含 API Key、Apple 签名凭据或个人录音。
