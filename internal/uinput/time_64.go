//go:build linux && (amd64 || arm64 || loong64 || mips64 || mips64le || ppc64 || ppc64le || riscv64 || s390x)

package uinput

// timeval matches struct timeval on 64-bit Linux, where input_event is 24 bytes.
type timeval struct {
	Sec  int64
	Usec int64
}
