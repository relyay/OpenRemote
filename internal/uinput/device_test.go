//go:build linux

package uinput

import (
	"encoding/binary"
	"errors"
	"math/big"
	"os"
	"runtime"
	"strings"
	"testing"
	"time"
	"unsafe"

	"openremote/internal/protocol"
)

func TestStructSizes(t *testing.T) {
	if unsafe.Sizeof(uinputSetup{}) != 92 {
		t.Fatalf("uinput_setup %d", unsafe.Sizeof(uinputSetup{}))
	}
	if unsafe.Sizeof(absSetup{}) != 28 {
		t.Fatalf("uinput_abs_setup %d", unsafe.Sizeof(absSetup{}))
	}
	switch runtime.GOARCH {
	case "amd64", "arm64", "loong64", "mips64", "mips64le", "ppc64", "ppc64le", "riscv64", "s390x":
		if unsafe.Sizeof(inputEvent{}) != 24 {
			t.Fatalf("input_event %d", unsafe.Sizeof(inputEvent{}))
		}
	case "386", "arm":
		if unsafe.Sizeof(inputEvent{}) != 16 {
			t.Fatalf("input_event %d", unsafe.Sizeof(inputEvent{}))
		}
	}
}

func TestDiffEmitsChangedControlsAndSyn(t *testing.T) {
	next := protocol.State{
		LX: 1000, LT: 255, HatX: -1,
		Buttons: protocol.BtnA | protocol.BtnGuide,
	}
	ev := diff(protocol.State{}, next)
	if len(ev) == 0 || ev[len(ev)-1].Type != evSyn {
		t.Fatalf("events %#v", ev)
	}
	got := map[uint16]inputEvent{}
	for _, e := range ev[:len(ev)-1] {
		got[e.Code] = e
	}
	if got[absX].Value != 1000 || got[absX].Type != evAbs {
		t.Fatalf("ABS_X %#v", got[absX])
	}
	if _, ok := got[absY]; ok {
		t.Fatal("unchanged ABS_Y was emitted")
	}
	if got[absZ].Value != 255 || got[absHat0X].Value != -1 {
		t.Fatalf("axes %#v", got)
	}
	if got[btnA].Type != evKey || got[btnA].Value != 1 {
		t.Fatalf("BTN_A %#v", got[btnA])
	}
	if got[btnMode].Value != 1 {
		t.Fatalf("guide %#v", got[btnMode])
	}

	back := diff(next, protocol.State{})
	released := false
	for _, e := range back {
		if e.Type == evKey && e.Code == btnA && e.Value == 0 {
			released = true
		}
	}
	if !released {
		t.Fatal("button release missing")
	}
	if diff(next, next) != nil {
		t.Fatal("identical state produced events")
	}
}

func TestVirtualXbox360(t *testing.T) {
	d, err := Create()
	if err != nil {
		if os.IsPermission(err) || errors.Is(err, ErrPermission) || errors.Is(err, ErrDeviceNode) {
			t.Skip(err)
		}
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.Close() })

	if d.SysName == "" {
		t.Fatal("kernel did not return a sysfs name")
	}
	block := ""
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) && block == "" {
		block = procBlock(d.SysName)
		if block == "" {
			time.Sleep(20 * time.Millisecond)
		}
	}
	if block == "" {
		t.Fatalf("device %s missing from /proc/bus/input/devices", d.SysName)
	}
	if !strings.Contains(block, `Name="Microsoft X-Box 360 pad"`) {
		t.Fatalf("name:\n%s", block)
	}
	if !strings.Contains(block, "Vendor=045e") || !strings.Contains(block, "Product=028e") {
		t.Fatalf("ids:\n%s", block)
	}
	bits := procBits(block)
	for _, bit := range []int{btnA, btnB, btnX, btnY, btnTL, btnTR, btnSelect, btnStart, btnMode, btnThumbL, btnThumbR} {
		if bits["KEY"].Bit(bit) == 0 {
			t.Errorf("KEY bit %d missing\n%s", bit, block)
		}
	}
	// Triggers must be axes. These key bits would shift SDL button indices.
	for _, bit := range []int{0x132, 0x135, 0x138, 0x139} {
		if bits["KEY"].Bit(bit) != 0 {
			t.Errorf("unexpected KEY bit %d\n%s", bit, block)
		}
	}
	for _, bit := range []int{absX, absY, absZ, absRX, absRY, absRZ, absHat0X, absHat0Y} {
		if bits["ABS"].Bit(bit) == 0 {
			t.Errorf("ABS bit %d missing\n%s", bit, block)
		}
	}

	if d.EventPath == "" {
		t.Fatalf("no event node for %s\n%s", d.SysName, block)
	}
	assertButtonReadback(t, d)
}

func assertButtonReadback(t *testing.T, d *Device) {
	t.Helper()
	f, err := os.Open(d.EventPath)
	if err != nil {
		t.Logf("event node is not readable, skip readback: %v", err)
		return
	}
	defer f.Close()

	prev := protocol.State{}
	next := protocol.State{Buttons: protocol.BtnA, LY: 20000, LT: 200, HatY: -1}
	if err := d.Set(prev, next); err != nil {
		t.Fatal(err)
	}
	_ = f.SetReadDeadline(time.Now().Add(time.Second))
	buf := make([]byte, int(unsafe.Sizeof(inputEvent{}))*16)
	gotA := false
	gotY := false
	gotZ := false
	gotHat := false
	for !gotA || !gotY || !gotZ || !gotHat {
		n, err := f.Read(buf)
		if err != nil {
			t.Fatalf("read events (a=%v y=%v z=%v hat=%v): %v", gotA, gotY, gotZ, gotHat, err)
		}
		sz := int(unsafe.Sizeof(inputEvent{}))
		for off := 0; off+sz <= n; off += sz {
			ev := parseEvent(buf[off : off+sz])
			switch {
			case ev.Type == evKey && ev.Code == btnA && ev.Value == 1:
				gotA = true
			case ev.Type == evAbs && ev.Code == absY && ev.Value == 20000:
				gotY = true
			case ev.Type == evAbs && ev.Code == absZ && ev.Value == 200:
				gotZ = true
			case ev.Type == evAbs && ev.Code == absHat0Y && ev.Value == -1:
				gotHat = true
			}
		}
	}
}

func parseEvent(b []byte) inputEvent {
	var ev inputEvent
	ev.Type = binary.LittleEndian.Uint16(b[len(b)-8 : len(b)-6])
	ev.Code = binary.LittleEndian.Uint16(b[len(b)-6 : len(b)-4])
	ev.Value = int32(binary.LittleEndian.Uint32(b[len(b)-4:]))
	return ev
}

func procBlock(sysName string) string {
	data, err := os.ReadFile("/proc/bus/input/devices")
	if err != nil {
		return ""
	}
	needle := "/devices/virtual/input/" + sysName
	for _, block := range strings.Split(string(data), "\n\n") {
		if strings.Contains(block, needle) {
			return block
		}
	}
	return ""
}

func procBits(block string) map[string]*big.Int {
	out := map[string]*big.Int{}
	for _, line := range strings.Split(block, "\n") {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "B: ") {
			continue
		}
		rest := strings.TrimPrefix(line, "B: ")
		name, bits, ok := strings.Cut(rest, "=")
		if !ok {
			continue
		}
		out[name] = parseBitmap(bits)
	}
	for _, name := range []string{"KEY", "ABS"} {
		if out[name] == nil {
			out[name] = new(big.Int)
		}
	}
	return out
}

func parseBitmap(s string) *big.Int {
	n := new(big.Int)
	for _, field := range strings.Fields(s) {
		n.Lsh(n, 64)
		word, ok := new(big.Int).SetString(field, 16)
		if !ok {
			continue
		}
		n.Or(n, word)
	}
	return n
}
