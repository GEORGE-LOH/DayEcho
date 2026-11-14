# 无 Mac 的云端构建

GitHub Actions 使用 `macos-15` 运行器；优先选择安装的 Xcode 16.4，否则使用运行器默认 Xcode。实际版本写入构建日志。XcodeGen 由运行器 Homebrew 安装，版本同样记录。无需 Apple 账号或 API Key。

## 运行

向 `main` 或 `codex/**` 分支推送、对 main 发起 PR，或在 GitHub 仓库 Actions → Apple build and tests → Run workflow 手动启动。PR 和对应 codex 分支的 push 可能分别执行一次构建。

流程生成工程 → 编译 iPhone App → 编译 Watch App → 自动选择已安装的 iPhone 模拟器 → 执行 XCTest → 上传日志、xcresult 和模拟器 App 压缩包。任一步失败都保持构建失败，已有日志仍上传；不会用静态语法检查代替编译。

构建日志和产物位于 Actions 的对应运行页面，保留 7 天。仓库为私有时，访问日志与下载产物需要仓库权限。运行时间按 GitHub 账户的 Actions 额度与设置计量，不会自动设置付费额度。

## 产物的含义

- `DayEcho-iPhone-Simulator.zip`：适用于 Mac 上的 iPhone 模拟器。
- `DayEcho-Watch-Simulator.zip`：适用于 Mac 上的 Watch 模拟器。
- `DayEcho.xcresult`：Xcode 测试报告。
- `iphone-build.log`、`watch-build.log`、`tests.log`：编译与测试日志。

这些产物不是可直接在真实 iPhone/Apple Watch 安装的 IPA。没有 Mac 也能通过 GitHub 页面查看构建和测试结果，但不能在 GitHub 托管运行器上验证你的手表录音、后台续航或实际蓝牙传输。

## 后续真机分发

如需不借助本地 Mac 安装测试版，下一阶段配置 Apple Developer Program、App Store Connect 和 TestFlight。需唯一 bundle ID、发行证书、provisioning profiles 以及分发权限，密钥应保存为 GitHub Actions Secrets。当前流程没有配置签名或 TestFlight，也没有上传任何 Apple 凭据。
