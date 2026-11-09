// The Bluetooth pairing agent (org.bluez.Agent1; docs/hyprland.md): BlueZ
// asks it what a pairing needs, a code to show, to compare or to type, and
// whether a device may pair or use a service. Each request goes to the
// shell's Bluetooth popup (Bluetooth.qml: qs ipc call bluetooth ask), which
// answers the ones that wait on the session bus (org.shadesmar.Spanreed,
// /org/shadesmar/Bluetooth, Answer); BlueZ's Cancel closes them. In Plasma,
// bluedevil is the agent.
package main

import (
	"fmt"
	"log"
	"strconv"
	"sync"
	"time"

	"github.com/godbus/dbus/v5"
)

const (
	agentPath   = dbus.ObjectPath("/org/shadesmar/agent")
	agentIface  = "org.bluez.Agent1"
	answerPath  = dbus.ObjectPath("/org/shadesmar/Bluetooth")
	answerIface = "org.shadesmar.Bluetooth"
)

// BlueZ waits a minute for an agent's answer (src/agent.c), then cancels;
// past this, nobody waits for it.
var answerWithin = 70 * time.Second

var (
	rejected = dbus.NewError("org.bluez.Error.Rejected", nil)
	canceled = dbus.NewError("org.bluez.Error.Canceled", nil)
)

type answer struct {
	ok    bool
	value string
}

// agent: BlueZ's calls (its exported methods, BlueZ's names) and the
// requests waiting for the shell's answer, by id.
type agent struct {
	mu      sync.Mutex
	next    uint32
	pending map[uint32]chan answer
	// the shell's bluetooth target: fn and its arguments
	shell func(fn string, args ...string) error
}

func newAgent(shell func(fn string, args ...string) error) *agent {
	return &agent{pending: map[uint32]chan answer{}, shell: shell}
}

func (a *agent) id() uint32 {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.next++
	return a.next
}

// ask asks the shell and waits for its answer: Rejected when it says no or
// can't ask, Canceled when BlueZ cancels or nobody answers.
func (a *agent) ask(kind string, device dbus.ObjectPath, code string) (string, *dbus.Error) {
	id := a.id()
	ch := make(chan answer, 1)
	a.mu.Lock()
	a.pending[id] = ch
	a.mu.Unlock()
	defer func() {
		a.mu.Lock()
		delete(a.pending, id)
		a.mu.Unlock()
	}()
	if err := a.shell("ask", fmt.Sprint(id), kind, string(device), code, "0"); err != nil {
		log.Printf("bluetooth %s: %v", kind, err)
		return "", rejected
	}
	select {
	case ans, open := <-ch:
		if !open {
			return "", canceled
		}
		if !ans.ok {
			return "", rejected
		}
		return ans.value, nil
	case <-time.After(answerWithin):
		go a.shell("cancel", fmt.Sprint(id))
		return "", canceled
	}
}

// show has the shell show a code to type on the device; nothing to answer.
func (a *agent) show(kind string, device dbus.ObjectPath, code string, entered int) *dbus.Error {
	if err := a.shell("ask", fmt.Sprint(a.id()), kind, string(device), code, strconv.Itoa(entered)); err != nil {
		log.Printf("bluetooth %s: %v", kind, err)
		return rejected
	}
	return nil
}

// answered: the shell's answer to request id (Answer, on the session bus).
func (a *agent) answered(id uint32, ok bool, value string) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if ch, found := a.pending[id]; found {
		ch <- answer{ok, value}
		delete(a.pending, id)
	}
}

func (a *agent) Release() *dbus.Error {
	log.Print("bluetooth: BlueZ let the agent go")
	return nil
}

// RequestPinCode: a legacy device's PIN, typed in the popup (its own,
// often 0000, or one typed on it too).
func (a *agent) RequestPinCode(device dbus.ObjectPath) (string, *dbus.Error) {
	pin, err := a.ask("pin", device, "")
	if err != nil {
		return "", err
	}
	if len(pin) < 1 || len(pin) > 16 {
		return "", rejected
	}
	return pin, nil
}

// DisplayPinCode: a PIN to type on the device (a legacy keyboard).
func (a *agent) DisplayPinCode(device dbus.ObjectPath, pin string) *dbus.Error {
	return a.show("show-pin", device, pin, 0)
}

// RequestPasskey: the six digits the device shows, typed in the popup.
func (a *agent) RequestPasskey(device dbus.ObjectPath) (uint32, *dbus.Error) {
	typed, err := a.ask("passkey", device, "")
	if err != nil {
		return 0, err
	}
	n, perr := strconv.ParseUint(typed, 10, 32)
	if perr != nil || n > 999999 {
		return 0, rejected
	}
	return uint32(n), nil
}

// DisplayPasskey: six digits to type on the device (a keyboard), called
// again as they're typed (entered).
func (a *agent) DisplayPasskey(device dbus.ObjectPath, passkey uint32, entered uint16) *dbus.Error {
	return a.show("show-passkey", device, fmt.Sprintf("%06d", passkey), int(entered))
}

// RequestConfirmation: the six digits both show (a phone), confirmed.
func (a *agent) RequestConfirmation(device dbus.ObjectPath, passkey uint32) *dbus.Error {
	_, err := a.ask("confirm", device, fmt.Sprintf("%06d", passkey))
	return err
}

// RequestAuthorization: a device pairing from its side, with no code.
func (a *agent) RequestAuthorization(device dbus.ObjectPath) *dbus.Error {
	_, err := a.ask("authorize", device, "")
	return err
}

// AuthorizeService: a paired device that isn't trusted, connecting to a
// service (its UUID).
func (a *agent) AuthorizeService(device dbus.ObjectPath, uuid string) *dbus.Error {
	_, err := a.ask("service", device, uuid)
	return err
}

// Cancel: BlueZ gave up on the request (one at a time, it doesn't say
// which): every waiting one ends, the popup closes it.
func (a *agent) Cancel() *dbus.Error {
	a.mu.Lock()
	for id, ch := range a.pending {
		close(ch)
		delete(a.pending, id)
	}
	a.mu.Unlock()
	go a.shell("cancel", "0")
	return nil
}

// answers serves the shell's answers.
type answers struct{ a *agent }

func (s answers) Answer(id uint32, ok bool, value string) *dbus.Error {
	s.a.answered(id, ok, value)
	return nil
}

// serveAgent registers the agent with BlueZ, as its default, now and each
// time bluetoothd starts again. The dev rigs (HYPR_DEV) share the machine's
// BlueZ: the agent is on the rig's session bus instead, for tests to call.
func serveAgent(session *dbus.Conn, shell func(fn string, args ...string) error) error {
	a := newAgent(shell)
	if err := session.Export(answers{a}, answerPath, answerIface); err != nil {
		return err
	}
	if dev() {
		return session.Export(a, agentPath, agentIface)
	}
	system, err := dbus.ConnectSystemBus()
	if err != nil {
		return err
	}
	if err := system.Export(a, agentPath, agentIface); err != nil {
		return err
	}
	if err := system.AddMatchSignal(dbus.WithMatchSender("org.freedesktop.DBus"), dbus.WithMatchMember("NameOwnerChanged"), dbus.WithMatchArg(0, "org.bluez")); err != nil {
		return err
	}
	signals := make(chan *dbus.Signal, 8)
	system.Signal(signals)
	go func() {
		for s := range signals {
			if s.Name == "org.freedesktop.DBus.NameOwnerChanged" && len(s.Body) == 3 {
				if owner, _ := s.Body[2].(string); owner != "" {
					register(system)
				}
			}
		}
	}()
	register(system)
	return nil
}

// register: without bluetoothd (not started), nothing; it registers once
// bluetoothd is there (serveAgent).
func register(system *dbus.Conn) {
	manager := system.Object("org.bluez", "/org/bluez")
	if err := manager.Call("org.bluez.AgentManager1.RegisterAgent", dbus.FlagNoAutoStart, agentPath, "KeyboardDisplay").Err; err != nil {
		log.Printf("bluetooth: no pairing agent: %v", err)
		return
	}
	if err := manager.Call("org.bluez.AgentManager1.RequestDefaultAgent", dbus.FlagNoAutoStart, agentPath).Err; err != nil {
		log.Printf("bluetooth: the pairing agent isn't the default: %v", err)
		return
	}
	log.Print("bluetooth: the pairing agent is BlueZ's default")
}
