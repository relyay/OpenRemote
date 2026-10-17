//go:build !linux

package uinput

import "openremote/internal/protocol"

// Device is the virtual pad handle. Other systems have no backend yet.
type Device struct {
	EventPath string
	JSPath    string
	SysName   string
}

// Create reports that this OS cannot open a virtual Xbox 360 pad.
func Create() (*Device, error) {
	return nil, ErrUnsupported
}

// Set is unused: Create never returns a device.
func (d *Device) Set(prev, next protocol.State) error {
	return ErrUnsupported
}

// Close is unused: Create never returns a device.
func (d *Device) Close() error {
	return nil
}
