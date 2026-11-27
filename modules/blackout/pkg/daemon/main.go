// blackout covers every screen in black after some time without input, for
// a desktop on an OLED TV: black OLED pixels are off, so the screen rests
// as if the TV were off. Unlike turning the screen off (DPMS), the HDMI
// signal stays, so the TV doesn't go to standby, and the first key or mouse
// move brings the desktop back; that input goes to the black layer, not to
// an app. It waits while something keeps the screen on. KWin holds back
// the idle event itself for Wayland idle inhibitors (mpv while it plays) and
// org.freedesktop.ScreenSaver inhibitions (browsers playing a video, SDL
// games), which KWin serves; blackout also follows PowerDevil's "keep the
// screen on" inhibitions (the battery applet's manual block).
//
// Wayland protocols, all in KWin: ext-idle-notify-v1 (when the user is
// idle), wlr-layer-shell (a surface above everything, the panel included),
// single-pixel-buffer and viewporter (one black pixel stretched over the
// output: no shared memory).
//
// `blackout now` (the panel's button) blacks the screens out at once: it
// sends SIGUSR1 to the service. The screens come back on the first input
// after a second without any, so the click or the shortcut's keys don't
// count; video playing doesn't hold that back.
package main

import (
	"flag"
	"fmt"
	"log"
	"math"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
	"time"
)

const (
	layerOverlay         = 3             // zwlr_layer_shell_v1.layer.overlay
	anchorAll            = 1 | 2 | 4 | 8 // top, bottom, left, right: the whole output
	keyboardExclusive    = 1             // the key that wakes the screen goes to the black layer
	seatPointer          = 1             // wl_seat.capability.pointer
	changeScreenSettings = 4             // PowerDevil's policy for "keep the screen on"
	settle               = time.Second   // on demand: the input that ends it comes after this much calm
)

func main() {
	idle := flag.Duration("idle", 5*time.Minute, "time without input before the screens go black")
	flag.Parse()
	log.SetFlags(0)
	if flag.Arg(0) == "now" {
		cmd := exec.Command("systemctl", "--user", "kill", "--signal=SIGUSR1", "--kill-whom=main", "blackout.service")
		cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
		if err := cmd.Run(); err != nil {
			os.Exit(1)
		}
		return
	}
	if err := run(*idle); err != nil {
		log.Fatal(err)
	}
}

type output struct {
	id      uint32 // our wl_output
	version uint32
	cover   *cover
}

// cover is the black layer on one output.
type cover struct {
	surface, layer, viewport uint32
}

type app struct {
	w        *conn
	registry uint32
	// globals we bind
	compositor, layerShell, pixels, viewporter, seat, notifier uint32
	seatVersion, notifierVersion                               uint32
	pointer                                                    uint32
	black                                                      uint32             // the black wl_buffer
	outputs                                                    map[uint32]*output // by global name

	idle      bool // no input for the timeout, and no Wayland inhibitor
	inhibited bool // PowerDevil holds a "keep the screen on" inhibition

	onDemand      bool   // black since `blackout now`, until the next input
	demandNote    uint32 // its input idle notification
	demandSettled bool   // a second without input has passed since
}

func run(timeout time.Duration) error {
	w, err := dial()
	if err != nil {
		return err
	}
	a := &app{w: w, outputs: map[uint32]*output{}}
	a.registry = w.newID(a.registryEvent)
	w.req(displayID, 1, a.registry) // get_registry
	if err := w.roundtrip(); err != nil {
		return err
	}
	for name, id := range map[string]uint32{
		"wl_compositor":                     a.compositor,
		"zwlr_layer_shell_v1":               a.layerShell,
		"wp_single_pixel_buffer_manager_v1": a.pixels,
		"wp_viewporter":                     a.viewporter,
		"wl_seat":                           a.seat,
		"ext_idle_notifier_v1":              a.notifier,
	} {
		if id == 0 {
			return fmt.Errorf("the compositor has no %s", name)
		}
	}
	a.black = w.newID(nil)
	w.req(a.pixels, 1, a.black, uint32(0), uint32(0), uint32(0), uint32(math.MaxUint32)) // create_u32_rgba_buffer: opaque black
	// get_idle_notification follows idle inhibitors (get_input_idle_notification wouldn't)
	w.req(a.notifier, 1, w.newID(a.idleEvent), uint32(timeout.Milliseconds()), a.seat)
	if err := w.roundtrip(); err != nil {
		return err
	}

	chunks, readErr := make(chan []byte), make(chan error, 1)
	go func() {
		for {
			b, err := w.read()
			if err != nil {
				readErr <- err
				return
			}
			chunks <- b
		}
	}()
	demands := make(chan os.Signal, 1)
	signal.Notify(demands, syscall.SIGUSR1)
	inhibitions := make(chan bool, 1)
	if err := watchInhibitions(inhibitions); err != nil {
		log.Printf("PowerDevil's inhibitions aren't followed: %v", err)
	}
	log.Printf("blacking out after %v without input", timeout)
	for {
		select {
		case b := <-chunks:
			if err := w.feed(b); err != nil {
				return err
			}
		case err := <-readErr:
			return err
		case on := <-inhibitions:
			a.inhibited = on
			a.update()
		case <-demands:
			a.blackNow()
		}
		if w.err != nil {
			return w.err
		}
	}
}

func (a *app) registryEvent(op uint16, m *args) {
	w := a.w
	switch op {
	case 0: // global(name, interface, version)
		name, iface, version := m.uint(), m.str(), m.uint()
		bind := func(max uint32, h handler) (uint32, uint32) {
			v := min(version, max)
			id := w.newID(h)
			w.req(a.registry, 0, name, iface, v, id) // bind: a new_id with no type takes its interface and version
			return id, v
		}
		switch iface {
		case "wl_compositor":
			a.compositor, _ = bind(4, nil)
		case "zwlr_layer_shell_v1":
			a.layerShell, _ = bind(4, nil)
		case "wp_single_pixel_buffer_manager_v1":
			a.pixels, _ = bind(1, nil)
		case "wp_viewporter":
			a.viewporter, _ = bind(1, nil)
		case "ext_idle_notifier_v1":
			a.notifier, a.notifierVersion = bind(2, nil) // 2: input idle notifications
		case "wl_seat":
			if a.seat == 0 { // the first seat; KWin has one
				a.seat, a.seatVersion = bind(5, a.seatEvent)
			}
		case "wl_output":
			o := &output{}
			o.id, o.version = bind(4, nil)
			a.outputs[name] = o
			a.update() // a screen plugged in while black gets covered too
		}
	case 1: // global_remove(name)
		name := m.uint()
		if o := a.outputs[name]; o != nil {
			a.uncover(o)
			if o.version >= 3 {
				w.destroy(o.id, 0) // release
			}
			delete(a.outputs, name)
		}
	}
}

func (a *app) seatEvent(op uint16, m *args) {
	if op != 0 { // capabilities(caps)
		return
	}
	caps := m.uint()
	switch {
	case caps&seatPointer != 0 && a.pointer == 0:
		a.pointer = a.w.newID(a.pointerEvent)
		a.w.req(a.seat, 0, a.pointer) // get_pointer
	case caps&seatPointer == 0 && a.pointer != 0:
		if a.seatVersion >= 3 {
			a.w.destroy(a.pointer, 1) // release
		}
		a.pointer = 0
	}
}

// pointerEvent hides the cursor over the black layer: it would stay still
// there, in the same place, as long as the screen is black.
func (a *app) pointerEvent(op uint16, m *args) {
	if op != 0 { // enter(serial, surface, x, y)
		return
	}
	serial, surface := m.uint(), m.uint()
	for _, o := range a.outputs {
		if o.cover != nil && o.cover.surface == surface {
			a.w.req(a.pointer, 0, serial, uint32(0), int32(0), int32(0)) // set_cursor with no surface: hidden
		}
	}
}

func (a *app) idleEvent(op uint16, _ *args) {
	switch op {
	case 0: // idled
		a.idle = true
	case 1: // resumed
		a.idle = false
	}
	a.update()
}

// blackNow covers the outputs until the next input that comes after a
// second without any.
func (a *app) blackNow() {
	if a.onDemand {
		return
	}
	a.onDemand, a.demandSettled = true, false
	op := uint16(2) // get_input_idle_notification: inhibitors don't hold it back
	if a.notifierVersion < 2 {
		op = 1
	}
	a.demandNote = a.w.newID(a.demandEvent)
	a.w.req(a.notifier, op, a.demandNote, uint32(settle.Milliseconds()), a.seat)
	a.update()
}

func (a *app) demandEvent(op uint16, _ *args) {
	switch op {
	case 0: // idled: from now on, input ends it
		a.demandSettled = true
	case 1: // resumed
		if !a.demandSettled {
			return
		}
		a.w.destroy(a.demandNote, 0)
		a.onDemand, a.demandNote = false, 0
		a.update()
	}
}

// update covers or uncovers the outputs to match the state.
func (a *app) update() {
	black := a.idle && !a.inhibited || a.onDemand
	changed := false
	for _, o := range a.outputs {
		switch {
		case black && o.cover == nil:
			a.coverOutput(o)
			changed = true
		case !black && o.cover != nil:
			a.uncover(o)
			changed = true
		}
	}
	if changed {
		if black {
			log.Print("black")
		} else {
			log.Print("back")
		}
	}
}

func (a *app) coverOutput(o *output) {
	w := a.w
	c := &cover{surface: w.newID(nil)}
	w.req(a.compositor, 0, c.surface) // create_surface
	c.layer = w.newID(func(op uint16, m *args) { a.layerEvent(o, c, op, m) })
	w.req(a.layerShell, 0, c.layer, c.surface, o.id, uint32(layerOverlay), "blackout") // get_layer_surface
	w.req(c.layer, 1, uint32(anchorAll))                                               // set_anchor
	w.req(c.layer, 2, int32(-1))                                                       // set_exclusive_zone: -1 covers the panel too
	w.req(c.layer, 4, uint32(keyboardExclusive))                                       // set_keyboard_interactivity
	w.req(c.surface, 6)                                                                // commit with no buffer: the compositor answers with a configure
	o.cover = c
}

func (a *app) layerEvent(o *output, c *cover, op uint16, m *args) {
	if o.cover != c {
		return
	}
	w := a.w
	switch op {
	case 0: // configure(serial, width, height)
		serial, width, height := m.uint(), m.uint(), m.uint()
		w.req(c.layer, 6, serial) // ack_configure
		if c.viewport == 0 {
			c.viewport = w.newID(nil)
			w.req(a.viewporter, 1, c.viewport, c.surface)    // get_viewport
			w.req(c.surface, 1, a.black, int32(0), int32(0)) // attach
		}
		if width > 0 && height > 0 {
			w.req(c.viewport, 2, int32(width), int32(height)) // set_destination: the pixel fills the output
		}
		w.req(c.surface, 2, int32(0), int32(0), int32(math.MaxInt32), int32(math.MaxInt32)) // damage
		w.req(c.surface, 6)                                                                 // commit
	case 1: // closed: the output went away
		a.uncover(o)
	}
}

func (a *app) uncover(o *output) {
	c := o.cover
	if c == nil {
		return
	}
	w := a.w
	w.destroy(c.layer, 7) // the role first, then the surface
	if c.viewport != 0 {
		w.destroy(c.viewport, 0)
	}
	w.destroy(c.surface, 0)
	o.cover = nil
}

func init() {
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "usage: blackout [-idle 5m]\n       blackout now\n\nCovers every screen in black after the idle time without input,\nor at once (now: tells the running service).\n")
		flag.PrintDefaults()
	}
}
