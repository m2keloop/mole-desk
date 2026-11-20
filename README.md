# 盘览 · Mole Desk

轻量的 macOS 磁盘查看与清理客户端。盘览调用 [Mole](https://github.com/tw93/Mole) 的预览命令，在原生窗口中审阅候选项目，并提供磁盘浏览和应用使用时间查询。

Windows 原生界面移植及构建方法见 [Windows 说明](https://github.com/m2keloop/mole-desk/blob/main/windows/README.md)。

预发布安装包发布在 [GitHub Releases](https://github.com/m2keloop/mole-desk/releases)。推送形如 `v0.1.0-beta.1` 的标签会自动测试、构建并发布预发布版；工作流只在全部构建和测试通过后发布，不需要人工审核。测试版的系统要求、签名状态和已知限制以 Release 说明为准。

## 安装

盘览是调用 Mole CLI 的独立图形客户端，安装盘览不会自动安装 Mole，也不会自动清理文件。

### macOS

1. 确认系统为 macOS 13 或更新版本，并在终端执行 `uname -m`：`arm64` 表示 Apple Silicon，`x86_64` 表示 Intel。
2. 在 [Releases](https://github.com/m2keloop/mole-desk/releases) 找到预发布版本，根据架构下载 `MoleDesk-macOS-arm64.zip` 或 `MoleDesk-macOS-x86_64.zip`。同时可下载 `SHA256SUMS.txt`，用 `shasum -a 256 下载包路径` 计算哈希，与文件中对应包的值比较。
3. 解压 ZIP，打开解压后的目录，把 `盘览.app` 拖入「应用程序」文件夹，然后打开。
4. 安装 [Mole macOS CLI](https://github.com/tw93/Mole)：已安装 Homebrew 的用户可运行 `brew install mole`，再用 `mo --version` 验证。没有 Homebrew 时，请参考 Mole 官方安装说明。安装完成后如盘览未找到 Mole，请重新打开盘览。

测试包目前仅有 ad-hoc 签名，未经 Apple Developer ID 签名与公证，下载后可能被 Gatekeeper 拦截。确认下载来源和文件完整性后，可参考 [Apple 的说明](https://support.apple.com/zh-cn/102445)处理。校验值用于检查文件是否一致，不能单独证明发布者身份。

### Windows

1. 在 Windows「设置 → 系统 → 关于」查看系统类型，从 [Releases](https://github.com/m2keloop/mole-desk/releases) 下载 `MoleDesk-Windows-x64.zip`（Intel / AMD）或 `MoleDesk-Windows-arm64.zip`（ARM）。需要 Windows 10 或 11。
2. 可下载 `SHA256SUMS.txt`，在 PowerShell 中执行 `Get-FileHash -Algorithm SHA256 下载包路径`，并与对应包的校验值比较。
3. 解压到你选择的文件夹，运行其中的 `MoleDesk.exe`。这是免安装版本，保留该文件夹即可，不会自动创建安装程序。
4. 安装 [Mole Windows CLI](https://github.com/tw93/Mole/blob/windows/README.md)：已安装 Scoop 的用户可在 PowerShell 中运行 `scoop install mole`，再用 `mo --version` 验证。其他安装方式请参考 Mole 的 Windows 官方说明。安装完成后如盘览未找到 Mole，请重新打开盘览。

Windows 测试包尚未签名，可能出现 SmartScreen 提示；x64 已通过自动启动检查，ARM64 仅交叉编译，均未完成实际用户电脑验证。使用范围与限制见 [Windows 说明](https://github.com/m2keloop/mole-desk/blob/main/windows/README.md)。

### 使用 AI 协助安装

如果使用的 AI 助手有这台电脑的终端或文件操作权限，可以直接向它发送下面的提示；只能聊天的助手可以依据这些步骤指导你操作。安装与系统安全确认是否需要你操作，取决于所用助手和系统的权限规则。

> 请帮我在这台电脑上安装开源项目「盘览 Mole Desk」：https://github.com/m2keloop/mole-desk 。先阅读 README 和 Releases 的说明，检查系统与处理器架构，选择对应的预发布包并核对 SHA-256；如尚未安装 Mole CLI，请按对应平台的官方说明协助安装并验证版本。完成后启动盘览验证。安装期间不要执行清理、卸载其他应用或删除我的文件，不要上传个人文件、私密路径和日志；遇到签名、公证、系统安全提示或需要更高权限的操作时，请说明情况并由我处理。

如果要让 AI 按 Mole 项目自己的流程安装 Mole，也可以让它读取 [Mole 的 AI 安装说明](https://raw.githubusercontent.com/tw93/Mole/main/llms.txt)。该说明介绍 CLI 和 AI 工具集成；是否安装 AI 工具集成由你决定，盘览本身只需要 Mole CLI。安装后若想评估清理范围，可先运行 `mo clean --dry-run`，预览不会执行清理。

## 卸载

**卸载盘览不会自动卸载 Mole，也不会清理个人文件或其他应用的数据。**

- **macOS**：退出盘览，在 Finder 中找到安装位置，将 `盘览.app` 移到废纸篓。若还想移除盘览自己的设置和上次预览备份，可自行检查 `~/Library/Preferences/local.lan.MoleDesk.plist` 和 `~/Library/Application Support/local.lan.MoleDesk/` 后移到废纸篓；这些路径可能不存在。移到废纸篓后仍可恢复，清空废纸篓才会永久删除。
- **Windows**：退出盘览，将解压出的 `MoleDesk.exe` 或整个盘览文件夹移到回收站。本版本是免安装程序；Mole 的配置和日志不在这个文件夹中，不会随之删除。

如其他工具仍需要 Mole，请保留它。若也要单独卸载 Mole，先确认其安装方式：Homebrew 安装的可使用 `brew uninstall mole`；Scoop 安装的可使用 `scoop uninstall mole`。通过 Mole 官方脚本安装的，可先运行 `mo remove --dry-run` 查看范围，再根据 [Mole 官方说明](https://github.com/tw93/Mole)决定是否执行 `mo remove`。Mole 的配置、日志及包管理器缓存是否保留取决于安装方式和版本，应先检查；不要把卸载盘览等同于清空这些数据。

## 功能

- **清理预览**：读取 Mole 的扫描清单，按分类、大小和路径筛选。选择受支持的缓存或废弃扩展，核对路径后移入废纸篓。
- **磁盘分析**：调用 Mole 的 JSON 分析，浏览启动磁盘或选定目录，逐层查看文件和目录的大小。无法读取的目录会标记为结果不完整。
- **应用使用与卸载**：读取 Spotlight 的最近使用记录，按时间筛选，标记正在运行和缺少记录的应用；通过 Mole 预览关联文件，再到终端确认卸载。
- **保护范围**：设置不允许从盘览移动的目录。首次运行时包含微信数据、用户的 ~/Documents 和 ~/go/pkg/mod，可以在界面中调整。

应用关闭后不常驻。重新扫描和磁盘分析时会运行 Mole，操作期间会临时增加资源占用。磁盘分析大小由 Mole 计算，可能与系统显示的实际占用空间不同。

## 从源码构建 macOS 版

- macOS 13 或更新版本。
- Xcode 或 Apple Command Line Tools（`xcode-select --install`）。
- 已安装的 Mole CLI。

在项目目录运行：

    ./build.sh
    open 盘览.app

构建使用当前机器的架构，并进行本地 ad-hoc 签名。源码仓库不包含已构建的应用包；预发布包可从 Releases 下载。安装到其他机器或公开分发时，需要自行处理签名与公证。

## 使用说明

打开盘览后点击「重新扫描」，或读取本机已有的 Mole 预览。勾选「仅可移入废纸篓」可以查看盘览支持操作的项目。按住 Command 可多选，确认框列出实际路径。盘览会在操作前重新核验路径和保护范围，完成后显示磁盘可用空间变化。

文件移入废纸篓后仍占用空间，清空废纸篓后才会释放。并非所有 Mole 候选都支持在盘览内处理，部分项目可以在 Finder 中定位。Mole 的预览中带 + 的数字表示有项目未能完整计量。

应用使用时间来自 macOS Spotlight 的 kMDItemLastUsedDate。系统记录可能缺失或滞后，命令行和后台启动也可能没有更新记录。正在运行的应用会单独标记；时间筛选用于初步检查。

应用卸载先调用 Mole 的 dry-run，显示 Mole 发现的关联文件；只有预览中的应用路径与所选路径一致时才可继续。继续后会在终端重新运行 Mole，必须再次核对应用路径及文件清单并在终端确认。Mole 的卸载不读取盘览的自定义保护范围，请勿确认包含受保护文件的清单；个人数据默认保留。系统应用、盘览自身、正在运行的应用和盘览保护范围内的应用不能从这里发起卸载。Mole 默认使用废纸篓，实际操作和剩余文件以 Mole 的提示为准。

目前清理预览由 Mole 生成，选中项目的移动由盘览完成。Mole 的清理命令没有指定单个预览项目的公开参数，因此盘览不会将选中项目的操作替换为范围更大的 `mo clean`。

Spotlight 索引、文件权限和完整磁盘访问权限会影响结果。盘览只读取本地数据，未实现数据上传。系统缓存和废纸篓的预览范围取决于 Mole 运行时权限。

## 测试

    ./test.sh

测试使用临时文件和模拟应用记录。窗口测试需要可用的 macOS 图形会话。测试不会清理用户文件。

## 关联项目与许可

盘览是独立的第三方客户端，与 Mole 项目没有官方关联。它依赖本机安装的 Mole CLI，未在仓库中打包 Mole。Mole 使用 GPL-3.0 许可，详见 [Mole 许可证](https://github.com/tw93/Mole/blob/main/LICENSE)。

盘览源码与图标使用 [GPL-3.0](LICENSE) 许可。
