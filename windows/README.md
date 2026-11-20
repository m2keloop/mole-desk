# 盘览 Windows 版

这是盘览的 Windows 原生界面移植，调用用户自行安装的 [Mole Windows CLI](https://github.com/tw93/Mole/tree/windows)。使用 Go 和 Windows 原生控件，不内置浏览器，也不打包 Mole。

## 当前功能

- 调用 `mo clean --dry-run`，显示 Mole 清理清单、预估总量和分类；支持搜索，并在资源管理器中定位选中路径。Mole 的预览并不保证每一项都有单独大小。
- 调用 `mo analyze --json`，浏览指定盘符或目录，双击目录可继续查看；大小和不完整标记来自 Mole。
- 调用 `mo uninstall --list` 显示应用清单，可搜索和定位安装目录。Windows 版 Mole 的列表不提供最近使用日期，界面显示“未记录”，不将安装或文件修改时间冒充使用时间。
- 启动 Mole 自带的卸载交互界面，用户在其中重新选择应用并确认。当前版本不会将盘览选中的应用自动传入 Mole，也不会自动确认。
- 调用 Mole 的 `clean --whitelist` 管理 Mole 清理保护名单。保护名单由 Mole 管理；它不能自动约束 Mole 卸载过程。

Windows 版暂未提供在盘览内逐项移入回收站、在 GUI 中逐项审阅卸载残留、应用最近使用天数和 macOS 版独立保护范围。可在资源管理器中手动处理已审阅的项目；盘览不会执行 `mo clean` 的实际清理，避免将逐项操作扩展为整机清理。

## 安装和运行

需要 Windows 10/11 和 [Mole Windows CLI](https://github.com/tw93/Mole/blob/windows/README.md)。在 Windows「设置 → 系统 → 关于」查看系统类型，从 [GitHub Releases](https://github.com/m2keloop/mole-desk/releases) 下载 `MoleDesk-Windows-x64.zip`（Intel / AMD）或 `MoleDesk-Windows-arm64.zip`（ARM64）。解压到你选择的文件夹，运行其中的 `MoleDesk.exe`。它是免安装程序，不会自动清理文件。

如需核对下载内容，可同时下载 `SHA256SUMS.txt`，在 PowerShell 运行 `Get-FileHash -Algorithm SHA256 下载包路径`，与文件中相应压缩包的值比较。Windows 测试包未签名，可能显示 SmartScreen 提示；请先确认下载来源和文件完整性。

如果已经安装 Scoop，可在 PowerShell 运行 `scoop install mole` 安装 Mole Windows CLI，并用 `mo --version` 验证。没有 Scoop 时请参考 [Mole 的 Windows 官方安装说明](https://github.com/tw93/Mole/blob/windows/README.md)。安装 Mole 后如果盘览未找到它，请关闭并重新打开盘览。支持 PATH 中的 `mo.exe`、Mole 标准脚本安装位置以及 Scoop 默认位置。请勿把 Mac 版 Mole 当作 Windows 版使用。

### 使用 AI 协助安装

使用有终端或文件访问能力的 AI 助手时，可以发送：

> 请帮我在这台 Windows 电脑上安装开源项目「盘览 Mole Desk」：https://github.com/m2keloop/mole-desk 。请先阅读项目 README 和 Releases，检查系统架构，下载对应的预发布包并核对 SHA-256；如尚未安装 Mole Windows CLI，请按官方说明协助安装并验证。安装期间不要清理文件、卸载其他应用或上传我的个人数据；遇到系统安全提示或需要更高权限时，请说明并由我处理。

Mole 项目也提供 [AI 安装说明](https://raw.githubusercontent.com/tw93/Mole/main/llms.txt)；盘览只需要其中的 Mole CLI。安装 AI 工具集成不是盘览的必要步骤。

## 卸载

退出盘览，将解压的 `MoleDesk.exe` 或整个盘览文件夹移到回收站即可。盘览是免安装程序，卸载它不会移除 Mole CLI、Mole 的配置或日志，也不会清理其他应用的文件。

如需单独移除 Mole：Scoop 安装的可以使用 `scoop uninstall mole`；通过官方脚本安装的可先运行 `mo remove --dry-run`，查看范围后再根据 [Mole 官方说明](https://github.com/tw93/Mole/blob/windows/README.md)决定是否执行 `mo remove`。如其他工具仍需要 Mole，请保留它。

## 从源码构建

构建需要 Go 1.22 或更高版本。在 macOS、Linux 运行 `./build.sh`；在 Windows PowerShell 中运行 `./build.ps1`。产物位于 `dist/`，不包含 Mole。

在 macOS 上可运行 `go test ./internal/mole` 测试清单解析，也可交叉编译 Windows 可执行文件。**交叉编译不能验证 Windows 界面、权限、终端交互或实际文件操作**；本次构建尚未经 Windows 实机验证。
