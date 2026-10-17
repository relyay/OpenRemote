// Package pad keeps the latest snapshot of the virtual controller and
// forwards changes to the kernel device. One browser owns the pad at a time.
package pad

import (
	"sync"
	"time"

	"openremote/internal/protocol"
)

// minPulse is how long a digital edge stays visible to a game that only
// samples the pad once per frame. A tap shorter than that is extended here,
// after the client has already sent the real release.
const minPulse = 16 * time.Millisecond

// Writer applies an evdev diff. prev is the last snapshot that was sent.
type Writer interface {
	Set(prev, next protocol.State) error
}

// Pad is safe for concurrent use from the HTTP handlers.
type Pad struct {
	mu       sync.Mutex
	w        Writer
	owner    uint64
	kernel   protocol.State
	want     protocol.State
	edge     edgeTimes
	pulseGen uint64
	timer    *time.Timer
}

type edgeTimes struct {
	button [11]time.Time
	hat    time.Time
	lt     time.Time
	rt     time.Time
}

func New(w Writer) *Pad {
	return &Pad{w: w}
}

// Bind makes id the owner and releases whatever the previous owner held.
func (p *Pad) Bind(id uint64) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.stopPulse()
	prev := p.kernel
	p.owner = id
	p.want = protocol.State{}
	p.kernel = protocol.State{}
	p.edge = edgeTimes{}
	_ = p.w.Set(prev, p.kernel)
}

// Apply updates the kernel when id still owns the pad.
func (p *Pad) Apply(id uint64, s protocol.State) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if id != p.owner {
		return nil
	}
	p.want = s
	return p.reconcile(time.Now())
}

// Release returns the pad to center when id is still the owner.
func (p *Pad) Release(id uint64) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if id != p.owner {
		return
	}
	p.stopPulse()
	prev := p.kernel
	p.owner = 0
	p.want = protocol.State{}
	p.kernel = protocol.State{}
	p.edge = edgeTimes{}
	_ = p.w.Set(prev, p.kernel)
}

// State returns the snapshot currently held. It is used by tests.
func (p *Pad) State() (uint64, protocol.State) {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.owner, p.kernel
}

func (p *Pad) reconcile(now time.Time) error {
	out, wait := maskShortRelease(p.kernel, p.want, &p.edge, now)
	p.schedule(wait)
	if out == p.kernel {
		return nil
	}
	if err := p.w.Set(p.kernel, out); err != nil {
		return err
	}
	p.kernel = out
	return nil
}

func (p *Pad) schedule(wait time.Duration) {
	p.pulseGen++
	if p.timer != nil {
		p.timer.Stop()
		p.timer = nil
	}
	if wait <= 0 {
		return
	}
	gen := p.pulseGen
	p.timer = time.AfterFunc(wait, func() {
		p.mu.Lock()
		defer p.mu.Unlock()
		if p.pulseGen != gen {
			return
		}
		_ = p.reconcile(time.Now())
	})
}

func (p *Pad) stopPulse() {
	p.pulseGen++
	if p.timer != nil {
		p.timer.Stop()
		p.timer = nil
	}
}

// maskShortRelease copies want, but keeps a button, hat, or trigger that
// the client already released until it has been down for minPulse.
func maskShortRelease(kernel, want protocol.State, e *edgeTimes, now time.Time) (protocol.State, time.Duration) {
	out := want
	var wait time.Duration
	keep := func(at time.Time) (bool, time.Duration) {
		if at.IsZero() {
			return false, 0
		}
		elapsed := now.Sub(at)
		if elapsed >= minPulse {
			return false, 0
		}
		return true, minPulse - elapsed
	}
	sooner := func(w time.Duration) {
		if w <= 0 {
			return
		}
		if wait == 0 || w < wait {
			wait = w
		}
	}

	for i := 0; i < 11; i++ {
		bit := uint16(1) << uint(i)
		was := kernel.Buttons&bit != 0
		on := want.Buttons&bit != 0
		if !was && on {
			e.button[i] = now
		}
		if was && !on {
			if hold, w := keep(e.button[i]); hold {
				out.Buttons |= bit
				sooner(w)
			}
		}
	}

	kernelHat := kernel.HatX != 0 || kernel.HatY != 0
	wantHat := want.HatX != 0 || want.HatY != 0
	if wantHat && (kernel.HatX != want.HatX || kernel.HatY != want.HatY) {
		e.hat = now
	}
	if kernelHat && !wantHat {
		if hold, w := keep(e.hat); hold {
			out.HatX, out.HatY = kernel.HatX, kernel.HatY
			sooner(w)
		}
	}

	if kernel.LT == 0 && want.LT > 0 {
		e.lt = now
	}
	if kernel.LT > 0 && want.LT == 0 {
		if hold, w := keep(e.lt); hold {
			out.LT = kernel.LT
			sooner(w)
		}
	}
	if kernel.RT == 0 && want.RT > 0 {
		e.rt = now
	}
	if kernel.RT > 0 && want.RT == 0 {
		if hold, w := keep(e.rt); hold {
			out.RT = kernel.RT
			sooner(w)
		}
	}
	return out, wait
}
