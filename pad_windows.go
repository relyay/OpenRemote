package main

import (
	"errors"
	"fmt"
	"syscall"

	"openremote/internal/i18n"
	"openremote/internal/vigem"
)

const vigemDownload = "https://github.com/nefarius/ViGEmBus/releases/latest"

// openDevice plugs a pad into the ViGEmBus driver. detail names its XInput slot.
func openDevice() (device, string, error) {
	dev, err := vigem.Create()
	if err != nil {
		return nil, "", err
	}
	detail := "ViGEmBus"
	if dev.UserIndex >= 0 {
		detail += fmt.Sprintf(i18n.T(", XInput player %d", ", игрок XInput %d"), dev.UserIndex+1)
	}
	return dev, detail, nil
}

func explain(err error) string {
	switch {
	case errors.Is(err, vigem.ErrNoBus):
		return i18n.T(
			"the ViGEmBus driver is not installed. Install it from "+vigemDownload+" and run openremote again",
			"драйвер ViGEmBus не установлен. Установите его со страницы "+vigemDownload+" и запустите openremote снова",
		)
	case errors.Is(err, vigem.ErrVersion):
		return i18n.T(
			"the installed ViGEmBus driver is not compatible. Install the latest one from "+vigemDownload,
			"установленный драйвер ViGEmBus несовместим. Установите последнюю версию со страницы "+vigemDownload,
		)
	case errors.Is(err, vigem.ErrFull):
		return i18n.T("ViGEmBus has no free pad slot. Close other pad emulators", "в ViGEmBus нет свободного места для геймпада. Закройте другие эмуляторы геймпадов")
	default:
		return err.Error()
	}
}

// portInUse recognizes WSAEADDRINUSE, which is not syscall.EADDRINUSE on Windows.
func portInUse(err error) bool {
	return errors.Is(err, syscall.Errno(10048))
}
