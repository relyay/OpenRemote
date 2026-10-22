package i18n

import "syscall"

var procUILanguage = syscall.NewLazyDLL("kernel32.dll").NewProc("GetUserDefaultUILanguage")

// systemRussian reports whether the Windows display language is Russian.
func systemRussian() bool {
	const langRussian = 0x19 // PRIMARYLANGID of every ru-* LANGID
	langID, _, _ := procUILanguage.Call()
	return langID&0x3ff == langRussian
}
