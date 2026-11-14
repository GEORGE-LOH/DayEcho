# 数据流与设计取舍

## 录音与同步

`SegmentRecorder` → UUID.m4a → UUID.json 待传元数据 → WCSession.transferFile → iPhone Inbox → LibraryStore 音频复制 + 原子索引 → WCSession.transferUserInfo 保存回执 → Watch 删除队列副本。

系统传输完成不等同于应用持久化完成，因此不能在 `didFinish fileTransfer` 中直接删除手表文件。手机收到临时文件后在 delegate 返回前复制到 Inbox，再切回主 actor 更新记录库。

UUID 保证重复导入不会重复建立索引。已删除 UUID 持久化保存，阻止尚在队列中的副本恢复记录。UUID 墓碑没有自动压缩，长期使用需增加保留策略。暂未实现手机与手表同步任务的端到端集成测试。

启动扫描可恢复已写盘但未记入索引的音频；元数据缺失时只恢复文件时间和文件身份，时长显示为零，不伪造会话信息。损坏的索引不会被覆盖；目前只能通过开发工具备份和修复，不提供应用内恢复向导。

## 转写与 AI

本地音频 → SFSpeechRecognizer（requiresOnDeviceRecognition）→ 可编辑扩展的 Clip 转写字段 → 用户选择 → EvidenceBundle（显式字符限制）→ 发送预览 → HTTPS AI → UUID 来源过滤 → 原始录音播放。

转写逐段执行，并设 90 秒超时。结果写回前重新读取当前记录，避免覆盖用户在识别期间的标记变更。已删除的记录不会被转写任务恢复。

AI API 兼容层仅支持非流式 `/chat/completions` 的文本回答。错误只展示状态码，不将服务商返回的任意正文泄漏到界面或日志。模型输出视为纯文本，无法调用工具。提示词防注入只是辅助措施，不能保证模型完全不受录音内容影响。

## 完整产品的后续工作

1. **先完成 Apple 平台验证**：修复实际 SDK 编译问题；测试权限拒绝、离线同步、杀进程、电话打断、锁屏录音和电池温升。未经这些验证不应公开发布。
2. **长时间可靠录音**：以 AVAudioEngine 连续采样与异步文件轮换替代启停式分段，评估 watchOS 后台行为、热量和功耗；增加磁盘低水位和有上限的重试。
3. **完整检索**：为中文和英文选择可在设备运行的 embedding 模型；SQLite/FTS 与向量索引；时间/会话检索、分块摘要和可核对引用。需基于真实设备性能选模型，不能仅用名称相似的 API 代替。
4. **日记和长期记忆**：持久化 AI 回答，按日生成摘要；每条记忆可查看来源、编辑、停用、删除。设计删除传播，避免删了原文仍保留派生记忆。
5. **可选健康和活动**：单独申请 HealthKit 只读权限，将真实心率、运动与睡眠数据关联到时间线；不将心率直接标成压力或情绪。
6. **可选位置**：明确用途、权限和保留周期；先实现前台位置标记，再评估后台定位的必要性与电量成本。
7. **发行**：无障碍、国际化、图标、隐私清单审查、App Store 数据披露、签名、TestFlight、真机回归。

## 参考

- Apple Audio Session recording category: https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record
- Apple WatchConnectivity: https://developer.apple.com/documentation/watchconnectivity
- Apple on-device speech: https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition
- XcodeGen: https://github.com/yonaskolb/XcodeGen

这些文档是实现参考，并非本工程已经通过平台验收的证据。
