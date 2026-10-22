// Package vigem plugs one virtual Xbox 360 pad into the ViGEmBus driver on
// Windows. Games see it through XInput like a wired controller.
//
// The driver is spoken to directly with DeviceIoControl, the same requests
// the ViGEmClient library sends, so the host needs no DLL and no cgo.
package vigem

import "openremote/internal/protocol"

// XUSB_REPORT button bits, from ViGEm/Common.h.
const (
	xusbDpadUp        = 0x0001
	xusbDpadDown      = 0x0002
	xusbDpadLeft      = 0x0004
	xusbDpadRight     = 0x0008
	xusbStart         = 0x0010
	xusbBack          = 0x0020
	xusbLeftThumb     = 0x0040
	xusbRightThumb    = 0x0080
	xusbLeftShoulder  = 0x0100
	xusbRightShoulder = 0x0200
	xusbGuide         = 0x0400
	xusbA             = 0x1000
	xusbB             = 0x2000
	xusbX             = 0x4000
	xusbY             = 0x8000
)

// Report is XUSB_REPORT: the XInput gamepad state the driver forwards to games.
type Report struct {
	Buttons      uint16
	LeftTrigger  uint8
	RightTrigger uint8
	ThumbLX      int16
	ThumbLY      int16
	ThumbRX      int16
	ThumbRY      int16
}

var buttonMap = [...]struct {
	from uint16
	to   uint16
}{
	{protocol.BtnA, xusbA},
	{protocol.BtnB, xusbB},
	{protocol.BtnX, xusbX},
	{protocol.BtnY, xusbY},
	{protocol.BtnLB, xusbLeftShoulder},
	{protocol.BtnRB, xusbRightShoulder},
	{protocol.BtnBack, xusbBack},
	{protocol.BtnStart, xusbStart},
	{protocol.BtnGuide, xusbGuide},
	{protocol.BtnL3, xusbLeftThumb},
	{protocol.BtnR3, xusbRightThumb},
}

// ReportFrom converts a protocol snapshot. The protocol follows evdev, where
// positive stick Y is down; XInput counts up as positive, so Y is flipped.
func ReportFrom(s protocol.State) Report {
	r := Report{
		LeftTrigger:  s.LT,
		RightTrigger: s.RT,
		ThumbLX:      s.LX,
		ThumbLY:      flip(s.LY),
		ThumbRX:      s.RX,
		ThumbRY:      flip(s.RY),
	}
	for _, m := range buttonMap {
		if s.Buttons&m.from != 0 {
			r.Buttons |= m.to
		}
	}
	switch {
	case s.HatY < 0:
		r.Buttons |= xusbDpadUp
	case s.HatY > 0:
		r.Buttons |= xusbDpadDown
	}
	switch {
	case s.HatX < 0:
		r.Buttons |= xusbDpadLeft
	case s.HatX > 0:
		r.Buttons |= xusbDpadRight
	}
	return r
}

// flip negates an axis. -32768 has no positive twin in int16.
func flip(v int16) int16 {
	if v == -32768 {
		return 32767
	}
	return -v
}
