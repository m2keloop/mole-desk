// Package mole decodes the documented Windows Mole CLI outputs.
package mole

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"unicode/utf16"
	"unicode/utf8"
)

type CleanEntry struct {
	Category string
	Path     string
}
type CleanReport struct {
	Entries []CleanEntry
	Raw     string
}

// DecodeText handles both PowerShell 5.1 UTF-16 exports and UTF-8 exports.
func DecodeText(b []byte) (string, error) {
	switch {
	case bytes.HasPrefix(b, []byte{0xff, 0xfe}):
		b = b[2:]
		if len(b)%2 != 0 {
			return "", errors.New("invalid UTF-16 preview")
		}
		units := make([]uint16, len(b)/2)
		for i := range units {
			units[i] = binary.LittleEndian.Uint16(b[2*i:])
		}
		return string(utf16.Decode(units)), nil
	case bytes.HasPrefix(b, []byte{0xef, 0xbb, 0xbf}):
		b = b[3:]
	}
	if !utf8.Valid(b) {
		return "", errors.New("Mole preview encoding is not UTF-8 or UTF-16LE")
	}
	return string(b), nil
}

var windowsPath = regexp.MustCompile(`(?i)^[a-z]:\\`)

func ParseClean(data []byte) (CleanReport, error) {
	text, err := DecodeText(data)
	if err != nil {
		return CleanReport{}, err
	}
	if !strings.Contains(text, "# Mole Cleanup Preview - ") {
		return CleanReport{}, errors.New("unrecognized Mole cleanup preview")
	}
	var entries []CleanEntry
	group := ""
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "# ") {
			group = strings.TrimSpace(strings.TrimPrefix(line, "# "))
		} else if windowsPath.MatchString(line) || strings.HasPrefix(line, `\\`) {
			entries = append(entries, CleanEntry{Category: group, Path: line})
		}
	}
	return CleanReport{Entries: entries, Raw: text}, nil
}

type App struct {
	Name      string  `json:"name"`
	ID        string  `json:"id"`
	Source    string  `json:"source"`
	Version   *string `json:"version"`
	Publisher *string `json:"publisher"`
	Path      string  `json:"path"`
	Size      string  `json:"size"`
}

func ParseApps(data []byte) ([]App, error) {
	text, err := DecodeText(data)
	if err != nil {
		return nil, err
	}
	var apps []App
	if err = json.Unmarshal([]byte(text), &apps); err != nil {
		return nil, fmt.Errorf("Mole app list: %w", err)
	}
	if apps == nil {
		return nil, errors.New("Mole app list is not an array")
	}
	for _, app := range apps {
		if app.Name == "" || app.ID == "" {
			return nil, errors.New("incomplete Mole app record")
		}
	}
	return apps, nil
}

type DiskEntry struct {
	Name       string `json:"name"`
	Path       string `json:"path"`
	Size       int64  `json:"size"`
	IsDir      bool   `json:"is_dir"`
	ScanStatus string `json:"scan_status"`
}
type DiskReport struct {
	Path       string      `json:"path"`
	Entries    []DiskEntry `json:"entries"`
	ScanStatus string      `json:"scan_status"`
}

func ParseDisk(data []byte) (DiskReport, error) {
	text, err := DecodeText(data)
	if err != nil {
		return DiskReport{}, err
	}
	var result DiskReport
	if err = json.Unmarshal([]byte(text), &result); err != nil {
		return result, fmt.Errorf("Mole disk report: %w", err)
	}
	if result.Path == "" || result.Entries == nil {
		return result, errors.New("incomplete Mole disk report")
	}
	for _, entry := range result.Entries {
		if entry.Path == "" || entry.Size < 0 {
			return result, errors.New("invalid Mole disk entry")
		}
	}
	return result, nil
}

var ansi = regexp.MustCompile("\\x1b\\[[0-?]*[ -/]*[@-~]")

func PlainText(s string) string { return ansi.ReplaceAllString(s, "") }

// Mole reports a total on stdout, not individual sizes in clean-list.txt.
func CleanSummary(s string) string {
	for _, line := range strings.Split(PlainText(s), "\n") {
		if i := strings.Index(line, "Potential space:"); i >= 0 {
			return strings.TrimSpace(line[i:])
		}
	}
	return ""
}
