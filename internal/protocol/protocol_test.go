package protocol

import "testing"

func TestBinaryRoundTrip(t *testing.T) {
	in := State{
		LX: -16000, LY: 32767, RX: 1, RY: -1,
		LT: 255, RT: 3,
		HatX: -1, HatY: 1,
		Buttons: BtnA | BtnStart | BtnR3,
	}
	out, err := DecodeBinary(EncodeBinary(in))
	if err != nil {
		t.Fatal(err)
	}
	if out != in {
		t.Fatalf("got %+v want %+v", out, in)
	}
}

func TestBinaryRejectsShortAndStripsBits(t *testing.T) {
	if _, err := DecodeBinary([]byte{1, 2, 3}); err == nil {
		t.Fatal("short frame accepted")
	}
	p := EncodeBinary(State{})
	p[10] = 0xFF
	p[11] = 0xFF
	p[12] = 5
	neg := int8(-9)
	p[13] = byte(neg)
	s, err := DecodeBinary(p)
	if err != nil {
		t.Fatal(err)
	}
	if s.Buttons != BtnMask || s.HatX != 1 || s.HatY != -1 {
		t.Fatalf("got %+v", s)
	}
	// Extra trailing bytes are reserved and ignored.
	p = append(p, 9, 9, 9)
	if _, err := DecodeBinary(p); err != nil {
		t.Fatal(err)
	}
}

func TestJSONNormalizedAndRaw(t *testing.T) {
	s, err := DecodeJSON([]byte(`{"lx":-1,"ly":1,"lt":1,"hatx":-1,"a":true,"start":true}`))
	if err != nil {
		t.Fatal(err)
	}
	if s.LX != -32767 || s.LY != 32767 || s.LT != 255 || s.HatX != -1 {
		t.Fatalf("axes %+v", s)
	}
	if s.Buttons != BtnA|BtnStart {
		t.Fatalf("buttons %04x", s.Buttons)
	}

	raw, err := DecodeJSON([]byte(`{"rx":-20000,"rt":128,"buttons":4}`))
	if err != nil {
		t.Fatal(err)
	}
	if raw.RX != -20000 || raw.RT != 128 || raw.Buttons != BtnX {
		t.Fatalf("raw %+v", raw)
	}
}

func TestJSONRejectsGarbage(t *testing.T) {
	if _, err := DecodeJSON([]byte(`{`)); err == nil {
		t.Fatal("accepted broken json")
	}
	s, err := DecodeJSON([]byte(`{"ly":null,"lt":-4}`))
	if err != nil {
		t.Fatal(err)
	}
	if s != (State{}) {
		t.Fatalf("got %+v", s)
	}
}

func TestButtonBitsMatchLayout(t *testing.T) {
	if BtnA != 1<<0 || BtnB != 1<<1 || BtnX != 1<<2 || BtnY != 1<<3 {
		t.Fatal("face bits")
	}
	if BtnLB != 1<<4 || BtnRB != 1<<5 || BtnBack != 1<<6 || BtnStart != 1<<7 {
		t.Fatal("shoulder/menu bits")
	}
	if BtnGuide != 1<<8 || BtnL3 != 1<<9 || BtnR3 != 1<<10 || BtnMask != 0x07FF {
		t.Fatal("stick/guide bits")
	}
}
