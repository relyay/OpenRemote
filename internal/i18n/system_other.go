//go:build !windows

package i18n

// systemRussian is false: without a locale variable a Unix process runs as C.
func systemRussian() bool { return false }
