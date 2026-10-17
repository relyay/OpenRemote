// Package server accepts one WebSocket client and drives the virtual pad.
package server

import (
	"encoding/binary"
	"errors"
	"io"
	"log"
	"net"
	"net/http"
	"sync"
	"time"

	"openremote/internal/i18n"
	"openremote/internal/protocol"
	"openremote/internal/ws"
)

// Gamepad is the virtual controller owned by at most one browser.
type Gamepad interface {
	Bind(id uint64)
	Apply(id uint64, s protocol.State) error
	Release(id uint64)
}

// Server is the socket that drives the pad.
type Server struct {
	Handler http.Handler
	hub     *hub
}

// New returns the HTTP handler for /ws.
func New(pad Gamepad) *Server {
	h := &hub{pad: pad}
	mux := http.NewServeMux()
	mux.HandleFunc("/ws", h.serveWS)
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		_, _ = io.WriteString(w, "ok\n")
	})
	return &Server{Handler: mux, hub: h}
}

// ServeUDP applies pad snapshots from datagrams. Each packet is a uint16
// sequence plus one binary frame. A lost packet does not delay the next one.
func (s *Server) ServeUDP(conn *net.UDPConn) {
	buf := make([]byte, 64)
	for {
		n, _, err := conn.ReadFromUDP(buf)
		if err != nil {
			if errors.Is(err, net.ErrClosed) {
				return
			}
			continue
		}
		if n < protocol.FrameSize+2 {
			continue
		}
		s.hub.applyUDP(buf[:n])
	}
}

// CloseClients disconnects the browser that currently owns the pad.
func (s *Server) CloseClients() {
	s.hub.mu.Lock()
	current := s.hub.current
	s.hub.mu.Unlock()
	if current != nil {
		_ = current.Close()
	}
}

type hub struct {
	pad     Gamepad
	mu      sync.Mutex
	seq     uint64
	owner   uint64
	current *ws.Conn
	lastUDP time.Time
	udpSeq  uint16
	haveUDP bool
}

func (h *hub) serveWS(w http.ResponseWriter, r *http.Request) {
	conn, err := ws.Accept(w, r)
	if err != nil {
		return
	}
	h.mu.Lock()
	h.seq++
	id := h.seq
	old := h.current
	h.current = conn
	h.owner = id
	h.haveUDP = false
	h.mu.Unlock()
	if old != nil {
		// 4000 tells that page not to reconnect and steal the pad back.
		_ = old.WriteClose(4000, "replaced")
		_ = old.Close()
	}

	addr := r.RemoteAddr
	log.Printf(i18n.T("client connected: %s", "клиент подключился: %s"), addr)
	h.pad.Bind(id)

	done := make(chan struct{})
	go func() {
		tick := time.NewTicker(20 * time.Second)
		defer tick.Stop()
		for {
			select {
			case <-done:
				return
			case <-tick.C:
				if err := conn.Ping(); err != nil {
					_ = conn.Close()
					return
				}
			}
		}
	}()

	defer func() {
		close(done)
		h.mu.Lock()
		still := h.current == conn
		if still {
			h.current = nil
			h.owner = 0
			h.haveUDP = false
		}
		h.mu.Unlock()
		_ = conn.Close()
		if still {
			h.pad.Release(id)
		}
		log.Printf(i18n.T("client disconnected: %s", "клиент отключился: %s"), addr)
	}()

	for {
		op, payload, err := conn.ReadMessage()
		if err != nil {
			if !errors.Is(err, io.EOF) && !errors.Is(err, net.ErrClosed) {
				log.Printf(i18n.T("client %s: %v", "клиент %s: %v"), addr, err)
			}
			return
		}
		var st protocol.State
		switch op {
		case 0x2:
			st, err = protocol.DecodeBinary(payload)
		case 0x1:
			st, err = protocol.DecodeJSON(payload)
		default:
			continue
		}
		if err != nil {
			log.Printf(i18n.T("client %s: frame: %v", "клиент %s: кадр: %v"), addr, err)
			continue
		}
		if h.udpFresh() {
			continue
		}
		if err := h.pad.Apply(id, st); err != nil {
			log.Printf(i18n.T("gamepad: %v", "геймпад: %v"), err)
			return
		}
	}
}

func (h *hub) applyUDP(p []byte) {
	seq := binary.LittleEndian.Uint16(p[:2])
	st, err := protocol.DecodeBinary(p[2:])
	if err != nil {
		return
	}
	h.mu.Lock()
	if h.current == nil {
		h.mu.Unlock()
		return
	}
	if h.haveUDP && int16(seq-h.udpSeq) <= 0 {
		h.mu.Unlock()
		return
	}
	id := h.owner
	h.udpSeq = seq
	h.haveUDP = true
	h.lastUDP = time.Now()
	h.mu.Unlock()
	_ = h.pad.Apply(id, st)
}

func (h *hub) udpFresh() bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return !h.lastUDP.IsZero() && time.Since(h.lastUDP) < 300*time.Millisecond
}
