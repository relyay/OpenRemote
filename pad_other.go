//go:build !linux && !windows

package main

import (
	"errors"
	"syscall"

	"openremote/internal/i18n"
)

var errUnsupported = errors.New("unsupported OS")

func openDevice() (device, string, error) {
	return nil, "", errUnsupported
}

func explain(err error) string {
	if errors.Is(err, errUnsupported) {
		return i18n.T("the virtual gamepad works only on Linux and Windows", "виртуальный геймпад работает только в Linux и Windows")
	}
	return err.Error()
}

func portInUse(err error) bool {
	return errors.Is(err, syscall.EADDRINUSE)
}
