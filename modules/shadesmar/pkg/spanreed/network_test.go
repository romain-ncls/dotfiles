package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
)

const connPath = dbus.ObjectPath("/org/freedesktop/NetworkManager/Settings/7")

type fakeKeys struct {
	mu   sync.Mutex
	kept map[string]string // uuid/setting/key
}

func (k *fakeKeys) lookup(uuid, setting, key string) (string, error) {
	k.mu.Lock()
	defer k.mu.Unlock()
	return k.kept[uuid+"/"+setting+"/"+key], nil
}

func (k *fakeKeys) store(uuid, setting, key, label, value string) error {
	k.mu.Lock()
	defer k.mu.Unlock()
	k.kept[uuid+"/"+setting+"/"+key] = value
	return nil
}

func (k *fakeKeys) forget(uuid string) error {
	k.mu.Lock()
	defer k.mu.Unlock()
	for id := range k.kept {
		if strings.HasPrefix(id, uuid+"/") {
			delete(k.kept, id)
		}
	}
	return nil
}

// a shell that answers each ask with reply (nil: doesn't answer), and
// records the calls
type fakeNetShell struct {
	n     *netAgent
	calls chan []string
	reply func(fields []field) *string // the answer's JSON values, or "no"
}

func newNetFake(kept map[string]string, reply func([]field) *string) *fakeNetShell {
	f := &fakeNetShell{calls: make(chan []string, 16), reply: reply}
	f.n = newNetAgent(f.call, &fakeKeys{kept: kept})
	return f
}

func (f *fakeNetShell) call(fn string, args ...string) error {
	f.calls <- append([]string{fn}, args...)
	if fn == "ask" && f.reply != nil {
		if r := f.reply(askOf(append([]string{fn}, args...)).Fields); r != nil {
			id, _ := strconv.Atoi(args[0])
			js := `{"id":` + args[0] + `,"ok":false}`
			if *r != "no" {
				js = `{"id":` + strconv.Itoa(id) + `,"ok":true,"values":` + *r + `}`
			}
			go netAnswers{f.n}.Answer(js)
		}
	}
	return nil
}

// the request a shell call carries
type askReq struct {
	Setting, Name, Message string
	Fields                 []field
}

func askOf(call []string) (r askReq) {
	json.Unmarshal([]byte(call[2]), &r)
	return
}

func answerWith(js string) func([]field) *string { return func([]field) *string { return &js } }

func wifi(flags uint32) connection {
	c := connection{
		"connection":               {"id": dbus.MakeVariant("Freebox"), "uuid": dbus.MakeVariant("u1")},
		"802-11-wireless-security": {"key-mgmt": dbus.MakeVariant("wpa-psk")},
	}
	if flags != 0 {
		c["802-11-wireless-security"]["psk-flags"] = dbus.MakeVariant(flags)
	}
	return c
}

func secretOf(t *testing.T, c connection, setting, key string) string {
	t.Helper()
	v, _ := c[setting][key].Value().(string)
	return v
}

func TestWifiKept(t *testing.T) {
	f := newNetFake(map[string]string{"u1/802-11-wireless-security/psk": "kept"}, nil)
	c, err := f.n.GetSecrets(wifi(agentOwned), connPath, "802-11-wireless-security", nil, 0)
	if err != nil || secretOf(t, c, "802-11-wireless-security", "psk") != "kept" {
		t.Fatalf("kept: %v %v", c, err)
	}
	if len(f.calls) != 0 {
		t.Fatal("asked anyway")
	}
}

func TestWifiAsked(t *testing.T) {
	var asked []field
	f := newNetFake(map[string]string{}, func(fields []field) *string {
		asked = fields
		js := `{"psk":"typed"}`
		return &js
	})
	// nothing kept, no interaction: nothing
	if _, err := f.n.GetSecrets(wifi(agentOwned), connPath, "802-11-wireless-security", nil, 0); err != noSecrets {
		t.Fatalf("no interaction: %v", err)
	}
	c, err := f.n.GetSecrets(wifi(agentOwned), connPath, "802-11-wireless-security", nil, allowInteraction)
	if err != nil || secretOf(t, c, "802-11-wireless-security", "psk") != "typed" {
		t.Fatalf("typed: %v %v", c, err)
	}
	call := <-f.calls
	if r := askOf(call); call[0] != "ask" || r.Setting != "802-11-wireless-security" || r.Name != "Freebox" || r.Message != "Asks for its password" {
		t.Fatalf("asked %v", call)
	}
	if len(asked) != 1 || asked[0] != (field{"psk", "Password", true, false}) {
		t.Fatalf("fields %+v", asked)
	}
}

func TestWifiAgain(t *testing.T) {
	// asked anew: the kept one isn't offered, the card says why
	f := newNetFake(map[string]string{"u1/802-11-wireless-security/psk": "wrong"}, answerWith(`{"psk":"right"}`))
	c, err := f.n.GetSecrets(wifi(agentOwned), connPath, "802-11-wireless-security", nil, allowInteraction|requestNew)
	if err != nil || secretOf(t, c, "802-11-wireless-security", "psk") != "right" {
		t.Fatalf("again: %v %v", c, err)
	}
	if r := askOf(<-f.calls); !strings.Contains(r.Message, "didn't work") || r.Fields[0].Saved {
		t.Fatalf("asked %+v", r)
	}
}

func TestNo(t *testing.T) {
	f := newNetFake(map[string]string{}, answerWith("no"))
	if _, err := f.n.GetSecrets(wifi(0), connPath, "802-11-wireless-security", nil, allowInteraction); err != userCanceled {
		t.Fatalf("no: %v", err)
	}
}

func TestCancelGetSecrets(t *testing.T) {
	f := newNetFake(map[string]string{}, nil)
	done := make(chan *dbus.Error)
	go func() {
		_, err := f.n.GetSecrets(wifi(0), connPath, "802-11-wireless-security", nil, allowInteraction)
		done <- err
	}()
	<-f.calls // asked
	f.n.CancelGetSecrets(connPath, "802-11-wireless-security")
	if err := <-done; err != agentCanceled {
		t.Fatalf("canceled: %v", err)
	}
	if call := <-f.calls; call[0] != "cancel" || call[1] != "1" {
		t.Fatalf("closed %v", call)
	}
}

func TestNetNobodyAnswers(t *testing.T) {
	askWithin = 50 * time.Millisecond
	defer func() { askWithin = 115 * time.Second }()
	f := newNetFake(map[string]string{}, nil)
	if _, err := f.n.GetSecrets(wifi(0), connPath, "802-11-wireless-security", nil, allowInteraction); err != userCanceled {
		t.Fatalf("timed out: %v", err)
	}
	<-f.calls
	if call := <-f.calls; call[0] != "cancel" {
		t.Fatalf("closed %v", call)
	}
}

func TestSaveAndDelete(t *testing.T) {
	keys := &fakeKeys{kept: map[string]string{}}
	n := newNetAgent(func(string, ...string) error { return nil }, keys)
	c := wifi(agentOwned)
	c["802-11-wireless-security"]["psk"] = dbus.MakeVariant("typed")
	c["vpn"] = map[string]dbus.Variant{
		"data":    dbus.MakeVariant(map[string]string{"password-flags": "1", "challenge-response-flags": "2"}),
		"secrets": dbus.MakeVariant(map[string]string{"password": "vpnpass", "challenge-response": "123456"}),
	}
	n.SaveSecrets(c, connPath)
	want := map[string]string{"u1/802-11-wireless-security/psk": "typed", "u1/vpn/password": "vpnpass"}
	if len(keys.kept) != len(want) {
		t.Fatalf("kept %v", keys.kept)
	}
	for k, v := range want {
		if keys.kept[k] != v {
			t.Fatalf("kept %v", keys.kept)
		}
	}
	// a system-owned secret is NetworkManager's
	n.SaveSecrets(func() connection {
		c := wifi(0)
		c["802-11-wireless-security"]["psk"] = dbus.MakeVariant("x")
		return c
	}(), connPath)
	if keys.kept["u1/802-11-wireless-security/psk"] != "typed" {
		t.Fatal("kept a system-owned secret")
	}
	n.DeleteSecrets(wifi(0), connPath)
	if len(keys.kept) != 0 {
		t.Fatalf("still kept %v", keys.kept)
	}
}

func TestSecretKeys(t *testing.T) {
	wep := connection{"802-11-wireless-security": {"key-mgmt": dbus.MakeVariant("none"), "wep-tx-keyidx": dbus.MakeVariant(uint32(2))}}
	tls := connection{"802-1x": {"eap": dbus.MakeVariant([]string{"tls"})}}
	peap := connection{"802-1x": {"eap": dbus.MakeVariant([]string{"peap"})}}
	for _, tc := range []struct {
		c       connection
		setting string
		hints   []string
		want    string
	}{
		{wifi(0), "802-11-wireless-security", nil, "psk"},
		{wep, "802-11-wireless-security", nil, "wep-key2"},
		{tls, "802-1x", nil, "private-key-password"},
		{peap, "802-1x", nil, "password"},
		{connection{}, "gsm", []string{"x-vpn-message:hi", "password"}, "password"},
	} {
		if got := strings.Join(secretKeys(tc.c, tc.setting, tc.hints), ","); got != tc.want {
			t.Errorf("%s: %q, want %q", tc.setting, got, tc.want)
		}
	}
	wep["802-11-wireless-security"]["wep-key-flags"] = dbus.MakeVariant(uint32(agentOwned))
	if wep.flags("802-11-wireless-security", "wep-key2") != agentOwned {
		t.Error("WEP keys' flags")
	}
}

// a VPN plugin whose dialog is faked: its .name file, and what the dialog
// prints for the arguments it gets
func vpnAgent(t *testing.T, reply func([]field) *string, dialog func(args []string, stdin string) string) (*netAgent, *fakeNetShell, *[]string) {
	t.Helper()
	dir := t.TempDir()
	name := "[VPN Connection]\nservice=org.freedesktop.NetworkManager.openvpn\n\n[GNOME]\nauth-dialog=/usr/lib/nm-openvpn-auth-dialog\nsupports-external-ui-mode=true\nsupports-hints=true\n"
	if err := os.WriteFile(filepath.Join(dir, "openvpn.name"), []byte(name), 0o644); err != nil {
		t.Fatal(err)
	}
	f := newNetFake(map[string]string{}, reply)
	f.n.plugins = []string{dir}
	var ran []string
	f.n.run = func(path string, args []string, stdin string) (string, error) {
		if path != "/usr/lib/nm-openvpn-auth-dialog" {
			return "", errors.New("wrong dialog")
		}
		ran = append(args, stdin)
		return dialog(args, stdin), nil
	}
	return f.n, f, &ran
}

func vpnConn() connection {
	return connection{
		"connection": {"id": dbus.MakeVariant("Agora"), "uuid": dbus.MakeVariant("u2")},
		"vpn": {
			"service-type": dbus.MakeVariant("org.freedesktop.NetworkManager.openvpn"),
			"data":         dbus.MakeVariant(map[string]string{"connection-type": "password-tls", "password-flags": "1"}),
		},
	}
}

const ui = "[VPN Plugin UI]\nVersion=2\nDescription=You need to authenticate\nTitle=Authentication required\n\n"

func TestVPNKeptPassword(t *testing.T) {
	// the first request: the dialog found the kept password, nothing to ask
	n, f, ran := vpnAgent(t, nil, func([]string, string) string {
		return ui + "[password]\nValue=kept\\spass\nLabel=Password\nIsSecret=true\nShouldAsk=true\n"
	})
	c, err := n.GetSecrets(vpnConn(), connPath, "vpn", nil, allowInteraction)
	if err != nil {
		t.Fatal(err)
	}
	if s, _ := c["vpn"]["secrets"].Value().(map[string]string); s["password"] != "kept pass" {
		t.Fatalf("secrets %v", c)
	}
	if len(f.calls) != 0 {
		t.Fatal("asked anyway")
	}
	args := strings.Join(*ran, " ")
	if !strings.Contains(args, "-u u2 -n Agora -s org.freedesktop.NetworkManager.openvpn --external-ui-mode -i") ||
		!strings.Contains(args, "DATA_KEY=connection-type\nDATA_VAL=password-tls\n\n") || !strings.HasSuffix(args, "DONE\n\n") {
		t.Fatalf("ran %q", args)
	}
}

func TestVPNChallenge(t *testing.T) {
	// the server's challenge: a hint, its message on the card
	var asked []field
	n, f, ran := vpnAgent(t, func(fields []field) *string {
		asked = fields
		js := `{"x-dynamic-challenge-echo:challenge-response":"123456"}`
		return &js
	}, func([]string, string) string {
		return ui + "[password]\nValue=kept\nLabel=Password\nIsSecret=true\nShouldAsk=false\n\n" +
			"[x-dynamic-challenge-echo:challenge-response]\nValue=\nLabel=Challenge response\nIsSecret=true\nShouldAsk=true\nForceEcho=true\n"
	})
	hints := []string{"x-dynamic-challenge-echo:challenge-response", "x-vpn-message:Enter your OTP"}
	c, err := n.GetSecrets(vpnConn(), connPath, "vpn", hints, allowInteraction)
	if err != nil {
		t.Fatal(err)
	}
	s, _ := c["vpn"]["secrets"].Value().(map[string]string)
	if s["password"] != "kept" || s["x-dynamic-challenge-echo:challenge-response"] != "123456" {
		t.Fatalf("secrets %v", s)
	}
	if r := askOf(<-f.calls); r.Setting != "vpn" || r.Name != "Agora" || r.Message != "Enter your OTP" {
		t.Fatalf("asked %+v", r)
	}
	if len(asked) != 1 || asked[0] != (field{"x-dynamic-challenge-echo:challenge-response", "Challenge response", false, false}) {
		t.Fatalf("fields %+v", asked)
	}
	if !strings.Contains(strings.Join(*ran, " "), "-t x-dynamic-challenge-echo:challenge-response -t x-vpn-message:Enter your OTP") {
		t.Fatalf("hints not passed: %q", *ran)
	}
}

func TestVPNAgain(t *testing.T) {
	// asked anew: the kept password is offered (an empty field keeps it)
	var asked []field
	n, _, _ := vpnAgent(t, func(fields []field) *string {
		asked = fields
		js := `{"password":""}`
		return &js
	}, func(args []string, _ string) string {
		return ui + "[password]\nValue=kept\nLabel=Password\nIsSecret=true\nShouldAsk=true\n"
	})
	c, err := n.GetSecrets(vpnConn(), connPath, "vpn", nil, allowInteraction|requestNew)
	if err != nil {
		t.Fatal(err)
	}
	if s, _ := c["vpn"]["secrets"].Value().(map[string]string); s["password"] != "kept" {
		t.Fatalf("secrets %v", s)
	}
	if len(asked) != 1 || !asked[0].Saved {
		t.Fatalf("fields %+v", asked)
	}
}

func TestVPNNoPlugin(t *testing.T) {
	n, _, _ := vpnAgent(t, nil, func([]string, string) string { return "" })
	c := vpnConn()
	c["vpn"]["service-type"] = dbus.MakeVariant("org.freedesktop.NetworkManager.openconnect")
	if _, err := n.GetSecrets(c, connPath, "vpn", nil, allowInteraction); err != noSecrets {
		t.Fatalf("no plugin: %v", err)
	}
}

func TestKeyfile(t *testing.T) {
	k := parseKeyfile("# c\n[A]\nx = 1\nLabel[fr]=Mot\nLabel=Word\n[B]\nv=\\sa\\nb\\\\\n")
	if k.get("A", "x") != "1" || k.get("A", "Label") != "Word" || k.get("B", "v") != " a\nb\\" || len(k) != 2 {
		t.Fatalf("%+v", k)
	}
}
