// logi-wheel sets SmartShift, its sensitivity and the scroll force of
// Logitech mice per app on KDE Plasma, like Logi Options+ does on Windows.
//
// A KWin script, loaded by the daemon, reports each window activation over
// D-Bus. The daemon picks the matching profile in /etc/logi-wheel.toml and
// sends one HID++ command (feature 0x2111, SmartShift enhanced) to every
// Logitech mouse on /dev/hidraw*. It never touches wheel events or the wheel
// resolution, so the kernel's hi-res smooth scrolling is left alone.
//
// Usage:
//
//	logi-wheel           run the daemon (the systemd user service does this)
//	logi-wheel status    print the raw values each mouse holds now
package main

import (
	"fmt"
	"log"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/BurntSushi/toml"
	"github.com/godbus/dbus/v5"
)

const (
	configPath = "/etc/logi-wheel.toml"
	kwinScript = "/usr/share/logi-wheel/logi-wheel.js"
	busName    = "local.LogiWheel"
	objectPath = "/local/LogiWheel"
)

type Profile struct {
	SmartShift  bool `toml:"smartshift"`
	Sensitivity int  `toml:"sensitivity"`
	Force       int  `toml:"force"`
}

// profileFor returns the [app.<name>] profile matching a window's class or
// desktop file name, with the keys it leaves out taken from [default].
func profileFor(class, desktop string) (string, Profile) {
	var cfg struct {
		Default toml.Primitive
		App     map[string]toml.Primitive
	}
	p := Profile{SmartShift: true, Sensitivity: 50, Force: 50}
	md, err := toml.DecodeFile(configPath, &cfg)
	if err != nil {
		log.Printf("%s: %v; using defaults", configPath, err)
		return "default", p
	}
	md.PrimitiveDecode(cfg.Default, &p)
	for name, prim := range cfg.App {
		if strings.EqualFold(name, class) || strings.EqualFold(name, desktop) {
			md.PrimitiveDecode(prim, &p)
			return name, p
		}
	}
	return "default", p
}

type daemon struct {
	mu      sync.Mutex
	mice    map[string]*Mouse
	profile *Profile
}

func (d *daemon) apply(m *Mouse) {
	if d.profile == nil {
		return
	}
	if err := m.Apply(*d.profile); err != nil {
		log.Print(err)
	}
}

func (d *daemon) rescan() {
	d.mu.Lock()
	defer d.mu.Unlock()
	for _, m := range findMice(d.mice) {
		log.Printf("%s: SmartShift mouse found", m.node)
		status, _ := m.feature(featDeviceStatus)
		d.mice[m.node] = m
		d.apply(m)
		go d.watch(m, status)
	}
}

// watch re-sends the profile when the mouse reconnects (it forgets the wheel
// settings) and forgets the mouse when its node goes away.
func (d *daemon) watch(m *Mouse, status byte) {
	for {
		select {
		case r := <-m.events:
			if status != 0 && r[2] == status && r[3]>>4 == 0 {
				time.Sleep(500 * time.Millisecond)
				d.mu.Lock()
				d.apply(m)
				d.mu.Unlock()
			}
		case <-m.gone:
			log.Printf("%s: gone", m.node)
			d.mu.Lock()
			delete(d.mice, m.node)
			d.mu.Unlock()
			m.Close()
			return
		}
	}
}

// ActiveWindow is called by the KWin script over D-Bus.
func (d *daemon) ActiveWindow(class, desktop string) *dbus.Error {
	go func() {
		name, p := profileFor(class, desktop)
		d.mu.Lock()
		defer d.mu.Unlock()
		if d.profile != nil && *d.profile == p {
			return
		}
		d.profile = &p
		log.Printf("%s -> [%s] %+v", firstSet(class, desktop), name, p)
		for _, m := range d.mice {
			d.apply(m)
		}
	}()
	return nil
}

func firstSet(a, b string) string {
	if a != "" {
		return a
	}
	return b
}

// loadKWinScript (re)loads the script, so it reports the window that is
// active right now.
func loadKWinScript(conn *dbus.Conn) error {
	kwin := conn.Object("org.kde.KWin", "/Scripting")
	const iface = "org.kde.kwin.Scripting."
	var loaded bool
	if err := kwin.Call(iface+"isScriptLoaded", 0, "logi-wheel").Store(&loaded); err != nil {
		return err
	}
	if loaded {
		kwin.Call(iface+"unloadScript", 0, "logi-wheel")
	}
	if err := kwin.Call(iface+"loadScript", 0, kwinScript, "logi-wheel").Err; err != nil {
		return err
	}
	return kwin.Call(iface+"start", 0).Err
}

func runDaemon() {
	log.SetFlags(0)
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		log.Fatal(err)
	}
	d := &daemon{mice: map[string]*Mouse{}}
	if err := conn.Export(d, objectPath, busName); err != nil {
		log.Fatal(err)
	}
	reply, err := conn.RequestName(busName, dbus.NameFlagDoNotQueue)
	if err != nil || reply != dbus.RequestNameReplyPrimaryOwner {
		log.Fatalf("D-Bus name %s taken (%v)", busName, err)
	}
	d.rescan()
	if err := loadKWinScript(conn); err != nil {
		log.Fatalf("loading the KWin script: %v", err)
	}
	for range time.Tick(3 * time.Second) { // mouse switched back to this PC
		d.rescan()
	}
}

func status() {
	mice := findMice(nil)
	if len(mice) == 0 {
		fmt.Fprintln(os.Stderr, "no SmartShift mouse found (connected? readable /dev/hidraw*?)")
		os.Exit(1)
	}
	for _, m := range mice {
		mode, threshold, force, err := m.Read()
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			continue
		}
		name := map[byte]string{1: "free-spin", 2: "ratchet"}[mode]
		fmt.Printf("%s: wheel %s, auto-disengage threshold %d, force %d\n", m.node, name, threshold, force)
	}
}

func main() {
	switch {
	case len(os.Args) == 1:
		runDaemon()
	case len(os.Args) == 2 && os.Args[1] == "status":
		status()
	default:
		fmt.Fprintln(os.Stderr, "usage: logi-wheel [status]")
		os.Exit(2)
	}
}
