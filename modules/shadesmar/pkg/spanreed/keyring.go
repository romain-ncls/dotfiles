package main

import (
	"errors"

	"github.com/godbus/dbus/v5"
)

// The Secret Service (org.freedesktop.secrets: KWallet's ksecretd, unlocked
// at login), where the network agent keeps the secrets NetworkManager
// leaves to it. In nm-applet's items (libnma's schema): the ones it kept
// are found, and the VPNs' auth dialogs look there too.
type secretService struct{ bus *dbus.Conn }

const (
	secretsName = "org.freedesktop.secrets"
	secretsPath = dbus.ObjectPath("/org/freedesktop/secrets")
	service     = "org.freedesktop.Secret.Service."
	nmSchema    = "org.freedesktop.NetworkManager.Connection"
)

type secret struct {
	Session     dbus.ObjectPath
	Parameters  []byte
	Value       []byte
	ContentType string
}

func (s secretService) call(method string, args ...any) *dbus.Call {
	return s.bus.Object(secretsName, secretsPath).Call(service+method, 0, args...)
}

// nm-applet's attributes: a connection's secret, or all of its secrets
func attributes(uuid, setting, key string) map[string]string {
	a := map[string]string{"xdg:schema": nmSchema, "connection-uuid": uuid}
	if setting != "" {
		a["setting-name"], a["setting-key"] = setting, key
	}
	return a
}

// items: those unlocked, or that unlock without asking (the wallet's
// password isn't asked here: PAM opens it at login).
func (s secretService) items(attrs map[string]string) ([]dbus.ObjectPath, error) {
	var unlocked, locked []dbus.ObjectPath
	if err := s.call("SearchItems", attrs).Store(&unlocked, &locked); err != nil {
		return nil, err
	}
	if len(locked) > 0 {
		var opened []dbus.ObjectPath
		var prompt dbus.ObjectPath
		if s.call("Unlock", locked).Store(&opened, &prompt) == nil {
			unlocked = append(unlocked, opened...)
		}
	}
	return unlocked, nil
}

// a plain session: the secrets stay on the session bus
func (s secretService) session() (dbus.ObjectPath, func(), error) {
	var out dbus.Variant
	var path dbus.ObjectPath
	if err := s.call("OpenSession", "plain", dbus.MakeVariant("")).Store(&out, &path); err != nil {
		return "", nil, err
	}
	return path, func() { s.bus.Object(secretsName, path).Call("org.freedesktop.Secret.Session.Close", 0) }, nil
}

func (s secretService) lookup(uuid, setting, key string) (string, error) {
	items, err := s.items(attributes(uuid, setting, key))
	if err != nil || len(items) == 0 {
		return "", err
	}
	session, done, err := s.session()
	if err != nil {
		return "", err
	}
	defer done()
	var secrets map[dbus.ObjectPath]secret
	if err := s.call("GetSecrets", items[:1], session).Store(&secrets); err != nil {
		return "", err
	}
	for _, sec := range secrets {
		return string(sec.Value), nil
	}
	return "", nil
}

func (s secretService) store(uuid, setting, key, label, value string) error {
	var collection dbus.ObjectPath
	if err := s.call("ReadAlias", "default").Store(&collection); err != nil {
		return err
	}
	if collection == "/" {
		return errors.New("no default collection")
	}
	session, done, err := s.session()
	if err != nil {
		return err
	}
	defer done()
	props := map[string]dbus.Variant{
		"org.freedesktop.Secret.Item.Label":      dbus.MakeVariant(label),
		"org.freedesktop.Secret.Item.Attributes": dbus.MakeVariant(attributes(uuid, setting, key)),
	}
	var item, prompt dbus.ObjectPath
	err = s.bus.Object(secretsName, collection).Call("org.freedesktop.Secret.Collection.CreateItem", 0,
		props, secret{session, []byte{}, []byte(value), "text/plain"}, true).Store(&item, &prompt)
	if err == nil && prompt != "/" {
		err = errors.New("the wallet is locked")
	}
	return err
}

func (s secretService) forget(uuid string) error {
	items, err := s.items(attributes(uuid, "", ""))
	for _, item := range items {
		var prompt dbus.ObjectPath
		if e := s.bus.Object(secretsName, item).Call("org.freedesktop.Secret.Item.Delete", 0).Store(&prompt); e != nil {
			err = e
		}
	}
	return err
}
