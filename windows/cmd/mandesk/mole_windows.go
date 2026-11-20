//go:build windows

package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"

	"github.com/m2keloop/mole-desk/windows/internal/mole"
)

const (
	createNoWindow = 0x08000000
	maxOutput      = 16 << 20
)

type moleCommand struct {
	file   string
	prefix []string
}

// Windows PowerShell 5.1 can write BOM-less ANSI using the system code page.
func decodeWindowsText(data []byte) (string, error) {
	if decoded, err := mole.DecodeText(data); err == nil {
		return decoded, nil
	}
	if len(data) == 0 {
		return "", nil
	}
	convert := syscall.NewLazyDLL("kernel32.dll").NewProc("MultiByteToWideChar")
	n, _, _ := convert.Call(0, 0, uintptr(unsafe.Pointer(&data[0])), uintptr(len(data)), 0, 0)
	if n == 0 {
		return "", errors.New("无法读取 Mole 输出的文本编码。")
	}
	wide := make([]uint16, int(n))
	ok, _, _ := convert.Call(0, 0, uintptr(unsafe.Pointer(&data[0])), uintptr(len(data)), uintptr(unsafe.Pointer(&wide[0])), n)
	if ok == 0 {
		return "", errors.New("无法读取 Mole 输出的文本编码。")
	}
	return syscall.UTF16ToString(wide), nil
}

func findMole() (moleCommand, error) {
	if exe, err := exec.LookPath("mo.exe"); err == nil {
		return moleCommand{file: exe}, nil
	}
	var candidates []string
	if local := os.Getenv("LOCALAPPDATA"); local != "" {
		candidates = append(candidates, filepath.Join(local, "Programs", "mole-cli", "mole.ps1"))
	}
	if scoop := os.Getenv("SCOOP"); scoop != "" {
		candidates = append(candidates, filepath.Join(scoop, "apps", "mole", "current", "mole.ps1"))
	}
	if home := os.Getenv("USERPROFILE"); home != "" {
		candidates = append(candidates, filepath.Join(home, "scoop", "apps", "mole", "current", "mole.ps1"))
	}
	if ps, err := exec.LookPath("mole.ps1"); err == nil {
		candidates = append(candidates, ps)
	}
	powershell := filepath.Join(os.Getenv("SystemRoot"), "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
	for _, path := range candidates {
		if stat, err := os.Stat(path); err == nil && !stat.IsDir() {
			return moleCommand{file: powershell, prefix: []string{"-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", path}}, nil
		}
	}
	return moleCommand{}, errors.New("未找到 Windows 版 Mole，请先安装并重启盘览。")
}

type limitedBuffer struct {
	bytes.Buffer
	exceeded bool
}

func (b *limitedBuffer) Write(p []byte) (int, error) {
	n := len(p)
	remaining := maxOutput - b.Len()
	if remaining > 0 {
		if remaining < len(p) {
			_, _ = b.Buffer.Write(p[:remaining])
			b.exceeded = true
		} else {
			_, _ = b.Buffer.Write(p)
		}
	} else {
		b.exceeded = true
	}
	return n, nil
}
func (m moleCommand) run(ctx context.Context, args ...string) ([]byte, error) {
	argv := append(append([]string{}, m.prefix...), args...)
	cmd := exec.CommandContext(ctx, m.file, argv...)
	cmd.SysProcAttr = &syscall.SysProcAttr{CreationFlags: createNoWindow}
	var output, diagnostic limitedBuffer
	cmd.Stdout = &output
	cmd.Stderr = &diagnostic
	err := cmd.Run()
	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	if output.exceeded || diagnostic.exceeded {
		return nil, errors.New("Mole 输出过大，已停止读取。")
	}
	if err != nil {
		msg := strings.TrimSpace(mole.PlainText(diagnostic.String()))
		if msg == "" {
			msg = err.Error()
		}
		return nil, fmt.Errorf("Mole 运行失败：%s", msg)
	}
	return output.Bytes(), nil
}
func (m moleCommand) interactive(args ...string) error {
	// Pass only fixed commands, never names, paths or text through a shell.
	for _, arg := range args {
		if arg != "uninstall" && arg != "clean" && arg != "--whitelist" {
			return errors.New("unsupported interactive command")
		}
	}
	prefix := append([]string{}, m.prefix...)
	if len(prefix) > 0 {
		prefix = []string{"-NoLogo", "-NoExit", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", prefix[len(prefix)-1]}
	}
	argv := append(prefix, args...)
	quoted := make([]string, len(argv))
	for i, arg := range argv {
		quoted[i] = syscall.EscapeArg(arg)
	}
	params := strings.Join(quoted, " ")
	shell := syscall.NewLazyDLL("shell32.dll").NewProc("ShellExecuteW")
	result, _, _ := shell.Call(0, uintptr(unsafe.Pointer(wide("open"))), uintptr(unsafe.Pointer(wide(m.file))),
		uintptr(unsafe.Pointer(wide(params))), 0, 1)
	if result <= 32 {
		return fmt.Errorf("无法启动终端（错误代码 %d）", result)
	}
	return nil
}
func readClean(ctx context.Context, m moleCommand) (mole.CleanReport, string, error) {
	home := os.Getenv("USERPROFILE")
	if home == "" {
		return mole.CleanReport{}, "", errors.New("无法确定用户目录。")
	}
	path := filepath.Join(home, ".config", "mole", "clean-list.txt")
	before, _ := os.Stat(path)
	out, err := m.run(ctx, "clean", "--dry-run")
	if err != nil {
		return mole.CleanReport{}, "", err
	}
	info, err := os.Stat(path)
	if err != nil {
		return mole.CleanReport{}, "", errors.New("Mole 未写入预览清单；请检查权限。")
	}
	if info.Size() > maxOutput {
		return mole.CleanReport{}, "", errors.New("预览清单过大。")
	}
	if before != nil && !info.ModTime().After(before.ModTime()) {
		return mole.CleanReport{}, "", errors.New("Mole 预览清单未更新，已拒绝使用旧结果。")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return mole.CleanReport{}, "", err
	}
	decoded, err := decodeWindowsText(data)
	if err != nil {
		return mole.CleanReport{}, "", err
	}
	report, err := mole.ParseClean([]byte(decoded))
	if err != nil {
		return mole.CleanReport{}, "", err
	}
	outText, err := decodeWindowsText(out)
	if err != nil {
		return mole.CleanReport{}, "", err
	}
	output := mole.PlainText(outText)
	if !strings.Contains(strings.ToLower(output), "dry run complete") {
		return mole.CleanReport{}, "", errors.New("Mole 未确认预览完成，结果未展示。")
	}
	return report, output, nil
}
func scanApps(ctx context.Context, m moleCommand) ([]mole.App, error) {
	out, err := m.run(ctx, "uninstall", "--list")
	if err != nil {
		return nil, err
	}
	text, err := decodeWindowsText(out)
	if err != nil {
		return nil, err
	}
	return mole.ParseApps([]byte(text))
}
func scanDisk(ctx context.Context, m moleCommand, path string) (mole.DiskReport, error) {
	path = filepath.Clean(path)
	if !filepath.IsAbs(path) {
		return mole.DiskReport{}, errors.New("请输入 Windows 绝对路径，例如 C:\\。")
	}
	out, err := m.run(ctx, "analyze", "--json", path)
	if err != nil {
		return mole.DiskReport{}, err
	}
	text, err := decodeWindowsText(out)
	if err != nil {
		return mole.DiskReport{}, err
	}
	report, err := mole.ParseDisk([]byte(text))
	if err != nil {
		return report, err
	}
	if !strings.EqualFold(filepath.Clean(report.Path), path) {
		return mole.DiskReport{}, errors.New("Mole 返回的目录与请求不一致。")
	}
	return report, nil
}
