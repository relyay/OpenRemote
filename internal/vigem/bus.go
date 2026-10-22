package vigem

import "errors"

// Requests and structs of the ViGEmBus driver, from ViGEm/km/BusShared.h.
// They are plain data, so they build and are tested on every OS.

const (
	fileDeviceBusExtender = 0x2a
	methodBuffered        = 0
	fileReadData          = 1
	fileWriteData         = 2

	ioctlBase = 0x801
)

func ctlCode(function, access uint32) uint32 {
	return fileDeviceBusExtender<<16 | access<<14 | function<<2 | methodBuffered
}

var (
	ioctlPluginTarget     = ctlCode(ioctlBase+0x000, fileWriteData)
	ioctlUnplugTarget     = ctlCode(ioctlBase+0x001, fileWriteData)
	ioctlCheckVersion     = ctlCode(ioctlBase+0x002, fileWriteData)
	ioctlWaitDeviceReady  = ctlCode(ioctlBase+0x003, fileWriteData)
	ioctlXusbSubmitReport = ctlCode(ioctlBase+0x201, fileWriteData)
	ioctlXusbGetUserIndex = ctlCode(ioctlBase+0x206, fileWriteData|fileReadData)
)

const (
	commonVersion = 0x0001
	targetXbox360 = 0 // VIGEM_TARGET_TYPE Xbox360Wired
	maxTargets    = 16

	// The ids of a wired Microsoft Xbox 360 pad, as the Linux backend uses.
	vendorID  = 0x045e
	productID = 0x028e
)

// serialRequest is VIGEM_CHECK_VERSION, VIGEM_UNPLUG_TARGET and
// VIGEM_WAIT_DEVICE_READY: a size and one ULONG.
type serialRequest struct {
	Size  uint32
	Value uint32
}

type pluginTarget struct {
	Size       uint32
	SerialNo   uint32
	TargetType uint32
	VendorID   uint16
	ProductID  uint16
}

type submitReport struct {
	Size     uint32
	SerialNo uint32
	Report   Report
}

type getUserIndex struct {
	Size      uint32
	SerialNo  uint32
	UserIndex uint32
}

var (
	// ErrNoBus means the ViGEmBus driver is not installed.
	ErrNoBus = errors.New("vigem: ViGEmBus driver not found")
	// ErrVersion means the installed driver speaks another protocol.
	ErrVersion = errors.New("vigem: ViGEmBus version mismatch")
	// ErrFull means every pad slot of the bus is taken.
	ErrFull = errors.New("vigem: no free pad slot on the bus")
	// ErrClosed is returned after Close.
	ErrClosed = errors.New("vigem: pad closed")
)
