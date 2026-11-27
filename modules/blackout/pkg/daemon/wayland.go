package main

// A small Wayland client: the wire format, and nothing else. Each message is
// native-endian 32-bit words: the object id, then the message's size in bytes
// (high 16 bits) and its opcode (low 16), then the arguments. A string is its
// length counting the final NUL, its bytes and the NUL, padded to 4 bytes.
// File descriptors travel beside the bytes (SCM_RIGHTS); blackout asks for
// nothing that sends one, and closes any that comes.
// https://wayland.freedesktop.org/docs/html/ch04.html

import (
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"syscall"
)

var ne = binary.NativeEndian

const displayID = 1 // wl_display, the one object that exists from the start

// handler receives an object's events.
type handler func(op uint16, a *args)

type conn struct {
	c        *net.UnixConn
	buf      []byte // bytes read but not yet a whole message
	nextID   uint32
	free     []uint32 // ids the server released (wl_display.delete_id), to reuse
	handlers map[uint32]handler
	err      error // the first error: a failed write, or wl_display.error
}

func dial() (*conn, error) {
	name := os.Getenv("WAYLAND_DISPLAY")
	if name == "" {
		name = "wayland-0"
	}
	if !filepath.IsAbs(name) {
		dir := os.Getenv("XDG_RUNTIME_DIR")
		if dir == "" {
			return nil, errors.New("XDG_RUNTIME_DIR isn't set")
		}
		name = filepath.Join(dir, name)
	}
	c, err := net.DialUnix("unix", nil, &net.UnixAddr{Name: name, Net: "unix"})
	if err != nil {
		return nil, err
	}
	w := &conn{c: c, nextID: 2, handlers: map[uint32]handler{}}
	w.handlers[displayID] = w.display
	return w, nil
}

// display handles wl_display's events.
func (w *conn) display(op uint16, a *args) {
	switch op {
	case 0: // error(object, code, message)
		obj, code, msg := a.uint(), a.uint(), a.str()
		if w.err == nil {
			w.err = fmt.Errorf("wayland: error %d on object %d: %s", code, obj, msg)
		}
	case 1: // delete_id(id): the server let go of it, it can be reused
		id := a.uint()
		delete(w.handlers, id)
		w.free = append(w.free, id)
	}
}

// newID allocates an object id, whose events go to h (nil ignores them).
// The server takes a new id only if it is free or the next one after the
// highest so far, so ids are reused after delete_id, as libwayland does.
func (w *conn) newID(h handler) uint32 {
	var id uint32
	if n := len(w.free); n > 0 {
		id, w.free = w.free[n-1], w.free[:n-1]
	} else {
		id = w.nextID
		w.nextID++
	}
	if h == nil {
		h = func(uint16, *args) {}
	}
	w.handlers[id] = h
	return id
}

// req sends a request. Arguments are uint32 (uint, object, new_id; 0 is a
// null object), int32 or string.
func (w *conn) req(id uint32, op uint16, args ...any) {
	if w.err != nil {
		return
	}
	if _, err := w.c.Write(marshal(id, op, args...)); err != nil {
		w.err = err
	}
}

// destroy sends a destructor request. The object's events stop now; its id
// is reused once the server confirms (delete_id).
func (w *conn) destroy(id uint32, op uint16) {
	w.req(id, op)
	delete(w.handlers, id)
}

func marshal(id uint32, op uint16, args ...any) []byte {
	b := make([]byte, 8, 64)
	for _, a := range args {
		switch v := a.(type) {
		case uint32:
			b = ne.AppendUint32(b, v)
		case int32:
			b = ne.AppendUint32(b, uint32(v))
		case string:
			b = ne.AppendUint32(b, uint32(len(v)+1))
			b = append(b, v...)
			b = append(b, 0)
			for len(b)%4 != 0 {
				b = append(b, 0)
			}
		default:
			panic(fmt.Sprintf("wayland: can't send a %T", a))
		}
	}
	ne.PutUint32(b[0:], id)
	ne.PutUint32(b[4:], uint32(len(b))<<16|uint32(op))
	return b
}

// read waits for bytes from the compositor.
func (w *conn) read() ([]byte, error) {
	b := make([]byte, 4096)
	oob := make([]byte, syscall.CmsgSpace(28*4)) // libwayland sends at most 28 fds at once
	n, oobn, _, _, err := w.c.ReadMsgUnix(b, oob)
	closeFDs(oob[:oobn])
	if err != nil {
		return nil, err
	}
	if n == 0 {
		return nil, errors.New("wayland: the compositor closed the connection")
	}
	return b[:n], nil
}

// feed hands the whole messages in w.buf+b to their objects' handlers.
func (w *conn) feed(b []byte) error {
	w.buf = append(w.buf, b...)
	off := 0
	for len(w.buf)-off >= 8 {
		id := ne.Uint32(w.buf[off:])
		word := ne.Uint32(w.buf[off+4:])
		size, op := int(word>>16), uint16(word)
		if size < 8 || size%4 != 0 {
			return fmt.Errorf("wayland: bad message size %d", size)
		}
		if len(w.buf)-off < size {
			break
		}
		if h := w.handlers[id]; h != nil {
			a := &args{b: w.buf[off+8 : off+size]}
			h(op, a)
			if a.short && w.err == nil {
				w.err = fmt.Errorf("wayland: short event %d on object %d", op, id)
			}
		}
		off += size
		if w.err != nil {
			return w.err
		}
	}
	w.buf = w.buf[:copy(w.buf, w.buf[off:])]
	return w.err
}

// roundtrip waits until the compositor has handled every request sent so
// far, and the events they caused are handled (wl_display.sync).
func (w *conn) roundtrip() error {
	done := false
	cb := w.newID(func(uint16, *args) { done = true })
	w.req(displayID, 0, cb)
	for !done {
		if w.err != nil {
			return w.err
		}
		b, err := w.read()
		if err != nil {
			return err
		}
		if err := w.feed(b); err != nil {
			return err
		}
	}
	return w.err
}

func closeFDs(oob []byte) {
	msgs, err := syscall.ParseSocketControlMessage(oob)
	if err != nil {
		return
	}
	for _, m := range msgs {
		fds, err := syscall.ParseUnixRights(&m)
		if err != nil {
			continue
		}
		for _, fd := range fds {
			syscall.Close(fd)
		}
	}
}

// args reads an event's arguments in order. A missing one reads as zero and
// sets short.
type args struct {
	b     []byte
	short bool
}

func (a *args) uint() uint32 {
	if len(a.b) < 4 {
		a.short = true
		return 0
	}
	v := ne.Uint32(a.b)
	a.b = a.b[4:]
	return v
}

func (a *args) str() string {
	n := a.uint()
	if n == 0 { // a null string
		return ""
	}
	padded := (int(n) + 3) &^ 3
	if len(a.b) < padded {
		a.short = true
		return ""
	}
	s := string(a.b[:n-1])
	a.b = a.b[padded:]
	return s
}
