// Package ws is a small server-side WebSocket (RFC 6455) implementation.
// It accepts one upgrade and exchanges binary and text messages. Client
// frames must be masked, as the specification requires.
package ws

import (
	"bufio"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

const (
	opCont  = 0x0
	opText  = 0x1
	opBin   = 0x2
	opClose = 0x8
	opPing  = 0x9
	opPong  = 0xA

	maxMessage = 64 * 1024
)

// Conn is a hijacked WebSocket connection.
type Conn struct {
	conn net.Conn
	r    *bufio.Reader
	w    *bufio.Writer
	mu   sync.Mutex
	once sync.Once
}

// Accept upgrades an HTTP request to a WebSocket.
// On success the ResponseWriter must not be used again.
func Accept(w http.ResponseWriter, r *http.Request) (*Conn, error) {
	if !headerHas(r.Header.Get("Connection"), "upgrade") || !strings.EqualFold(strings.TrimSpace(r.Header.Get("Upgrade")), "websocket") {
		http.Error(w, "нужен websocket", http.StatusUpgradeRequired)
		return nil, errors.New("не websocket")
	}
	if r.Header.Get("Sec-WebSocket-Version") != "13" {
		w.Header().Set("Sec-WebSocket-Version", "13")
		http.Error(w, "нужна версия websocket 13", http.StatusBadRequest)
		return nil, errors.New("версия websocket")
	}
	key := strings.TrimSpace(r.Header.Get("Sec-WebSocket-Key"))
	if key == "" {
		http.Error(w, "нет Sec-WebSocket-Key", http.StatusBadRequest)
		return nil, errors.New("нет ключа websocket")
	}
	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "сервер не поддерживает websocket", http.StatusInternalServerError)
		return nil, errors.New("нет hijack")
	}
	conn, rw, err := hj.Hijack()
	if err != nil {
		return nil, err
	}
	if tc, ok := conn.(*net.TCPConn); ok {
		_ = tc.SetNoDelay(true)
		_ = tc.SetKeepAlive(true)
		_ = tc.SetKeepAlivePeriod(30 * time.Second)
	}
	sum := sha1.Sum([]byte(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
	accept := base64.StdEncoding.EncodeToString(sum[:])
	_, err = rw.WriteString("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\n\r\n")
	if err != nil {
		_ = conn.Close()
		return nil, err
	}
	if err := rw.Flush(); err != nil {
		_ = conn.Close()
		return nil, err
	}
	return &Conn{conn: conn, r: rw.Reader, w: rw.Writer}, nil
}

// ReadMessage returns one complete text or binary message.
// A close frame from the peer is answered and reported as io.EOF.
func (c *Conn) ReadMessage() (opcode byte, payload []byte, err error) {
	var buf []byte
	var kind byte
	for {
		fin, op, p, err := c.readFrame()
		if err != nil {
			return 0, nil, err
		}
		switch op {
		case opPing:
			if err := c.writeFrame(opPong, p); err != nil {
				return 0, nil, err
			}
		case opPong:
		case opClose:
			_ = c.writeFrame(opClose, nil)
			return 0, nil, io.EOF
		case opCont:
			if kind == 0 {
				return 0, nil, errors.New("websocket: продолжение без начала")
			}
			if len(buf)+len(p) > maxMessage {
				return 0, nil, errors.New("websocket: слишком большое сообщение")
			}
			buf = append(buf, p...)
			if fin {
				return kind, buf, nil
			}
		case opText, opBin:
			if !fin {
				kind = op
				buf = append(buf[:0], p...)
				continue
			}
			return op, p, nil
		default:
			return 0, nil, errors.New("websocket: неизвестный код кадра")
		}
	}
}

// Ping asks the peer to answer with a pong.
func (c *Conn) Ping() error {
	return c.writeFrame(opPing, []byte("pad"))
}

// WriteClose sends a close frame. Code 4000 means another browser took the pad.
func (c *Conn) WriteClose(code int, reason string) error {
	if code == 0 {
		code = 1000
	}
	payload := make([]byte, 2+len(reason))
	binary.BigEndian.PutUint16(payload[:2], uint16(code))
	copy(payload[2:], reason)
	return c.writeFrame(opClose, payload)
}

// Close closes the TCP connection.
func (c *Conn) Close() error {
	var err error
	c.once.Do(func() {
		err = c.conn.Close()
	})
	return err
}

func (c *Conn) readFrame() (fin bool, op byte, payload []byte, err error) {
	var hdr [2]byte
	if _, err = io.ReadFull(c.r, hdr[:]); err != nil {
		return
	}
	if hdr[0]&0x70 != 0 {
		err = errors.New("websocket: RSV")
		return
	}
	fin = hdr[0]&0x80 != 0
	op = hdr[0] & 0x0f
	if hdr[1]&0x80 == 0 {
		err = errors.New("websocket: кадр клиента без маски")
		return
	}
	ln := uint64(hdr[1] & 0x7f)
	switch ln {
	case 126:
		var ext [2]byte
		if _, err = io.ReadFull(c.r, ext[:]); err != nil {
			return
		}
		ln = uint64(binary.BigEndian.Uint16(ext[:]))
	case 127:
		var ext [8]byte
		if _, err = io.ReadFull(c.r, ext[:]); err != nil {
			return
		}
		ln = binary.BigEndian.Uint64(ext[:])
	}
	if ln > maxMessage {
		err = errors.New("websocket: слишком большой кадр")
		return
	}
	if (op == opClose || op == opPing || op == opPong) && (ln > 125 || !fin) {
		err = errors.New("websocket: неверный контрольный кадр")
		return
	}
	var mask [4]byte
	if _, err = io.ReadFull(c.r, mask[:]); err != nil {
		return
	}
	payload = make([]byte, ln)
	if _, err = io.ReadFull(c.r, payload); err != nil {
		return
	}
	for i := range payload {
		payload[i] ^= mask[i&3]
	}
	return fin, op, payload, nil
}

func (c *Conn) writeFrame(op byte, p []byte) error {
	if len(p) > maxMessage {
		return errors.New("websocket: слишком большое сообщение")
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	hdr := []byte{0x80 | op, 0}
	switch {
	case len(p) < 126:
		hdr[1] = byte(len(p))
	case len(p) < 65536:
		hdr[1] = 126
		hdr = append(hdr, byte(len(p)>>8), byte(len(p)))
	default:
		hdr[1] = 127
		var ext [8]byte
		binary.BigEndian.PutUint64(ext[:], uint64(len(p)))
		hdr = append(hdr, ext[:]...)
	}
	if _, err := c.w.Write(hdr); err != nil {
		return err
	}
	if _, err := c.w.Write(p); err != nil {
		return err
	}
	return c.w.Flush()
}

func headerHas(header, token string) bool {
	for _, part := range strings.Split(header, ",") {
		if strings.EqualFold(strings.TrimSpace(part), token) {
			return true
		}
	}
	return false
}
