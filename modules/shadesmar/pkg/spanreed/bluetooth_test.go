package main

import (
	"errors"
	"strconv"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
)

const device = dbus.ObjectPath("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

// a shell that answers each ask with reply (nil: doesn't answer), and
// records the calls
type fakeShell struct {
	a     *agent
	calls chan []string
	reply func(kind string) *answer
	fail  bool
}

func newFake(reply func(kind string) *answer) *fakeShell {
	f := &fakeShell{calls: make(chan []string, 16), reply: reply}
	f.a = newAgent(f.call)
	return f
}

func (f *fakeShell) call(fn string, args ...string) error {
	f.calls <- append([]string{fn}, args...)
	if f.fail {
		return errors.New("no shell")
	}
	if fn == "ask" && f.reply != nil {
		if r := f.reply(args[1]); r != nil {
			id, _ := strconv.ParseUint(args[0], 10, 32)
			go answers{f.a}.Answer(uint32(id), r.ok, r.value)
		}
	}
	return nil
}

func TestConfirmation(t *testing.T) {
	f := newFake(func(string) *answer { return &answer{ok: true} })
	if err := f.a.RequestConfirmation(device, 42); err != nil {
		t.Fatalf("confirmed: %v", err)
	}
	call := <-f.calls
	if call[2] != "confirm" || call[3] != string(device) || call[4] != "000042" {
		t.Fatalf("asked %v", call)
	}
	f = newFake(func(string) *answer { return &answer{ok: false} })
	if err := f.a.RequestConfirmation(device, 42); err != rejected {
		t.Fatalf("said no: %v", err)
	}
}

func TestPasskeyAndPin(t *testing.T) {
	f := newFake(func(kind string) *answer {
		if kind == "passkey" {
			return &answer{ok: true, value: "012345"}
		}
		return &answer{ok: true, value: "0000"}
	})
	if n, err := f.a.RequestPasskey(device); err != nil || n != 12345 {
		t.Fatalf("passkey %d %v", n, err)
	}
	if pin, err := f.a.RequestPinCode(device); err != nil || pin != "0000" {
		t.Fatalf("pin %q %v", pin, err)
	}
	f = newFake(func(string) *answer { return &answer{ok: true, value: "1234567"} })
	if _, err := f.a.RequestPasskey(device); err != rejected {
		t.Fatalf("seven digits: %v", err)
	}
}

func TestShow(t *testing.T) {
	f := newFake(nil)
	if err := f.a.DisplayPasskey(device, 7, 3); err != nil {
		t.Fatal(err)
	}
	if call := <-f.calls; call[2] != "show-passkey" || call[4] != "000007" || call[5] != "3" {
		t.Fatalf("showed %v", call)
	}
	f.fail = true
	if err := f.a.DisplayPinCode(device, "1234"); err != rejected {
		t.Fatalf("no shell to show it: %v", err)
	}
}

func TestCancel(t *testing.T) {
	f := newFake(nil)
	done := make(chan *dbus.Error)
	go func() { done <- f.a.RequestAuthorization(device) }()
	<-f.calls // asked
	f.a.Cancel()
	if err := <-done; err != canceled {
		t.Fatalf("canceled: %v", err)
	}
	if call := <-f.calls; call[0] != "cancel" || call[1] != "0" {
		t.Fatalf("closed %v", call)
	}
	if len(f.a.pending) != 0 {
		t.Fatal("still pending")
	}
}

func TestNobodyAnswers(t *testing.T) {
	answerWithin = 50 * time.Millisecond
	defer func() { answerWithin = 70 * time.Second }()
	f := newFake(nil)
	if err := f.a.AuthorizeService(device, "0000110b-0000-1000-8000-00805f9b34fb"); err != canceled {
		t.Fatalf("timed out: %v", err)
	}
	<-f.calls // asked
	if call := <-f.calls; call[0] != "cancel" || call[1] != "1" {
		t.Fatalf("closed %v", call)
	}
	f = newFake(nil)
	f.fail = true
	if err := f.a.RequestAuthorization(device); err != rejected {
		t.Fatalf("no shell: %v", err)
	}
}
