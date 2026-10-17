//go:build linux && (386 || arm || armbe || mips || mipsle || ppc)

package uinput

// timeval matches struct timeval on 32-bit Linux, where input_event is 16 bytes.
type timeval struct {
	Sec  int32
	Usec int32
}
