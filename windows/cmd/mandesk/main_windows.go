//go:build windows

package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"unsafe"

	"github.com/m2keloop/mole-desk/windows/internal/mole"
)

var (
	user32           = syscall.NewLazyDLL("user32.dll")
	kernel32         = syscall.NewLazyDLL("kernel32.dll")
	gdi32            = syscall.NewLazyDLL("gdi32.dll")
	registerClass    = user32.NewProc("RegisterClassExW")
	createWindow     = user32.NewProc("CreateWindowExW")
	defWindowProc    = user32.NewProc("DefWindowProcW")
	getMessage       = user32.NewProc("GetMessageW")
	translateMessage = user32.NewProc("TranslateMessage")
	dispatchMessage  = user32.NewProc("DispatchMessageW")
	showWindow       = user32.NewProc("ShowWindow")
	updateWindow     = user32.NewProc("UpdateWindow")
	postQuitMessage  = user32.NewProc("PostQuitMessage")
	sendMessage      = user32.NewProc("SendMessageW")
	postMessage      = user32.NewProc("PostMessageW")
	setWindowText    = user32.NewProc("SetWindowTextW")
	getWindowText    = user32.NewProc("GetWindowTextW")
	moveWindow       = user32.NewProc("MoveWindow")
	messageBox       = user32.NewProc("MessageBoxW")
	loadCursor       = user32.NewProc("LoadCursorW")
	getModuleHandle  = kernel32.NewProc("GetModuleHandleW")
	getStockObject   = gdi32.NewProc("GetStockObject")
)

const (
	wmDestroy          = 0x0002
	wmSize             = 0x0005
	wmCommand          = 0x0111
	wmResult           = 0x8001
	wmSetFont          = 0x0030
	wsOverlappedWindow = 0x00cf0000
	wsChild            = 0x40000000
	wsVisible          = 0x10000000
	wsBorder           = 0x00800000
	wsVScroll          = 0x00200000
	wsTabStop          = 0x00010000
	lbAddString        = 0x0180
	lbResetContent     = 0x0184
	lbGetCurSel        = 0x0188
	lbnSelChange       = 1
	lbnDblClick        = 2
	enChange           = 0x0300
	idClean            = 101
	idDisk             = 102
	idApps             = 103
	idUninstall        = 104
	idWhitelist        = 105
	idStop             = 106
	idOpen             = 107
	idUp               = 108
	idList             = 201
	idPath             = 202
	idSearch           = 203
	idDetail           = 204
	idStatus           = 205
	idTitle            = 206
	idPathLabel        = 207
	idSearchLabel      = 208
)

type point struct{ X, Y int32 }
type message struct {
	HWnd           uintptr
	Message        uint32
	WParam, LParam uintptr
	Time           uint32
	Pt             point
	Private        uint32
}
type windowClass struct {
	Size, Style                                                        uint32
	WndProc                                                            uintptr
	ClsExtra, WndExtra                                                 int32
	Instance, Icon, Cursor, Background, MenuName, ClassName, SmallIcon uintptr
}
type row struct {
	label, detail, path string
	directory           bool
}
type result struct {
	kind               string
	rows               []row
	info, detail, path string
	err                error
}
type window struct {
	hwnd          uintptr
	controls      map[int]uintptr
	rows, visible []row
	kind, current string
	cancel        context.CancelFunc
	sequence      uint64
	pending       map[uint64]result
	mu            sync.Mutex
}

var app *window

func wide(s string) *uint16 {
	p, e := syscall.UTF16PtrFromString(s)
	if e != nil {
		return syscall.StringToUTF16Ptr("无效文本")
	}
	return p
}
func text(h uintptr, s string) { setWindowText.Call(h, uintptr(unsafe.Pointer(wide(s)))) }
func getText(h uintptr) string {
	buf := make([]uint16, 32768)
	getWindowText.Call(h, uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
	return syscall.UTF16ToString(buf)
}
func alert(title, body string) {
	messageBox.Call(app.hwnd, uintptr(unsafe.Pointer(wide(body))), uintptr(unsafe.Pointer(wide(title))), 0x40)
}
func confirm(title, body string) bool {
	v, _, _ := messageBox.Call(app.hwnd, uintptr(unsafe.Pointer(wide(body))), uintptr(unsafe.Pointer(wide(title))), 0x24|0x100)
	return v == 6
}
func child(class, title string, style uint32, id int) uintptr {
	inst, _, _ := getModuleHandle.Call(0)
	h, _, _ := createWindow.Call(0, uintptr(unsafe.Pointer(wide(class))), uintptr(unsafe.Pointer(wide(title))), uintptr(style|wsChild|wsVisible), 0, 0, 0, 0, app.hwnd, uintptr(id), inst, 0)
	font, _, _ := getStockObject.Call(17)
	sendMessage.Call(h, wmSetFont, font, 1)
	app.controls[id] = h
	return h
}
func place(id, x, y, w, h int) {
	if w < 0 {
		w = 0
	}
	if h < 0 {
		h = 0
	}
	moveWindow.Call(app.controls[id], uintptr(x), uintptr(y), uintptr(w), uintptr(h), 1)
}
func (w *window) layout(width, height int) {
	place(idTitle, 20, 14, width-40, 30)
	place(idClean, 20, 50, 125, 30)
	place(idDisk, 153, 50, 110, 30)
	place(idApps, 271, 50, 110, 30)
	place(idUninstall, 389, 50, 145, 30)
	place(idWhitelist, 542, 50, 125, 30)
	place(idStop, 675, 50, 90, 30)
	place(idPathLabel, 20, 95, 42, 22)
	place(idPath, 65, 92, width/2-75, 27)
	place(idSearchLabel, width/2+10, 95, 42, 22)
	place(idSearch, width/2+55, 92, width/2-75, 27)
	tableH := height - 225
	if tableH < 70 {
		tableH = 70
	}
	place(idList, 20, 130, width-40, tableH)
	place(idDetail, 20, 138+tableH, width-40, 53)
	place(idStatus, 20, 198+tableH, width-295, 23)
	place(idUp, width-262, 194+tableH, 105, 30)
	place(idOpen, width-147, 194+tableH, 125, 30)
}
func (w *window) filter() {
	query := strings.ToLower(strings.TrimSpace(getText(w.controls[idSearch])))
	sendMessage.Call(w.controls[idList], lbResetContent, 0, 0)
	w.visible = w.visible[:0]
	for _, r := range w.rows {
		if query != "" && !strings.Contains(strings.ToLower(r.label+" "+r.path), query) {
			continue
		}
		if len(w.visible) >= 5000 {
			break
		}
		w.visible = append(w.visible, r)
		sendMessage.Call(w.controls[idList], lbAddString, 0, uintptr(unsafe.Pointer(wide(r.label))))
	}
	text(w.controls[idDetail], "选择一项查看路径和详情。")
}
func (w *window) selected() (row, bool) {
	n, _, _ := sendMessage.Call(w.controls[idList], lbGetCurSel, 0, 0)
	i := int(int32(n))
	if i < 0 || i >= len(w.visible) {
		return row{}, false
	}
	return w.visible[i], true
}
func (w *window) open() {
	r, ok := w.selected()
	if !ok || r.path == "" {
		alert("没有路径", "请先选择有路径的项目。 ")
		return
	}
	if !filepath.IsAbs(r.path) {
		alert("路径无效", "无法在资源管理器中显示此路径。")
		return
	}
	cmd := exec.Command("explorer.exe", "/select,", r.path)
	if e := cmd.Start(); e != nil {
		alert("无法打开资源管理器", e.Error())
	} else {
		_ = cmd.Process.Release()
	}
}
func (w *window) start(kind, path string) {
	if w.cancel != nil {
		alert("正在运行", "请等待或先停止当前操作。")
		return
	}
	m, err := findMole()
	if err != nil {
		alert("找不到 Mole", err.Error())
		return
	}
	ctx, cancel := context.WithCancel(context.Background())
	w.cancel = cancel
	w.sequence++
	sequence := w.sequence
	text(w.controls[idStatus], "Mole 正在运行，可点击停止。")
	go func() {
		r := result{kind: kind, path: path}
		switch kind {
		case "clean":
			report, out, e := readClean(ctx, m)
			r.err = e
			r.detail = out
			if e == nil {
				for _, item := range report.Entries {
					r.rows = append(r.rows, row{label: item.Category + "  ·  " + item.Path, detail: item.Category + "\r\n" + item.Path, path: item.Path})
				}
				r.info = fmt.Sprintf("Mole 清理预览 · %d 项；选择后可在资源管理器中检查", len(r.rows))
				if summary := mole.CleanSummary(out); summary != "" {
					r.info = fmt.Sprintf("Mole 清理预览 · %d 项 · %s", len(r.rows), summary)
				}
			}
		case "apps":
			apps, e := scanApps(ctx, m)
			r.err = e
			if e == nil {
				for _, a := range apps {
					r.rows = append(r.rows, row{label: a.Name + "  ·  " + a.Size, detail: fmt.Sprintf("%s\r\n来源：%s   版本：%s\r\n路径：%s\r\n最近使用时间：未记录", a.Name, a.Source, optional(a.Version), a.Path), path: a.Path})
				}
				r.info = fmt.Sprintf("Mole 应用列表 · %d 项；Windows 最近使用时间未提供", len(r.rows))
			}
		case "disk":
			disk, e := scanDisk(ctx, m, path)
			r.err = e
			if e == nil {
				r.path = disk.Path
				for _, item := range disk.Entries {
					if !filepath.IsAbs(item.Path) || !strings.EqualFold(filepath.Clean(filepath.Dir(item.Path)), filepath.Clean(disk.Path)) {
						continue
					}
					r.rows = append(r.rows, row{label: fmt.Sprintf("%s  ·  %s", item.Name, sizeText(item.Size)), detail: item.Path + "\r\n大小：" + sizeText(item.Size), path: item.Path, directory: item.IsDir})
				}
				r.info = fmt.Sprintf("Mole 磁盘分析 · %d 项", len(r.rows))
				if disk.ScanStatus != "complete" {
					r.info += " · 结果可能不完整"
				}
			}
		}
		w.mu.Lock()
		w.pending[sequence] = r
		w.mu.Unlock()
		postMessage.Call(w.hwnd, wmResult, uintptr(sequence), 0)
	}()
}
func optional(s *string) string {
	if s == nil || *s == "" {
		return "未记录"
	}
	return *s
}
func sizeText(n int64) string {
	if n < 1000 {
		return fmt.Sprintf("%d B", n)
	}
	v := float64(n)
	units := []string{"B", "KB", "MB", "GB", "TB"}
	i := 0
	for v >= 1000 && i < len(units)-1 {
		v /= 1000
		i++
	}
	return fmt.Sprintf("%.1f %s", v, units[i])
}
func (w *window) finish(seq uint64) {
	w.mu.Lock()
	r, ok := w.pending[seq]
	delete(w.pending, seq)
	w.mu.Unlock()
	if !ok || seq != w.sequence {
		return
	}
	if w.cancel != nil {
		w.cancel()
		w.cancel = nil
	}
	if r.err != nil {
		text(w.controls[idStatus], "未完成")
		if r.err == context.Canceled {
			text(w.controls[idStatus], "已请求停止。子进程可能仍在结束中。")
			return
		}
		alert("Mole 操作未完成", r.err.Error())
		return
	}
	w.kind = r.kind
	w.rows = r.rows
	if r.kind == "disk" {
		w.current = r.path
		text(w.controls[idPath], r.path)
	}
	w.filter()
	text(w.controls[idStatus], r.info)
	if len(w.rows) == 0 && r.detail != "" {
		text(w.controls[idDetail], r.detail)
	}
}
func (w *window) interactive(args ...string) {
	m, err := findMole()
	if err != nil {
		alert("找不到 Mole", err.Error())
		return
	}
	title := "Mole 卸载"
	body := "将打开 Mole 的终端界面。请在终端重新选择应用并核对清单，再由你确认。盘览当前选中的行不会自动传给 Mole。"
	if len(args) > 0 && args[0] == "clean" {
		title = "Mole 保护名单"
		body = "将打开 Mole 的保护名单编辑器。设置适用于 Mole 清理。"
	}
	if !confirm(title, body) {
		return
	}
	if err = m.interactive(args...); err != nil {
		alert("无法打开 Mole", err.Error())
	}
}
func wndProc(hwnd uintptr, msg uint32, wp, lp uintptr) uintptr {
	switch msg {
	case wmSize:
		if app != nil {
			app.layout(int(uint16(lp)), int(uint16(lp>>16)))
		}
		return 0
	case wmResult:
		if app != nil {
			app.finish(uint64(wp))
		}
		return 0
	case wmCommand:
		if app == nil {
			break
		}
		id := int(uint16(wp))
		event := int(uint16(wp >> 16))
		switch id {
		case idClean:
			app.start("clean", "")
		case idDisk:
			app.start("disk", getText(app.controls[idPath]))
		case idApps:
			app.start("apps", "")
		case idUninstall:
			app.interactive("uninstall")
		case idWhitelist:
			app.interactive("clean", "--whitelist")
		case idStop:
			if app.cancel != nil {
				app.cancel()
				text(app.controls[idStatus], "正在停止…")
			}
		case idOpen:
			app.open()
		case idUp:
			if app.kind == "disk" && app.current != "" {
				parent := filepath.Dir(app.current)
				if !strings.EqualFold(parent, app.current) {
					app.start("disk", parent)
				}
			}
		case idList:
			if event == lbnSelChange || event == lbnDblClick {
				if r, ok := app.selected(); ok {
					text(app.controls[idDetail], r.detail)
					if event == lbnDblClick && app.kind == "disk" && r.directory {
						app.start("disk", r.path)
					}
				}
			}
		case idSearch:
			if event == enChange {
				app.filter()
			}
		}
		return 0
	case wmDestroy:
		if app != nil && app.cancel != nil {
			app.cancel()
		}
		postQuitMessage.Call(0)
		return 0
	}
	v, _, _ := defWindowProc.Call(hwnd, uintptr(msg), wp, lp)
	return v
}
func main() {
	runtime.LockOSThread()
	app = &window{controls: map[int]uintptr{}, pending: map[uint64]result{}}
	inst, _, _ := getModuleHandle.Call(0)
	cursor, _, _ := loadCursor.Call(0, 32512)
	name := wide("MoleDeskWindows")
	class := windowClass{Size: uint32(unsafe.Sizeof(windowClass{})), WndProc: syscall.NewCallback(wndProc), Instance: inst, Cursor: cursor, Background: 6, ClassName: uintptr(unsafe.Pointer(name))}
	if ok, _, _ := registerClass.Call(uintptr(unsafe.Pointer(&class))); ok == 0 {
		return
	}
	h, _, _ := createWindow.Call(0, uintptr(unsafe.Pointer(name)), uintptr(unsafe.Pointer(wide("盘览 · Mole Desk"))), wsOverlappedWindow, 100, 100, 1040, 690, 0, 0, inst, 0)
	if h == 0 {
		return
	}
	app.hwnd = h
	child("STATIC", "盘览  ·  Mole Windows 磁盘与应用管理", 0, idTitle)
	child("STATIC", "路径", 0, idPathLabel)
	child("STATIC", "搜索", 0, idSearchLabel)
	for _, v := range []struct {
		id    int
		label string
	}{{idClean, "清理预览"}, {idDisk, "磁盘分析"}, {idApps, "应用列表"}, {idUninstall, "Mole 卸载…"}, {idWhitelist, "保护名单…"}, {idStop, "停止"}, {idOpen, "在资源管理器显示"}, {idUp, "上一级"}} {
		child("BUTTON", v.label, wsTabStop, v.id)
	}
	root := os.Getenv("SystemDrive")
	if root == "" {
		root = "C:"
	}
	child("EDIT", root+"\\", wsBorder|wsTabStop|0x0080, idPath)
	child("EDIT", "", wsBorder|wsTabStop|0x0080, idSearch)
	child("LISTBOX", "", wsBorder|wsVScroll|wsTabStop|0x0001|0x0100, idList)
	child("EDIT", "选择一项查看路径和详情。", wsBorder|wsVScroll|0x0004|0x0800|0x0040, idDetail)
	child("STATIC", "请选择功能；操作仅在本机运行。", 0, idStatus)
	app.layout(1024, 650)
	showWindow.Call(h, 1)
	updateWindow.Call(h)
	var msg message
	for {
		v, _, _ := getMessage.Call(uintptr(unsafe.Pointer(&msg)), 0, 0, 0)
		if int32(v) <= 0 {
			break
		}
		translateMessage.Call(uintptr(unsafe.Pointer(&msg)))
		dispatchMessage.Call(uintptr(unsafe.Pointer(&msg)))
	}
}
