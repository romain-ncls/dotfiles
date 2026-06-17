// Global Super+Shift+Scroll -> Spotify volume.
//
// KDE Plasma on Wayland cannot bind mouse-wheel events as global shortcuts, so
// we read input events straight from evdev: we track the held state of the
// Super and Shift modifiers (from any keyboard) and, when the wheel moves while
// both are held, run `spotify-vol up|down`.
//
// Every /dev/input/event* device is opened read-only (never grabbed), so normal
// scrolling and typing are unaffected. Requires membership of the `input` group.
package main

import (
	"encoding/binary"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"
)

// Linux input event types/codes (see <linux/input-event-codes.h>).
const (
	evKey = 0x01
	evRel = 0x02

	relWheel = 0x08

	keyLeftShift  = 42
	keyRightShift = 54
	keyLeftMeta   = 125
	keyRightMeta  = 126

	// struct input_event on 64-bit Linux: 16-byte timeval + u16 type + u16 code + s32 value.
	eventSize = 24
)

type event struct {
	typ   uint16
	code  uint16
	value int32
}

func parse(b []byte) event {
	return event{
		typ:   binary.LittleEndian.Uint16(b[16:18]),
		code:  binary.LittleEndian.Uint16(b[18:20]),
		value: int32(binary.LittleEndian.Uint32(b[20:24])),
	}
}

func isModifier(code uint16) bool {
	switch code {
	case keyLeftShift, keyRightShift, keyLeftMeta, keyRightMeta:
		return true
	}
	return false
}

func main() {
	spotifyVol := os.Getenv("SPOTIFY_VOL")
	if spotifyVol == "" {
		spotifyVol = "spotify-vol"
	}

	events := make(chan event, 64)
	go scanDevices(events)

	// A single consumer owns the modifier state, so no locking is needed here.
	pressed := map[uint16]bool{}
	held := func(a, b uint16) bool { return pressed[a] || pressed[b] }

	for ev := range events {
		switch {
		case ev.typ == evKey && isModifier(ev.code):
			if ev.value == 1 { // down (2 == autorepeat, ignored)
				pressed[ev.code] = true
			} else if ev.value == 0 { // up
				delete(pressed, ev.code)
			}
		case ev.typ == evRel && ev.code == relWheel && ev.value != 0:
			if held(keyLeftMeta, keyRightMeta) && held(keyLeftShift, keyRightShift) {
				dir := "up"
				if ev.value < 0 {
					dir = "down"
				}
				_ = exec.Command(spotifyVol, dir).Start()
			}
		}
	}
}

// scanDevices opens every input device and starts a reader goroutine for each,
// rescanning every 2s so hot-plugged mice/keyboards are picked up (and removed
// ones reopened when they return).
func scanDevices(events chan<- event) {
	var mu sync.Mutex
	open := map[string]bool{}

	for {
		paths, _ := filepath.Glob("/dev/input/event*")
		for _, p := range paths {
			mu.Lock()
			seen := open[p]
			if !seen {
				open[p] = true
			}
			mu.Unlock()
			if seen {
				continue
			}

			f, err := os.Open(p)
			if err != nil {
				mu.Lock()
				delete(open, p)
				mu.Unlock()
				continue
			}
			go readDevice(p, f, events, &mu, open)
		}
		time.Sleep(2 * time.Second)
	}
}

func readDevice(path string, f *os.File, events chan<- event, mu *sync.Mutex, open map[string]bool) {
	defer func() {
		f.Close()
		mu.Lock()
		delete(open, path)
		mu.Unlock()
	}()

	buf := make([]byte, eventSize)
	for {
		if _, err := io.ReadFull(f, buf); err != nil {
			return // device unplugged or read error: drop it, scanner may reopen later
		}
		ev := parse(buf)
		if (ev.typ == evKey && isModifier(ev.code)) || (ev.typ == evRel && ev.code == relWheel) {
			events <- ev
		}
	}
}
