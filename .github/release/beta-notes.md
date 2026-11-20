这是盘览的测试版，用于收集反馈；请先阅读下方说明。

### 下载

- `MoleDesk-macOS-arm64.zip`：Apple Silicon Mac，macOS 13 或更新版本。
- `MoleDesk-macOS-x86_64.zip`：Intel Mac，macOS 13 或更新版本。
- `MoleDesk-Windows-x64.zip`：Windows 10/11，Intel 或 AMD 处理器。
- `MoleDesk-Windows-arm64.zip`：Windows 10/11，ARM64 处理器。
- `SHA256SUMS.txt`：下载文件的 SHA-256 校验值。

Mac 下载后解压，将 `盘览.app` 拖入应用程序目录。Windows 解压后运行 `MoleDesk.exe`。每个压缩包都包含使用说明。使用前需要分别安装对应平台的 [Mole CLI](https://github.com/tw93/Mole)；盘览不会自动安装或打包 Mole。

### 测试版限制

- macOS 应用使用 ad-hoc 签名，未经 Apple Developer ID 签名和公证，下载后可能受到 Gatekeeper 限制。Windows 程序未签名，可能触发 SmartScreen；请确认下载来源和文件完整性。
- Windows 版尚未在实际用户电脑上完成验证；x64 已进行自动启动检查，ARM64 为交叉编译。Windows 版还不支持在盘览内逐项移入回收站，也不显示应用最近使用时间。
- 清理预览由 Mole 生成；macOS 中对所选项目的移动由盘览完成。Windows 版目前只提供预览和在资源管理器中定位，不自动执行整机清理。
- 应用卸载需在 Mole 的终端界面中重新核对并确认。Mole 卸载不自动读取盘览自定义保护范围；请检查文件清单。
- 没有自动更新功能。问题和反馈请通过仓库 Issues 提交，请不要上传个人文件或敏感日志。
