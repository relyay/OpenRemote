package server

import (
	"bufio"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"openremote/internal/protocol"
)

type fakePad struct {
	mu    sync.Mutex
	owner uint64
	state protocol.State
	seen  []protocol.State
}

func (f *fakePad) Bind(id uint64) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.owner = id
	f.state = protocol.State{}
}

func (f *fakePad) Apply(id uint64, s protocol.State) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if id != f.owner {
		return nil
	}
	f.state = s
	f.seen = append(f.seen, s)
	return nil
}

func (f *fakePad) Release(id uint64) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if id != f.owner {
		return
	}
	f.owner = 0
	f.state = protocol.State{}
}

func (f *fakePad) wait(t *testing.T) protocol.State {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		f.mu.Lock()
		if len(f.seen) > 0 {
			s := f.seen[len(f.seen)-1]
			f.mu.Unlock()
			return s
		}
		f.mu.Unlock()
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatal("кадр не дошёл до геймпада")
	return protocol.State{}
}

func TestSocket(t *testing.T) {
	pad := &fakePad{}
	s := New(pad)
	ts := httptest.NewServer(s.Handler)
	defer ts.Close()

	health, err := http.Get(ts.URL + "/health")
	if err != nil {
		t.Fatal(err)
	}
	health.Body.Close()
	if health.StatusCode != 200 {
		t.Fatal(health.StatusCode)
	}

	conn := dial(t, ts.URL)
	defer conn.Close()
	frame := protocol.EncodeBinary(protocol.State{Buttons: protocol.BtnB, RX: -1234, RT: 9, HatX: 1})
	if err := writeMasked(conn, 0x2, frame); err != nil {
		t.Fatal(err)
	}
	got := pad.wait(t)
	if got.Buttons != protocol.BtnB || got.RX != -1234 || got.RT != 9 || got.HatX != 1 {
		t.Fatalf("state %+v", got)
	}

	text := []byte(`{"a":true,"ly":1,"lt":1}`)
	if err := writeMasked(conn, 0x1, text); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		pad.mu.Lock()
		st := pad.state
		pad.mu.Unlock()
		if st.Buttons == protocol.BtnA && st.LY == 32767 && st.LT == 255 {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	pad.mu.Lock()
	defer pad.mu.Unlock()
	t.Fatalf("json state %+v", pad.state)
}

func TestSecondClientReplacesFirst(t *testing.T) {
	pad := &fakePad{}
	s := New(pad)
	ts := httptest.NewServer(s.Handler)
	defer ts.Close()

	first := dial(t, ts.URL)
	defer first.Close()
	second := dial(t, ts.URL)
	defer second.Close()

	time.Sleep(50 * time.Millisecond)
	_ = writeMasked(first, 0x2, protocol.EncodeBinary(protocol.State{Buttons: protocol.BtnA}))
	_ = writeMasked(second, 0x2, protocol.EncodeBinary(protocol.State{Buttons: protocol.BtnX}))

	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		pad.mu.Lock()
		st := pad.state
		pad.mu.Unlock()
		if st.Buttons == protocol.BtnX {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatal("второй клиент не стал владельцем")
}

func dial(t *testing.T, raw string) net.Conn {
	t.Helper()
	host := strings.TrimPrefix(raw, "http://")
	conn, err := net.Dial("tcp", host)
	if err != nil {
		t.Fatal(err)
	}
	_, err = io.WriteString(conn, "GET /ws HTTP/1.1\r\nHost: "+host+"\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n")
	if err != nil {
		t.Fatal(err)
	}
	br := bufio.NewReader(conn)
	status, err := br.ReadString('\n')
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(status, "101") {
		t.Fatalf("status %q", status)
	}
	for {
		line, err := br.ReadString('\n')
		if err != nil {
			t.Fatal(err)
		}
		if line == "\r\n" {
			break
		}
	}
	return conn
}

func writeMasked(conn net.Conn, op byte, payload []byte) error {
	mask := [4]byte{9, 8, 7, 6}
	hdr := []byte{0x80 | op, 0x80 | byte(len(payload))}
	if _, err := conn.Write(hdr); err != nil {
		return err
	}
	if _, err := conn.Write(mask[:]); err != nil {
		return err
	}
	buf := make([]byte, len(payload))
	for i, b := range payload {
		buf[i] = b ^ mask[i&3]
	}
	_, err := conn.Write(buf)
	return err
}
