package ws

import (
	"bufio"
	"crypto/sha1"
	"encoding/base64"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestAcceptAndBinaryFrame(t *testing.T) {
	got := make(chan []byte, 1)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c, err := Accept(w, r)
		if err != nil {
			t.Errorf("accept: %v", err)
			return
		}
		defer c.Close()
		op, p, err := c.ReadMessage()
		if err != nil {
			t.Errorf("read: %v", err)
			return
		}
		if op != opBin {
			t.Errorf("opcode %d", op)
		}
		got <- append([]byte(nil), p...)
	}))
	defer srv.Close()

	conn := dial(t, srv.URL)
	defer conn.Close()
	payload := []byte{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14}
	if err := writeMasked(conn, opBin, payload); err != nil {
		t.Fatal(err)
	}
	select {
	case p := <-got:
		if string(p) != string(payload) {
			t.Fatalf("payload %v", p)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timeout")
	}
}

func TestRejectsPlainHTTP(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, err := Accept(w, r); err == nil {
			t.Fatal("accepted a normal request")
		}
	}))
	defer srv.Close()
	res, err := http.Get(srv.URL)
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusUpgradeRequired {
		t.Fatalf("status %d", res.StatusCode)
	}
}

func dial(t *testing.T, raw string) net.Conn {
	t.Helper()
	host := strings.TrimPrefix(raw, "http://")
	conn, err := net.Dial("tcp", host)
	if err != nil {
		t.Fatal(err)
	}
	_, err = io.WriteString(conn, "GET / HTTP/1.1\r\nHost: "+host+"\r\nUpgrade: websocket\r\nConnection: keep-alive, Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n")
	if err != nil {
		t.Fatal(err)
	}
	br := bufio.NewReader(conn)
	status, err := br.ReadString('\n')
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(status, "101") {
		t.Fatal(status)
	}
	var accept string
	for {
		line, err := br.ReadString('\n')
		if err != nil {
			t.Fatal(err)
		}
		if line == "\r\n" {
			break
		}
		if strings.HasPrefix(strings.ToLower(line), "sec-websocket-accept:") {
			accept = strings.TrimSpace(strings.SplitN(line, ":", 2)[1])
		}
	}
	sum := sha1.Sum([]byte("dGhlIHNhbXBsZSBub25jZQ==" + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
	want := base64.StdEncoding.EncodeToString(sum[:])
	if accept != want || want != "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" {
		t.Fatalf("accept %q want %q", accept, want)
	}
	return conn
}

func writeMasked(conn net.Conn, op byte, payload []byte) error {
	mask := [4]byte{0x11, 0x22, 0x33, 0x44}
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
