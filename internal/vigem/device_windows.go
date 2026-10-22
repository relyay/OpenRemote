//go:build windows

package vigem

import (
	"errors"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"openremote/internal/protocol"
)

var (
	cfgmgr32          = syscall.NewLazyDLL("cfgmgr32.dll")
	procInterfaceSize = cfgmgr32.NewProc("CM_Get_Device_Interface_List_SizeW")
	procInterfaceList = cfgmgr32.NewProc("CM_Get_Device_Interface_ListW")
	busInterface      = syscall.GUID{Data1: 0x96E42B22, Data2: 0xF5E9, Data3: 0x42F8, Data4: [8]byte{0xB0, 0x43, 0xED, 0x0F, 0x93, 0x2F, 0x01, 0x4F}}
	errInvalidParam   = syscall.Errno(87) // ERROR_INVALID_PARAMETER
)

const (
	crSuccess     = 0x00
	crBufferSmall = 0x1A
)

// Device is one virtual Xbox 360 pad on the ViGEm bus.
type Device struct {
	mu     sync.Mutex
	h      syscall.Handle
	serial uint32
	// UserIndex is the XInput player slot 0..3, or -1 when Windows has not
	// assigned one yet.
	UserIndex int
}

// Create opens the bus and plugs in a pad. It returns ErrNoBus when the
// driver is not installed.
func Create() (*Device, error) {
	paths, err := busPaths()
	if err != nil {
		return nil, err
	}
	if len(paths) == 0 {
		return nil, ErrNoBus
	}
	last := ErrNoBus
	for _, path := range paths {
		h, err := open(path)
		if err != nil {
			last = err
			continue
		}
		d := &Device{h: h, UserIndex: -1}
		if err := d.checkVersion(); err != nil {
			_ = syscall.CloseHandle(h)
			last = err
			continue
		}
		if err := d.plugIn(); err != nil {
			_ = syscall.CloseHandle(h)
			return nil, err
		}
		d.UserIndex = d.userIndex()
		return d, nil
	}
	return nil, last
}

// Set sends next as the whole XInput state. The driver keeps no diff, so prev is unused.
func (d *Device) Set(prev, next protocol.State) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.h == syscall.InvalidHandle {
		return ErrClosed
	}
	req := submitReport{SerialNo: d.serial, Report: ReportFrom(next)}
	req.Size = uint32(unsafe.Sizeof(req))
	return d.ioctl(ioctlXusbSubmitReport, unsafe.Pointer(&req), req.Size, nil, 0)
}

// Close unplugs the pad and closes the bus.
func (d *Device) Close() error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.h == syscall.InvalidHandle {
		return nil
	}
	req := serialRequest{Value: d.serial}
	req.Size = uint32(unsafe.Sizeof(req))
	err := d.ioctl(ioctlUnplugTarget, unsafe.Pointer(&req), req.Size, nil, 0)
	if cErr := syscall.CloseHandle(d.h); err == nil {
		err = cErr
	}
	d.h = syscall.InvalidHandle
	return err
}

func (d *Device) checkVersion() error {
	req := serialRequest{Value: commonVersion}
	req.Size = uint32(unsafe.Sizeof(req))
	if err := d.ioctl(ioctlCheckVersion, unsafe.Pointer(&req), req.Size, nil, 0); err != nil {
		return ErrVersion
	}
	return nil
}

// plugIn takes the first free serial. The bus has no "any slot" request,
// so ViGEmClient walks the serials the same way.
func (d *Device) plugIn() error {
	for serial := uint32(1); serial <= maxTargets; serial++ {
		req := pluginTarget{SerialNo: serial, TargetType: targetXbox360, VendorID: vendorID, ProductID: productID}
		req.Size = uint32(unsafe.Sizeof(req))
		if err := d.ioctl(ioctlPluginTarget, unsafe.Pointer(&req), req.Size, nil, 0); err != nil {
			continue
		}
		d.serial = serial
		// Drivers from 1.17 hold this request until the pad accepts reports.
		// Older ones reject it as an unknown parameter and are ready at once.
		wait := serialRequest{Value: serial}
		wait.Size = uint32(unsafe.Sizeof(wait))
		err := d.ioctl(ioctlWaitDeviceReady, unsafe.Pointer(&wait), wait.Size, nil, 0)
		if err == nil || errors.Is(err, errInvalidParam) {
			return nil
		}
		unplug := serialRequest{Value: serial}
		unplug.Size = uint32(unsafe.Sizeof(unplug))
		_ = d.ioctl(ioctlUnplugTarget, unsafe.Pointer(&unplug), unplug.Size, nil, 0)
		return err
	}
	return ErrFull
}

// userIndex asks which XInput slot the pad got. Windows assigns it shortly
// after the pad appears, so the request is retried for a moment.
func (d *Device) userIndex() int {
	for i := 0; i < 20; i++ {
		req := getUserIndex{SerialNo: d.serial}
		req.Size = uint32(unsafe.Sizeof(req))
		if d.ioctl(ioctlXusbGetUserIndex, unsafe.Pointer(&req), req.Size, unsafe.Pointer(&req), req.Size) == nil {
			return int(req.UserIndex)
		}
		time.Sleep(25 * time.Millisecond)
	}
	return -1
}

func (d *Device) ioctl(code uint32, in unsafe.Pointer, inSize uint32, out unsafe.Pointer, outSize uint32) error {
	var done uint32
	return syscall.DeviceIoControl(d.h, code, (*byte)(in), inSize, (*byte)(out), outSize, &done, nil)
}

// open uses a synchronous handle. Every request here completes quickly, and
// the wait for a new pad is meant to block.
func open(path string) (syscall.Handle, error) {
	p, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return syscall.InvalidHandle, err
	}
	return syscall.CreateFile(
		p,
		syscall.GENERIC_READ|syscall.GENERIC_WRITE,
		syscall.FILE_SHARE_READ|syscall.FILE_SHARE_WRITE,
		nil,
		syscall.OPEN_EXISTING,
		syscall.FILE_ATTRIBUTE_NORMAL,
		0,
	)
}

// busPaths lists the present ViGEm bus interfaces.
func busPaths() ([]string, error) {
	if err := procInterfaceSize.Find(); err != nil {
		return nil, err
	}
	for {
		var size uint32
		r, _, _ := procInterfaceSize.Call(
			uintptr(unsafe.Pointer(&size)),
			uintptr(unsafe.Pointer(&busInterface)),
			0, 0, // all instances, CM_GET_DEVICE_INTERFACE_LIST_PRESENT
		)
		if r != crSuccess {
			return nil, ErrNoBus
		}
		if size <= 1 {
			return nil, nil
		}
		buf := make([]uint16, size)
		r, _, _ = procInterfaceList.Call(
			uintptr(unsafe.Pointer(&busInterface)),
			0,
			uintptr(unsafe.Pointer(&buf[0])),
			uintptr(size),
			0,
		)
		if r == crBufferSmall {
			continue // a bus appeared between the two calls
		}
		if r != crSuccess {
			return nil, ErrNoBus
		}
		return splitMultiSZ(buf), nil
	}
}

// splitMultiSZ splits a NUL-separated, double-NUL-terminated UTF-16 list.
func splitMultiSZ(buf []uint16) []string {
	var out []string
	start := 0
	for i, c := range buf {
		if c != 0 {
			continue
		}
		if i == start {
			break
		}
		out = append(out, syscall.UTF16ToString(buf[start:i]))
		start = i + 1
	}
	return out
}
