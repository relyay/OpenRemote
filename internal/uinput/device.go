//go:build linux

// Package uinput creates one virtual Microsoft Xbox 360 pad through /dev/uinput.
//
// The name, ids and axes follow the kernel xpad driver for product 045e:028e.
// Buttons stop at BTN_THUMBR. BTN_TL2 and BTN_TR2 are intentionally absent:
// triggers are ABS_Z and ABS_RZ (0..255), and those extra key bits would shift
// the indices SDL and Steam use for Back, Start and the stick clicks.
package uinput

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"openremote/internal/protocol"
)

const (
	deviceName = "Microsoft X-Box 360 pad"
	vendorID   = 0x045e
	productID  = 0x028e
	versionID  = 0x0114

	busUSB = 0x03

	evSyn = 0x00
	evKey = 0x01
	evAbs = 0x03

	synReport = 0

	btnA      = 0x130
	btnB      = 0x131
	btnX      = 0x133
	btnY      = 0x134
	btnTL     = 0x136
	btnTR     = 0x137
	btnSelect = 0x13a
	btnStart  = 0x13b
	btnMode   = 0x13c
	btnThumbL = 0x13d
	btnThumbR = 0x13e

	absX     = 0x00
	absY     = 0x01
	absZ     = 0x02
	absRX    = 0x03
	absRY    = 0x04
	absRZ    = 0x05
	absHat0X = 0x10
	absHat0Y = 0x11

	uiSetEvBit   = 0x40045564
	uiSetKeyBit  = 0x40045565
	uiDevCreate  = 0x5501
	uiDevDestroy = 0x5502
	uiDevSetup   = 0x405c5503
	uiAbsSetup   = 0x401c5504
	uiGetSysname = 0x8040552c // UI_GET_SYSNAME(64)
)

type inputEvent struct {
	Time  timeval
	Type  uint16
	Code  uint16
	Value int32
}

// uinputSetup is struct uinput_setup. The field order is the kernel layout.
type uinputSetup struct {
	BusType uint16
	Vendor  uint16
	Product uint16
	Version uint16
	Name    [80]byte
	FFMax   uint32
}

// absInfo is struct input_absinfo.
type absInfo struct {
	Value int32
	Min   int32
	Max   int32
	Fuzz  int32
	Flat  int32
	Res   int32
}

// absSetup is struct uinput_abs_setup, including the 2-byte pad before absinfo.
type absSetup struct {
	Code uint16
	Pad  uint16
	Info absInfo
}

// Device is one virtual Xbox 360 controller.
type Device struct {
	mu        sync.Mutex
	f         *os.File
	created   bool
	EventPath string
	JSPath    string
	SysName   string
}

// Create registers the pad with the kernel. The process needs write access
// to /dev/uinput, which usually means root or a udev rule.
func Create() (*Device, error) {
	f, err := os.OpenFile("/dev/uinput", os.O_WRONLY|syscall.O_NONBLOCK, 0)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, ErrDeviceNode
		}
		if errors.Is(err, syscall.EACCES) || errors.Is(err, syscall.EPERM) {
			return nil, ErrPermission
		}
		return nil, fmt.Errorf("open /dev/uinput: %w", err)
	}

	d := &Device{f: f}
	if err := d.setup(); err != nil {
		_ = f.Close()
		d.f = nil
		return nil, err
	}
	return d, nil
}

func (d *Device) setup() error {
	fd := d.f.Fd()
	if err := ioctl(fd, uiSetEvBit, evKey); err != nil {
		return fmt.Errorf("EV_KEY: %w", err)
	}
	if err := ioctl(fd, uiSetEvBit, evAbs); err != nil {
		return fmt.Errorf("EV_ABS: %w", err)
	}
	for _, key := range []uintptr{
		btnA, btnB, btnX, btnY,
		btnTL, btnTR,
		btnSelect, btnStart, btnMode,
		btnThumbL, btnThumbR,
	} {
		if err := ioctl(fd, uiSetKeyBit, key); err != nil {
			return fmt.Errorf("кнопка %d: %w", key, err)
		}
	}

	sticks := absInfo{Min: -32768, Max: 32767, Fuzz: 16, Flat: 128}
	triggers := absInfo{Min: 0, Max: 255}
	hat := absInfo{Min: -1, Max: 1}
	axes := []absSetup{
		{Code: absX, Info: sticks},
		{Code: absY, Info: sticks},
		{Code: absRX, Info: sticks},
		{Code: absRY, Info: sticks},
		{Code: absZ, Info: triggers},
		{Code: absRZ, Info: triggers},
		{Code: absHat0X, Info: hat},
		{Code: absHat0Y, Info: hat},
	}
	for i := range axes {
		if err := ioctlPtr(fd, uiAbsSetup, unsafe.Pointer(&axes[i])); err != nil {
			return fmt.Errorf("ось %d: %w", axes[i].Code, err)
		}
	}

	var setup uinputSetup
	setup.BusType = busUSB
	setup.Vendor = vendorID
	setup.Product = productID
	setup.Version = versionID
	copy(setup.Name[:], deviceName)
	if err := ioctlPtr(fd, uiDevSetup, unsafe.Pointer(&setup)); err != nil {
		return fmt.Errorf("UI_DEV_SETUP: %w", err)
	}
	if err := ioctl(fd, uiDevCreate, 0); err != nil {
		return fmt.Errorf("UI_DEV_CREATE: %w", err)
	}
	d.created = true

	var name [64]byte
	if err := ioctlPtr(fd, uiGetSysname, unsafe.Pointer(&name[0])); err == nil {
		if i := bytes.IndexByte(name[:], 0); i >= 0 {
			d.SysName = string(name[:i])
		} else {
			d.SysName = string(name[:])
		}
		d.EventPath, d.JSPath = waitNodes(d.SysName)
	}

	// Publish a centered pad. Games that read the current axis value then
	// see the sticks at rest and the triggers released.
	if err := d.write(centerEvents()); err != nil {
		_ = d.destroy()
		return err
	}
	return nil
}

// Set writes the evdev events that turn prev into next.
func (d *Device) Set(prev, next protocol.State) error {
	ev := diff(prev, next)
	if len(ev) == 0 {
		return nil
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.write(ev)
}

// Close removes the virtual pad from the kernel.
func (d *Device) Close() error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.f == nil {
		return nil
	}
	err := d.destroy()
	if cErr := d.f.Close(); err == nil {
		err = cErr
	}
	d.f = nil
	d.created = false
	return err
}

func (d *Device) destroy() error {
	if d.f == nil || !d.created {
		return nil
	}
	err := ioctl(d.f.Fd(), uiDevDestroy, 0)
	d.created = false
	return err
}

func (d *Device) write(ev []inputEvent) error {
	if d.f == nil {
		return ErrClosed
	}
	// One event per write. A short write that splits an input_event
	// desynchronizes every later button.
	for i := range ev {
		if err := d.writeEvent(&ev[i]); err != nil {
			return err
		}
	}
	return nil
}

func (d *Device) writeEvent(ev *inputEvent) error {
	b := unsafe.Slice((*byte)(unsafe.Pointer(ev)), int(unsafe.Sizeof(*ev)))
	retries := 0
	for len(b) > 0 {
		n, err := d.f.Write(b)
		if err != nil {
			if errors.Is(err, syscall.EAGAIN) || errors.Is(err, syscall.EWOULDBLOCK) {
				retries++
				if retries > 50 {
					return err
				}
				time.Sleep(time.Millisecond)
				continue
			}
			if errors.Is(err, os.ErrClosed) || errors.Is(err, syscall.ENODEV) {
				return ErrClosed
			}
			return err
		}
		if n == 0 {
			return errors.New("запись в uinput не продвинулась")
		}
		b = b[n:]
	}
	return nil
}

func centerEvents() []inputEvent {
	codes := []uint16{absX, absY, absZ, absRX, absRY, absRZ, absHat0X, absHat0Y}
	ev := make([]inputEvent, 0, len(codes)+1)
	for _, code := range codes {
		ev = append(ev, inputEvent{Type: evAbs, Code: code, Value: 0})
	}
	ev = append(ev, inputEvent{Type: evSyn, Code: synReport})
	return ev
}

func diff(prev, next protocol.State) []inputEvent {
	var ev []inputEvent
	addAbs := func(code uint16, value int32, changed bool) {
		if changed {
			ev = append(ev, inputEvent{Type: evAbs, Code: code, Value: value})
		}
	}
	addAbs(absX, int32(next.LX), prev.LX != next.LX)
	addAbs(absY, int32(next.LY), prev.LY != next.LY)
	addAbs(absRX, int32(next.RX), prev.RX != next.RX)
	addAbs(absRY, int32(next.RY), prev.RY != next.RY)
	addAbs(absZ, int32(next.LT), prev.LT != next.LT)
	addAbs(absRZ, int32(next.RT), prev.RT != next.RT)
	addAbs(absHat0X, int32(next.HatX), prev.HatX != next.HatX)
	addAbs(absHat0Y, int32(next.HatY), prev.HatY != next.HatY)

	changed := (prev.Buttons ^ next.Buttons) & protocol.BtnMask
	for bit := uint16(1); bit != 0 && bit <= protocol.BtnR3; bit <<= 1 {
		if changed&bit == 0 {
			continue
		}
		value := int32(0)
		if next.Buttons&bit != 0 {
			value = 1
		}
		ev = append(ev, inputEvent{Type: evKey, Code: buttonCode(bit), Value: value})
	}
	if len(ev) == 0 {
		return nil
	}
	ev = append(ev, inputEvent{Type: evSyn, Code: synReport})
	return ev
}

func buttonCode(bit uint16) uint16 {
	switch bit {
	case protocol.BtnA:
		return btnA
	case protocol.BtnB:
		return btnB
	case protocol.BtnX:
		return btnX
	case protocol.BtnY:
		return btnY
	case protocol.BtnLB:
		return btnTL
	case protocol.BtnRB:
		return btnTR
	case protocol.BtnBack:
		return btnSelect
	case protocol.BtnStart:
		return btnStart
	case protocol.BtnGuide:
		return btnMode
	case protocol.BtnL3:
		return btnThumbL
	case protocol.BtnR3:
		return btnThumbR
	default:
		return 0
	}
}

func waitNodes(sysName string) (eventPath, jsPath string) {
	if sysName == "" {
		return "", ""
	}
	for i := 0; i < 25; i++ {
		eventPath, jsPath = findNodes(sysName)
		if eventPath != "" {
			return eventPath, jsPath
		}
		time.Sleep(10 * time.Millisecond)
	}
	return "", ""
}

func findNodes(sysName string) (eventPath, jsPath string) {
	base := "/sys/class/input/" + sysName
	if matches, _ := filepath.Glob(base + "/event*"); len(matches) > 0 {
		eventPath = "/dev/input/" + filepath.Base(matches[0])
	}
	if matches, _ := filepath.Glob(base + "/js*"); len(matches) > 0 {
		jsPath = "/dev/input/" + filepath.Base(matches[0])
	}
	return eventPath, jsPath
}

func ioctl(fd, req, arg uintptr) error {
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd, req, arg)
	if errno != 0 {
		return errno
	}
	return nil
}

func ioctlPtr(fd, req uintptr, ptr unsafe.Pointer) error {
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd, req, uintptr(ptr))
	if errno != 0 {
		return errno
	}
	return nil
}
