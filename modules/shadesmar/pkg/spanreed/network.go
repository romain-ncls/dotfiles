// The network's secret agent (org.freedesktop.NetworkManager.SecretAgent;
// docs/hyprland.md): NetworkManager asks it for the secrets it doesn't keep,
// those left to the agent (a Wi-Fi password, a VPN's) or never kept (a
// VPN's one-time code). Kept ones come from the Secret Service (keyring.go,
// nm-applet's items); the others are asked in the shell's card (Network.qml:
// qs ipc call network ask), which answers through `spanreed answer`, its
// secrets on stdin rather than in a command line any process can read. A
// VPN's secrets are its plugin's to know: its auth dialog, in external UI
// mode as GNOME Shell runs it, lists them. In Plasma, plasma-nm is the agent.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/godbus/dbus/v5"
)

const (
	nmName           = "org.freedesktop.NetworkManager"
	nmAgentManager   = dbus.ObjectPath("/org/freedesktop/NetworkManager/AgentManager")
	secretAgentPath  = dbus.ObjectPath("/org/freedesktop/NetworkManager/SecretAgent")
	secretAgentIface = "org.freedesktop.NetworkManager.SecretAgent"
	networkPath      = dbus.ObjectPath("/org/shadesmar/Network")
	networkIface     = "org.shadesmar.Network"
)

// GetSecrets' flags
const (
	allowInteraction = 0x1
	requestNew       = 0x2
)

// a secret's flags
const (
	agentOwned  = 0x1
	notSaved    = 0x2
	notRequired = 0x4
)

// NetworkManager waits two minutes for an agent (nm-secret-agent.c), then
// cancels; the card goes a little before.
var askWithin = 115 * time.Second

var (
	userCanceled  = dbus.NewError(secretAgentIface+".UserCanceled", []any{"canceled"})
	agentCanceled = dbus.NewError(secretAgentIface+".AgentCanceled", []any{"canceled"})
	noSecrets     = dbus.NewError(secretAgentIface+".NoSecrets", []any{"no secrets"})
)

// connection: NetworkManager's, by setting and key
type connection map[string]map[string]dbus.Variant

func (c connection) str(setting, key string) string {
	s, _ := c[setting][key].Value().(string)
	return s
}

func (c connection) dict(setting, key string) map[string]string {
	d, _ := c[setting][key].Value().(map[string]string)
	return d
}

// a secret's flags: key-flags (wep-key-flags for the four WEP keys); a VPN's
// are in its data, as strings
func (c connection) flags(setting, key string) uint32 {
	if setting == "vpn" {
		f, _ := strconv.ParseUint(c.dict("vpn", "data")[key+"-flags"], 10, 32)
		return uint32(f)
	}
	if strings.HasPrefix(key, "wep-key") {
		key = "wep-key"
	}
	f, _ := c[setting][key+"-flags"].Value().(uint32)
	return f
}

// field: a field of the card. Saved: a secret is kept, which an empty
// field keeps (the secret itself doesn't go to the shell).
type field struct {
	Key    string `json:"key"`
	Label  string `json:"label"`
	Secret bool   `json:"secret"`
	Saved  bool   `json:"saved"`
}

type keyring interface {
	lookup(uuid, setting, key string) (string, error)
	store(uuid, setting, key, label, value string) error
	forget(uuid string) error
}

type request struct {
	path    dbus.ObjectPath
	setting string
	answer  chan map[string]string // nil: no
}

type netAgent struct {
	mu      sync.Mutex
	next    uint32
	pending map[uint32]*request
	// the shell's network target: fn and its arguments
	shell func(fn string, args ...string) error
	keys  keyring
	// where the VPN plugins are described, and how their dialogs run
	plugins []string
	run     func(path string, args []string, stdin string) (string, error)
}

func newNetAgent(shell func(fn string, args ...string) error, keys keyring) *netAgent {
	return &netAgent{
		pending: map[uint32]*request{},
		shell:   shell,
		keys:    keys,
		plugins: []string{"/usr/lib/NetworkManager/VPN", "/etc/NetworkManager/VPN"},
		run:     runDialog,
	}
}

func (n *netAgent) GetSecrets(c connection, path dbus.ObjectPath, setting string, hints []string, flags uint32) (connection, *dbus.Error) {
	if setting == "vpn" {
		values, err := n.vpn(c, path, hints, flags)
		if err != nil {
			return nil, err
		}
		return connection{"vpn": {"secrets": dbus.MakeVariant(values)}}, nil
	}
	values, err := n.secrets(c, path, setting, hints, flags)
	if err != nil {
		return nil, err
	}
	out := map[string]dbus.Variant{}
	for k, v := range values {
		out[k] = dbus.MakeVariant(v)
	}
	return connection{setting: out}, nil
}

// secretKeys: the secrets a setting asks for, by its kind; a setting we
// don't know, its hints.
func secretKeys(c connection, setting string, hints []string) []string {
	switch setting {
	case "802-11-wireless-security":
		switch c.str(setting, "key-mgmt") {
		case "wpa-psk", "sae":
			return []string{"psk"}
		case "none":
			idx, _ := c[setting]["wep-tx-keyidx"].Value().(uint32)
			return []string{fmt.Sprintf("wep-key%d", idx)}
		case "ieee8021x":
			if c.str(setting, "auth-alg") == "leap" {
				return []string{"leap-password"}
			}
		}
		return nil
	case "802-1x":
		eap, _ := c[setting]["eap"].Value().([]string)
		if len(eap) > 0 && !slices.ContainsFunc(eap, func(m string) bool { return m != "tls" }) {
			return []string{"private-key-password"}
		}
		return []string{"password"}
	}
	var keys []string
	for _, h := range hints {
		if !strings.HasPrefix(h, "x-") {
			keys = append(keys, h)
		}
	}
	return keys
}

func label(key string) string {
	switch {
	case strings.HasPrefix(key, "wep-key"):
		return "Key"
	case key == "private-key-password":
		return "The key's password"
	}
	return "Password"
}

// secrets: a setting's, kept ones first, then asked.
func (n *netAgent) secrets(c connection, path dbus.ObjectPath, setting string, hints []string, flags uint32) (map[string]string, *dbus.Error) {
	uuid, name := c.str("connection", "uuid"), c.str("connection", "id")
	keys := secretKeys(c, setting, hints)
	if len(keys) == 0 {
		log.Printf("network %s: no secrets known for %s", name, setting)
		return nil, noSecrets
	}
	values := map[string]string{}
	var fields []field
	missing := false
	for _, key := range keys {
		f := c.flags(setting, key)
		if f&notRequired != 0 {
			continue
		}
		value := ""
		// asked anew: the kept one failed
		if f&agentOwned != 0 && f&notSaved == 0 && flags&requestNew == 0 {
			v, err := n.keys.lookup(uuid, setting, key)
			if err != nil {
				log.Printf("network %s: %v", name, err)
			}
			value = v
		}
		if value != "" {
			values[key] = value
		} else {
			missing = true
		}
		fields = append(fields, field{key, label(key), true, value != ""})
	}
	if !missing {
		return values, nil
	}
	if flags&allowInteraction == 0 {
		return nil, noSecrets
	}
	message := "Asks for its password"
	if flags&requestNew != 0 {
		message = "Its password didn't work: type it again"
	}
	return n.ask(path, setting, name, message, fields, values)
}

type plugin struct {
	dialog string
	hints  bool
}

// authDialog: the VPN service's auth dialog, from the plugins' .name files
func (n *netAgent) authDialog(service string) (plugin, error) {
	for _, dir := range n.plugins {
		files, _ := filepath.Glob(filepath.Join(dir, "*.name"))
		for _, f := range files {
			data, err := os.ReadFile(f)
			if err != nil {
				continue
			}
			k := parseKeyfile(string(data))
			if k.get("VPN Connection", "service") != service {
				continue
			}
			if k.get("GNOME", "auth-dialog") == "" || k.get("GNOME", "supports-external-ui-mode") != "true" {
				return plugin{}, fmt.Errorf("%s has no auth dialog for us (external UI mode)", filepath.Base(f))
			}
			return plugin{k.get("GNOME", "auth-dialog"), k.get("GNOME", "supports-hints") == "true"}, nil
		}
	}
	return plugin{}, fmt.Errorf("no plugin for %s", service)
}

// vpn: a VPN's secrets, as its auth dialog lists them (its fields: Value,
// Label, IsSecret, ShouldAsk, ForceEcho). It finds the kept ones itself
// (nm-applet's items); the card asks for those it should and has no value
// for (a one-time code), or all of them when asked anew.
func (n *netAgent) vpn(c connection, path dbus.ObjectPath, hints []string, flags uint32) (map[string]string, *dbus.Error) {
	uuid, name := c.str("connection", "uuid"), c.str("connection", "id")
	service := c.str("vpn", "service-type")
	p, err := n.authDialog(service)
	if err != nil {
		log.Printf("network %s: %v", name, err)
		return nil, noSecrets
	}
	args := []string{"-u", uuid, "-n", name, "-s", service, "--external-ui-mode"}
	if flags&allowInteraction != 0 {
		args = append(args, "-i")
	}
	if flags&requestNew != 0 {
		args = append(args, "-r")
	}
	message := "Asks for its password"
	for _, h := range hints {
		if p.hints {
			args = append(args, "-t", h)
		}
		if m, ok := strings.CutPrefix(h, "x-vpn-message:"); ok {
			message = m
		}
	}
	var in strings.Builder
	for _, part := range []struct{ tag, setting string }{{"DATA", "data"}, {"SECRET", "secrets"}} {
		d := c.dict("vpn", part.setting)
		for _, k := range slices.Sorted(maps.Keys(d)) {
			fmt.Fprintf(&in, "%s_KEY=%s\n%s_VAL=%s\n\n", part.tag, k, part.tag, d[k])
		}
	}
	in.WriteString("DONE\n\n")
	out, err := n.run(p.dialog, args, in.String())
	if err != nil {
		log.Printf("network %s: %s: %v", name, filepath.Base(p.dialog), err)
		return nil, noSecrets
	}
	values := map[string]string{}
	var fields []field
	missing := false
	for _, g := range parseKeyfile(out) {
		if g.name == "VPN Plugin UI" {
			continue
		}
		value := g.keys["Value"]
		if value != "" {
			values[g.name] = value
		}
		if g.bool("ShouldAsk") {
			fields = append(fields, field{g.name, g.keys["Label"], g.bool("IsSecret") && !g.bool("ForceEcho"), value != ""})
			missing = missing || value == ""
		}
	}
	if len(fields) == 0 || !missing && flags&requestNew == 0 {
		return values, nil
	}
	if flags&requestNew != 0 && message == "Asks for its password" {
		message = "It didn't connect: try again"
	}
	return n.ask(path, "vpn", name, message, fields, values)
}

// runDialog runs an auth dialog, in English as the shell is.
func runDialog(path string, args []string, stdin string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, path, args...)
	cmd.Env = append(os.Environ(), "LC_ALL=C.UTF-8", "LANGUAGE=")
	cmd.Stdin = strings.NewReader(stdin)
	var out, errs bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &errs
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("%v: %s", err, strings.TrimSpace(errs.String()))
	}
	return out.String(), nil
}

// ask asks the shell for the fields and waits: values completed with the
// fields typed (an empty one keeps its kept value). A new request replaces
// the card (the shell says no to the one before).
func (n *netAgent) ask(path dbus.ObjectPath, setting, name, message string, fields []field, values map[string]string) (map[string]string, *dbus.Error) {
	n.mu.Lock()
	n.next++
	id := n.next
	r := &request{path, setting, make(chan map[string]string, 1)}
	n.pending[id] = r
	n.mu.Unlock()
	defer func() {
		n.mu.Lock()
		delete(n.pending, id)
		n.mu.Unlock()
	}()
	// one JSON object: qs ipc call splits an argument in brackets ([a,b])
	js, _ := json.Marshal(map[string]any{"setting": setting, "name": name, "message": message, "fields": fields})
	if err := n.shell("ask", fmt.Sprint(id), string(js)); err != nil {
		log.Printf("network %s: %v", name, err)
		return nil, noSecrets
	}
	select {
	case typed, open := <-r.answer:
		if !open {
			return nil, agentCanceled
		}
		if typed == nil {
			return nil, userCanceled
		}
		for _, f := range fields {
			if v := typed[f.Key]; v != "" {
				values[f.Key] = v
			}
		}
		return values, nil
	case <-time.After(askWithin):
		go n.shell("cancel", fmt.Sprint(id))
		return nil, userCanceled
	}
}

// answered: the shell's answer to request id (nil values: no)
func (n *netAgent) answered(id uint32, values map[string]string) {
	n.mu.Lock()
	defer n.mu.Unlock()
	if r, found := n.pending[id]; found {
		r.answer <- values
		delete(n.pending, id)
	}
}

// CancelGetSecrets: NetworkManager gave up on a request (the connection
// stopped, or two minutes went by): its card goes.
func (n *netAgent) CancelGetSecrets(path dbus.ObjectPath, setting string) *dbus.Error {
	n.mu.Lock()
	defer n.mu.Unlock()
	for id, r := range n.pending {
		if r.path == path && r.setting == setting {
			close(r.answer)
			delete(n.pending, id)
			go n.shell("cancel", fmt.Sprint(id))
		}
	}
	return nil
}

// SaveSecrets: a connection's secrets left to the agent, kept (after a
// connection with secrets typed, or an edit).
func (n *netAgent) SaveSecrets(c connection, path dbus.ObjectPath) *dbus.Error {
	uuid, name := c.str("connection", "uuid"), c.str("connection", "id")
	save := func(setting, key, value string) {
		f := c.flags(setting, key)
		if value == "" || f&agentOwned == 0 || f&notSaved != 0 {
			return
		}
		label := fmt.Sprintf("Network secret for %s/%s/%s", name, setting, key)
		if err := n.keys.store(uuid, setting, key, label, value); err != nil {
			log.Printf("network %s: not kept: %v", name, err)
		}
	}
	for setting, props := range c {
		if setting == "vpn" {
			for key, value := range c.dict("vpn", "secrets") {
				save(setting, key, value)
			}
			continue
		}
		for key, v := range props {
			value, ok := v.Value().(string)
			if ok && !strings.HasSuffix(key, "-flags") {
				save(setting, key, value)
			}
		}
	}
	return nil
}

// DeleteSecrets: a connection gone, its secrets with it.
func (n *netAgent) DeleteSecrets(c connection, path dbus.ObjectPath) *dbus.Error {
	if err := n.keys.forget(c.str("connection", "uuid")); err != nil {
		log.Printf("network %s: %v", c.str("connection", "id"), err)
	}
	return nil
}

// netAnswers serves the shell's answers (spanreed answer): its id, yes or
// no, and the fields typed.
type netAnswers struct{ n *netAgent }

func (s netAnswers) Answer(js string) *dbus.Error {
	var a struct {
		ID     uint32            `json:"id"`
		OK     bool              `json:"ok"`
		Values map[string]string `json:"values"`
	}
	if err := json.Unmarshal([]byte(js), &a); err != nil {
		return dbus.MakeFailedError(err)
	}
	if a.OK && a.Values == nil {
		a.Values = map[string]string{}
	}
	if !a.OK {
		a.Values = nil
	}
	s.n.answered(a.ID, a.Values)
	return nil
}

// serveNetwork registers the agent with NetworkManager, now and each time
// it starts again. The dev rigs (HYPR_DEV) share the machine's
// NetworkManager: the agent is on the rig's session bus instead, for tests
// to call.
func serveNetwork(session *dbus.Conn, shell func(fn string, args ...string) error) error {
	n := newNetAgent(shell, secretService{session})
	if err := session.Export(netAnswers{n}, networkPath, networkIface); err != nil {
		return err
	}
	if dev() {
		return session.Export(n, secretAgentPath, secretAgentIface)
	}
	system, err := dbus.ConnectSystemBus()
	if err != nil {
		return err
	}
	if err := system.Export(n, secretAgentPath, secretAgentIface); err != nil {
		return err
	}
	if err := system.AddMatchSignal(dbus.WithMatchSender("org.freedesktop.DBus"), dbus.WithMatchMember("NameOwnerChanged"), dbus.WithMatchArg(0, nmName)); err != nil {
		return err
	}
	signals := make(chan *dbus.Signal, 8)
	system.Signal(signals)
	go func() {
		for s := range signals {
			if s.Name == "org.freedesktop.DBus.NameOwnerChanged" && len(s.Body) == 3 {
				if owner, _ := s.Body[2].(string); owner != "" {
					registerNetwork(system)
				}
			}
		}
	}()
	registerNetwork(system)
	return nil
}

// registerNetwork: with VPN hints (a VPN's one-time code comes as a hint).
func registerNetwork(system *dbus.Conn) {
	manager := system.Object(nmName, nmAgentManager)
	if err := manager.Call(nmName+".AgentManager.RegisterWithCapabilities", dbus.FlagNoAutoStart, "org.shadesmar.spanreed", uint32(1)).Err; err != nil {
		log.Printf("network: no secret agent: %v", err)
		return
	}
	log.Print("network: the secret agent is registered")
}
