package main

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	featSmartShift   = 0x2111 // SmartShift enhanced (with tunable scroll force)
	featDeviceStatus = 0x1D4B // wireless device status: tells us when the mouse reconnects
	swid             = 0x0A   // our software id; the kernel driver and events use others
)

var errTimeout = errors.New("no answer")

// Mouse is a Logitech device spoken to in HID++ 2.0 over its hidraw node.
type Mouse struct {
	node     string
	f        *os.File
	mu       sync.Mutex // one request at a time
	replies  chan []byte
	features map[uint16]byte
	events   chan []byte // reports the mouse sends on its own
	gone     chan struct{}
}

func openMouse(node string) (*Mouse, error) {
	f, err := os.OpenFile(node, os.O_RDWR, 0)
	if err != nil {
		return nil, err
	}
	m := &Mouse{node: node, f: f, replies: make(chan []byte, 8), events: make(chan []byte, 8), features: map[uint16]byte{}, gone: make(chan struct{})}
	go m.readLoop()
	return m, nil
}

func (m *Mouse) Close() { m.f.Close() }

// readLoop hands replies to request and everything else to events.
func (m *Mouse) readLoop() {
	defer close(m.gone)
	buf := make([]byte, 64)
	for {
		n, err := m.f.Read(buf)
		if err != nil {
			return
		}
		r := append([]byte(nil), buf[:n]...)
		if len(r) < 6 || (r[0] != 0x10 && r[0] != 0x11) {
			continue
		}
		if r[3]&0x0F == swid || (r[2] == 0xFF || r[2] == 0x8F) && r[4]&0x0F == swid {
			select {
			case m.replies <- r:
			default:
			}
		} else {
			select {
			case m.events <- r:
			default:
			}
		}
	}
}

func (m *Mouse) request(index, fn byte, params ...byte) ([]byte, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	fnsw := fn<<4 | swid
	msg := make([]byte, 20)
	copy(msg, []byte{0x11, 0xFF, index, fnsw})
	copy(msg[4:], params)
	for len(m.replies) > 0 { // drop late replies to an earlier request
		<-m.replies
	}
	if _, err := m.f.Write(msg); err != nil {
		return nil, err
	}
	timeout := time.After(time.Second)
	for {
		select {
		case r := <-m.replies:
			if (r[2] == 0xFF || r[2] == 0x8F) && r[3] == index && r[4] == fnsw {
				return nil, fmt.Errorf("%s: HID++ error %#x", m.node, r[5])
			}
			if r[2] == index && r[3] == fnsw {
				return r[4:], nil
			}
		case <-m.gone:
			return nil, fmt.Errorf("%s: gone", m.node)
		case <-timeout:
			return nil, fmt.Errorf("%s: %w", m.node, errTimeout)
		}
	}
}

// feature returns the index of a HID++ 2.0 feature (0 = the device lacks it).
func (m *Mouse) feature(id uint16) (byte, error) {
	if i, ok := m.features[id]; ok {
		return i, nil
	}
	r, err := m.request(0, 0, byte(id>>8), byte(id))
	if err != nil {
		return 0, err
	}
	m.features[id] = r[0]
	return r[0], nil
}

// Read returns the wheel mode (1 free-spin, 2 ratchet), the auto-disengage
// threshold and the scroll force.
func (m *Mouse) Read() (mode, threshold, force byte, err error) {
	i, err := m.feature(featSmartShift)
	if err != nil {
		return
	}
	r, err := m.request(i, 1)
	if err != nil {
		return
	}
	return r[0], r[1], r[2], nil
}

func (m *Mouse) Apply(p Profile) error {
	threshold := byte(0xFF) // never free-spins
	if p.SmartShift {
		threshold = sensitivityToThreshold(p.Sensitivity)
	}
	force := byte(min(100, max(1, p.Force)))
	// The wheel only takes new values when the mode is sent with them (0 =
	// "unchanged" stores them until the next power cycle). Send the current
	// mode back, so a free-spin chosen with the button stays.
	mode, _, _, err := m.Read()
	if err != nil {
		return err
	}
	i, _ := m.feature(featSmartShift)
	_, err = m.request(i, 2, mode, threshold, force)
	return err
}

// sensitivityToThreshold maps Options+ sensitivity (1-100, higher = free-spins
// sooner) to the device's auto-disengage threshold (higher = needs a faster
// flick). Fitted on one point: Options+ 88 wrote 10 on an MX Anywhere 3S.
func sensitivityToThreshold(s int) byte {
	return byte(min(0xFE, max(1, int(1+float64(100-s)*0.75+0.5))))
}

// findMice opens the hidraw nodes of Logitech devices that speak HID++ and
// have SmartShift, skipping the nodes in skip.
func findMice(skip map[string]*Mouse) []*Mouse {
	var mice []*Mouse
	dirs, _ := filepath.Glob("/sys/class/hidraw/hidraw*")
	for _, dir := range dirs {
		node := "/dev/" + filepath.Base(dir)
		if _, ok := skip[node]; ok {
			continue
		}
		uevent, err1 := os.ReadFile(dir + "/device/uevent")
		desc, err2 := os.ReadFile(dir + "/device/report_descriptor")
		if err1 != nil || err2 != nil || !strings.Contains(string(uevent), ":0000046D:") ||
			!bytes.Contains(desc, []byte{0x85, 0x11}) { // no long HID++ report
			continue
		}
		m, err := openMouse(node)
		if err != nil {
			continue
		}
		if i, err := m.feature(featSmartShift); err == nil && i != 0 {
			mice = append(mice, m)
		} else {
			m.Close()
		}
	}
	return mice
}
