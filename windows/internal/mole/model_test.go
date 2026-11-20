package mole

import (
	"encoding/binary"
	"strings"
	"testing"
	"unicode/utf16"
)

func TestCleanWindowsReport(t *testing.T) {
	input := "# Mole Cleanup Preview - 2026-01-01\r\n# Browser cache\r\nC:\\Users\\名字\\AppData\\cache\r\n\\\\server\\share\\file\r\n"
	u := utf16.Encode([]rune(input))
	data := []byte{0xff, 0xfe}
	for _, n := range u {
		b := make([]byte, 2)
		binary.LittleEndian.PutUint16(b, n)
		data = append(data, b...)
	}
	report, err := ParseClean(data)
	if err != nil || len(report.Entries) != 2 || report.Entries[0].Category != "Browser cache" || !strings.Contains(report.Entries[0].Path, "名字") {
		t.Fatalf("%+v %v", report, err)
	}
	if _, err = ParseClean([]byte("not a Mole report")); err == nil {
		t.Fatal("invalid report accepted")
	}
}
func TestAppAndDiskJSON(t *testing.T) {
	apps, err := ParseApps([]byte(`[{"name":"\u5fae\u4fe1","id":"registry:x","path":"C:\\App"}]`))
	if err != nil || len(apps) != 1 || apps[0].Name != "微信" {
		t.Fatal(apps, err)
	}
	if _, err = ParseApps([]byte(`[{"name":"x"}]`)); err == nil {
		t.Fatal("missing ID accepted")
	}
	disk, err := ParseDisk([]byte(`{"path":"C:\\","scan_status":"complete","entries":[{"path":"C:\\test","name":"test","size":3,"is_dir":true}]}`))
	if err != nil || len(disk.Entries) != 1 {
		t.Fatal(disk, err)
	}
	if _, err = ParseDisk([]byte(`{"path":"C:\\","entries":[{"path":"x","size":-1}]}`)); err == nil {
		t.Fatal("negative size accepted")
	}
	if PlainText("\x1b[31mred\x1b[0m") != "red" {
		t.Fatal("ANSI escaping")
	}
	if CleanSummary("\x1b[32mPotential space: 1.5 GB\x1b[0m | Items: 2") != "Potential space: 1.5 GB | Items: 2" {
		t.Fatal("cleanup summary")
	}
}
