# 盘览 Windows 版

这是盘览的 Windows 原生界面移植，调用用户自行安装的 [Mole Windows CLI](https://github.com/tw93/Mole/tree/windows)。使用 Go 和 Windows 原生控件，不内置浏览器，也不打包 Mole。

## 当前功能

- 调用 `mo clean --dry-run`，显示 Mole 清理清单、预估总量和分类；支持搜索，并在资源管理器中定位选中路径。Mole 的预览并不保证每一项都有单独大小。
- 调用 `mo analyze --json`，浏览指定盘符或目录，双击目录可继续查看；大小和不完整标记来自 Mole。
- 调用 `mo uninstall --list` 显示应用清单，可搜索和定位安装目录。Windows 版 Mole 的列表不提供最近使用日期，界面显示“未记录”，不将安装或文件修改时间冒充使用时间。
- 启动 Mole 自带的卸载交互界面，用户在其中重新选择应用并确认。当前版本不会将盘览选中的应用自动传入 Mole，也不会自动确认。
- 调用 Mole 的 `clean --whitelist` 管理 Mole 清理保护名单。保护名单由 Mole 管理；它不能自动约束 Mole 卸载过程。

Windows 版暂未提供在盘览内逐项移入回收站、在 GUI 中逐项审阅卸载残留、应用最近使用天数和 macOS 版独立保护范围。可在资源管理器中手动处理已审阅的项目；盘览不会执行 `mo clean` 的实际清理，避免将逐项操作扩展为整机清理。

## 运行与构建

需要 Windows 10/11 和 [Mole Windows CLI](https://github.com/tw93/Mole/blob/windows/README.md)。运行 `dist/MoleDesk-windows-amd64.exe`（Intel/AMD）或 `dist/MoleDesk-windows-arm64.exe`（ARM64）；按提示执行清理预览，不会自动执行卸载或清理。

安装 Mole 后如果盘览未找到它，请关闭并重新打开盘览。支持 PATH 中的 `mo.exe`、Mole 标准脚本安装位置以及 Scoop 默认位置。请勿把 Mac 版 Mole 当作 Windows 版使用。

构建需要 Go 1.22 或更高版本。在 macOS、Linux 运行 `./build.sh`；在 Windows PowerShell 中运行 `./build.ps1`。产物位于 `dist/`，不包含 Mole。

在 macOS 上可运行 `go test ./internal/mole` 测试清单解析，也可交叉编译 Windows 可执行文件。**交叉编译不能验证 Windows 界面、权限、终端交互或实际文件操作**；本次构建尚未经 Windows 实机验证。
