package main

import (
	"bytes"
	"testing"
)

func words(ws ...uint32) []byte {
	var b []byte
	for _, w := range ws {
		b = ne.AppendUint32(b, w)
	}
	return b
}

func TestMarshal(t *testing.T) {
	// wl_registry(2).bind(name 7, "wl_seat", version 5, new id 9)
	got := marshal(2, 0, uint32(7), "wl_seat", uint32(5), uint32(9))
	want := words(2, 32<<16|0, 7, 8)
	want = append(want, "wl_seat\x00"...) // 7 bytes and the NUL: no padding
	want = append(want, words(5, 9)...)
	if !bytes.Equal(got, want) {
		t.Fatalf("got  %x\nwant %x", got, want)
	}

	// a string that needs padding, and a negative int
	got = marshal(3, 2, "blackout", int32(-1))
	want = words(3, 28<<16|2, 9)
	want = append(want, "blackout\x00\x00\x00\x00"...)
	want = append(want, words(0xffffffff)...)
	if !bytes.Equal(got, want) {
		t.Fatalf("got  %x\nwant %x", got, want)
	}
}

func TestFeed(t *testing.T) {
	w := &conn{nextID: 2, handlers: map[uint32]handler{}}
	w.handlers[displayID] = w.display
	type event struct {
		op    uint16
		name  uint32
		iface string
	}
	var got []event
	id := w.newID(func(op uint16, a *args) {
		got = append(got, event{op, a.uint(), a.str()})
	})
	msg := marshal(id, 0, uint32(42), "wl_output", uint32(4))
	// a message split across two reads is handled once whole
	if err := w.feed(msg[:10]); err != nil || len(got) != 0 {
		t.Fatalf("after half a message: %v, %v", got, err)
	}
	if err := w.feed(append(msg[10:], marshal(id, 1, uint32(43), "")...)); err != nil {
		t.Fatal(err)
	}
	want := []event{{0, 42, "wl_output"}, {1, 43, ""}}
	if len(got) != 2 || got[0] != want[0] || got[1] != want[1] {
		t.Fatalf("got %v, want %v", got, want)
	}
	if len(w.buf) != 0 {
		t.Fatalf("%d bytes left over", len(w.buf))
	}
}

func TestDeleteIDReusesIDs(t *testing.T) {
	w := &conn{nextID: 2, handlers: map[uint32]handler{}}
	w.handlers[displayID] = w.display
	a, b := w.newID(nil), w.newID(nil)
	if a != 2 || b != 3 {
		t.Fatalf("ids %d, %d", a, b)
	}
	if err := w.feed(marshal(displayID, 1, a)); err != nil { // delete_id(2)
		t.Fatal(err)
	}
	if _, ok := w.handlers[a]; ok {
		t.Fatal("the deleted id still has a handler")
	}
	if c := w.newID(nil); c != a {
		t.Fatalf("got id %d, want %d reused", c, a)
	}
	if c := w.newID(nil); c != 4 {
		t.Fatalf("got id %d, want 4", c)
	}
}

func TestDisplayError(t *testing.T) {
	w := &conn{nextID: 2, handlers: map[uint32]handler{}}
	w.handlers[displayID] = w.display
	err := w.feed(marshal(displayID, 0, uint32(5), uint32(1), "invalid arguments"))
	if err == nil || err.Error() != "wayland: error 1 on object 5: invalid arguments" {
		t.Fatalf("got %v", err)
	}
}
