package vigem

import (
	"testing"
	"unsafe"

	"openremote/internal/protocol"
)

func TestReportFlipsYAndMapsButtons(t *testing.T) {
	got := ReportFrom(protocol.State{
		LX: 100, LY: 200, RX: -300, RY: -32768,
		LT: 10, RT: 255,
		HatX: 1, HatY: -1,
		Buttons: protocol.BtnA | protocol.BtnY | protocol.BtnBack | protocol.BtnGuide | protocol.BtnR3,
	})
	want := Report{
		Buttons:      xusbA | xusbY | xusbBack | xusbGuide | xusbRightThumb | xusbDpadUp | xusbDpadRight,
		LeftTrigger:  10,
		RightTrigger: 255,
		ThumbLX:      100,
		ThumbLY:      -200,
		ThumbRX:      -300,
		ThumbRY:      32767,
	}
	if got != want {
		t.Fatalf("got %+v\nwant %+v", got, want)
	}
}

func TestEveryButtonHasOneXInputBit(t *testing.T) {
	seen := uint16(0)
	for bit := uint16(1); bit <= protocol.BtnR3; bit <<= 1 {
		r := ReportFrom(protocol.State{Buttons: bit})
		if r.Buttons == 0 || r.Buttons&(r.Buttons-1) != 0 {
			t.Fatalf("button %#x maps to %#x", bit, r.Buttons)
		}
		if seen&r.Buttons != 0 {
			t.Fatalf("button %#x reuses %#x", bit, r.Buttons)
		}
		seen |= r.Buttons
	}
}

// The driver checks Size, so the Go layout must match the C structs.
func TestStructSizes(t *testing.T) {
	if n := unsafe.Sizeof(Report{}); n != 12 {
		t.Errorf("XUSB_REPORT is %d bytes, want 12", n)
	}
	if n := unsafe.Sizeof(submitReport{}); n != 20 {
		t.Errorf("XUSB_SUBMIT_REPORT is %d bytes, want 20", n)
	}
	if n := unsafe.Sizeof(pluginTarget{}); n != 16 {
		t.Errorf("VIGEM_PLUGIN_TARGET is %d bytes, want 16", n)
	}
	if n := unsafe.Sizeof(getUserIndex{}); n != 12 {
		t.Errorf("XUSB_GET_USER_INDEX is %d bytes, want 12", n)
	}
}

func TestIoctlCodes(t *testing.T) {
	cases := map[string][2]uint32{
		"PLUGIN_TARGET":     {ioctlPluginTarget, 0x2AA004},
		"UNPLUG_TARGET":     {ioctlUnplugTarget, 0x2AA008},
		"CHECK_VERSION":     {ioctlCheckVersion, 0x2AA00C},
		"WAIT_DEVICE_READY": {ioctlWaitDeviceReady, 0x2AA010},
		"XUSB_SUBMIT":       {ioctlXusbSubmitReport, 0x2AA808},
		"XUSB_USER_INDEX":   {ioctlXusbGetUserIndex, 0x2AE81C},
	}
	for name, c := range cases {
		if c[0] != c[1] {
			t.Errorf("%s = %#x, want %#x", name, c[0], c[1])
		}
	}
}
