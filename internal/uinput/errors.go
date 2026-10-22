package uinput

import "errors"

// ErrClosed is returned when the virtual pad has already been destroyed.
var ErrClosed = errors.New("uinput closed")

// ErrDeviceNode is returned when /dev/uinput does not exist.
var ErrDeviceNode = errors.New("uinput node missing")

// ErrPermission is returned when the process cannot open /dev/uinput.
var ErrPermission = errors.New("uinput permission")
