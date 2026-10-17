package pad

import (
	"testing"
	"time"

	"openremote/internal/protocol"
)

type mem struct {
	writes []protocol.State
}

func (m *mem) Set(prev, next protocol.State) error {
	m.writes = append(m.writes, next)
	return nil
}

func TestOwnerReleasesPreviousHold(t *testing.T) {
	m := &mem{}
	p := New(m)
	p.Bind(1)
	if err := p.Apply(1, protocol.State{Buttons: protocol.BtnA, LX: 10}); err != nil {
		t.Fatal(err)
	}
	p.Bind(2)
	if err := p.Apply(1, protocol.State{Buttons: protocol.BtnB}); err != nil {
		t.Fatal(err)
	}
	if err := p.Apply(2, protocol.State{LY: -5}); err != nil {
		t.Fatal(err)
	}
	p.Release(1)
	owner, st := p.State()
	if owner != 2 || st.LY != -5 || st.Buttons != 0 {
		t.Fatalf("owner %d state %+v", owner, st)
	}
	p.Release(2)
	owner, st = p.State()
	if owner != 0 || st != (protocol.State{}) {
		t.Fatalf("after release owner %d state %+v", owner, st)
	}
	if m.writes[len(m.writes)-1] != (protocol.State{}) {
		t.Fatal("pad was not centered")
	}
}

func TestShortTapStaysDownUntilPulse(t *testing.T) {
	var edges edgeTimes
	start := time.Unix(0, 0)
	down := protocol.State{Buttons: protocol.BtnA}
	got, wait := maskShortRelease(protocol.State{}, down, &edges, start)
	if got.Buttons != protocol.BtnA || wait != 0 {
		t.Fatalf("press %+v wait %s", got, wait)
	}
	up := protocol.State{}
	got, wait = maskShortRelease(down, up, &edges, start.Add(5*time.Millisecond))
	if got.Buttons != protocol.BtnA {
		t.Fatalf("tap released too soon: %+v", got)
	}
	if wait <= 0 || wait > minPulse {
		t.Fatalf("wait %s", wait)
	}
	got, wait = maskShortRelease(down, up, &edges, start.Add(minPulse))
	if got.Buttons != 0 || wait != 0 {
		t.Fatalf("held tap %+v wait %s", got, wait)
	}
}
