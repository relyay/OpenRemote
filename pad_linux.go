package main

import (
	"errors"
	"strings"
	"syscall"

	"openremote/internal/i18n"
	"openremote/internal/uinput"
)

// openDevice creates the pad through /dev/uinput. detail names its device nodes.
func openDevice() (device, string, error) {
	dev, err := uinput.Create()
	if err != nil {
		return nil, "", err
	}
	var nodes []string
	for _, p := range []string{dev.EventPath, dev.JSPath} {
		if p != "" {
			nodes = append(nodes, p)
		}
	}
	return dev, strings.Join(nodes, "  "), nil
}

func explain(err error) string {
	switch {
	case errors.Is(err, uinput.ErrDeviceNode):
		return i18n.T("no /dev/uinput: run sudo modprobe uinput", "нет /dev/uinput: выполните sudo modprobe uinput")
	case errors.Is(err, uinput.ErrPermission):
		return i18n.T("no access to /dev/uinput: run sudo ./openremote", "нет доступа к /dev/uinput: запустите sudo ./openremote")
	default:
		return err.Error()
	}
}

func portInUse(err error) bool {
	return errors.Is(err, syscall.EADDRINUSE)
}
