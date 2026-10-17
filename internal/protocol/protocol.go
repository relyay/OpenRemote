// Package protocol is the state a browser sends to the virtual Xbox 360.
//
// Binary frames are 14 bytes, little-endian:
//
//	0  int16  left stick X,  -32767..32767, right is positive
//	2  int16  left stick Y,  -32767..32767, down is positive
//	4  int16  right stick X
//	6  int16  right stick Y
//	8  uint8  left trigger,  0..255
//	9  uint8  right trigger, 0..255
//	10 uint16 buttons bitfield
//	12 int8   d-pad X, -1..1, right is positive
//	13 int8   d-pad Y, -1..1, down is positive
//
// Button bits, low to high: A B X Y LB RB Back Start Guide L3 R3.
// This order matches the evdev codes of a real Xbox 360, so SDL button
// indices stay the same. Extra bits are ignored.
//
// A text frame is JSON. Sticks are -1..1 (or raw int16 if the absolute
// value is greater than 1). Triggers are 0..1 (or 0..255 if greater than 1).
// Positive stick Y is down, the same as the binary frame and as Linux evdev.
package protocol

import (
	"encoding/binary"
	"encoding/json"
	"errors"
	"math"
)

const FrameSize = 14

const (
	BtnA uint16 = 1 << iota
	BtnB
	BtnX
	BtnY
	BtnLB
	BtnRB
	BtnBack
	BtnStart
	BtnGuide
	BtnL3
	BtnR3
)

// BtnMask keeps the eleven real buttons. Higher bits are not a pad button.
const BtnMask uint16 = 0x07FF

// State is one full snapshot. The server applies the difference from the
// previous snapshot, so a client must send the whole pad every time.
type State struct {
	LX, LY  int16
	RX, RY  int16
	LT, RT  uint8
	HatX    int8
	HatY    int8
	Buttons uint16
}

var errShort = errors.New("короткий кадр геймпада")

// DecodeBinary reads one binary frame. Bytes after FrameSize are ignored.
func DecodeBinary(p []byte) (State, error) {
	if len(p) < FrameSize {
		return State{}, errShort
	}
	s := State{
		LX:      int16(binary.LittleEndian.Uint16(p[0:2])),
		LY:      int16(binary.LittleEndian.Uint16(p[2:4])),
		RX:      int16(binary.LittleEndian.Uint16(p[4:6])),
		RY:      int16(binary.LittleEndian.Uint16(p[6:8])),
		LT:      p[8],
		RT:      p[9],
		Buttons: binary.LittleEndian.Uint16(p[10:12]) & BtnMask,
		HatX:    clampHat(int8(p[12])),
		HatY:    clampHat(int8(p[13])),
	}
	return s, nil
}

// EncodeBinary writes s into a 14-byte frame.
func EncodeBinary(s State) []byte {
	p := make([]byte, FrameSize)
	binary.LittleEndian.PutUint16(p[0:2], uint16(s.LX))
	binary.LittleEndian.PutUint16(p[2:4], uint16(s.LY))
	binary.LittleEndian.PutUint16(p[4:6], uint16(s.RX))
	binary.LittleEndian.PutUint16(p[6:8], uint16(s.RY))
	p[8] = s.LT
	p[9] = s.RT
	binary.LittleEndian.PutUint16(p[10:12], s.Buttons&BtnMask)
	p[12] = byte(clampHat(s.HatX))
	p[13] = byte(clampHat(s.HatY))
	return p
}

type jsonState struct {
	LX      *float64 `json:"lx"`
	LY      *float64 `json:"ly"`
	RX      *float64 `json:"rx"`
	RY      *float64 `json:"ry"`
	LT      *float64 `json:"lt"`
	RT      *float64 `json:"rt"`
	HatX    *int     `json:"hatx"`
	HatY    *int     `json:"haty"`
	Buttons *uint16  `json:"buttons"`
	A       *bool    `json:"a"`
	B       *bool    `json:"b"`
	X       *bool    `json:"x"`
	Y       *bool    `json:"y"`
	LB      *bool    `json:"lb"`
	RB      *bool    `json:"rb"`
	Back    *bool    `json:"back"`
	Start   *bool    `json:"start"`
	Guide   *bool    `json:"guide"`
	L3      *bool    `json:"l3"`
	R3      *bool    `json:"r3"`
}

// DecodeJSON reads one text frame. Missing fields are released.
func DecodeJSON(p []byte) (State, error) {
	var in jsonState
	if err := json.Unmarshal(p, &in); err != nil {
		return State{}, err
	}
	s := State{
		LX:   axisFromJSON(in.LX),
		LY:   axisFromJSON(in.LY),
		RX:   axisFromJSON(in.RX),
		RY:   axisFromJSON(in.RY),
		LT:   trigFromJSON(in.LT),
		RT:   trigFromJSON(in.RT),
		HatX: hatFromJSON(in.HatX),
		HatY: hatFromJSON(in.HatY),
	}
	if in.Buttons != nil {
		s.Buttons |= *in.Buttons
	}
	s.Buttons |= boolBit(in.A, BtnA)
	s.Buttons |= boolBit(in.B, BtnB)
	s.Buttons |= boolBit(in.X, BtnX)
	s.Buttons |= boolBit(in.Y, BtnY)
	s.Buttons |= boolBit(in.LB, BtnLB)
	s.Buttons |= boolBit(in.RB, BtnRB)
	s.Buttons |= boolBit(in.Back, BtnBack)
	s.Buttons |= boolBit(in.Start, BtnStart)
	s.Buttons |= boolBit(in.Guide, BtnGuide)
	s.Buttons |= boolBit(in.L3, BtnL3)
	s.Buttons |= boolBit(in.R3, BtnR3)
	s.Buttons &= BtnMask
	return s, nil
}

func clampHat(v int8) int8 {
	switch {
	case v < 0:
		return -1
	case v > 0:
		return 1
	default:
		return 0
	}
}

func axisFromJSON(v *float64) int16 {
	if v == nil || math.IsNaN(*v) || math.IsInf(*v, 0) {
		return 0
	}
	n := *v
	if n > 1 || n < -1 {
		return clampAxis(n)
	}
	return clampAxis(n * 32767)
}

func trigFromJSON(v *float64) uint8 {
	if v == nil || math.IsNaN(*v) || math.IsInf(*v, 0) {
		return 0
	}
	n := *v
	if n > 1 {
		if n > 255 {
			n = 255
		}
		if n < 0 {
			n = 0
		}
		return uint8(math.Round(n))
	}
	if n < 0 {
		n = 0
	}
	return uint8(math.Round(n * 255))
}

func hatFromJSON(v *int) int8 {
	if v == nil || *v == 0 {
		return 0
	}
	if *v < 0 {
		return -1
	}
	return 1
}

func clampAxis(n float64) int16 {
	if n > 32767 {
		n = 32767
	}
	if n < -32767 {
		n = -32767
	}
	return int16(math.Round(n))
}

func boolBit(v *bool, bit uint16) uint16 {
	if v != nil && *v {
		return bit
	}
	return 0
}
