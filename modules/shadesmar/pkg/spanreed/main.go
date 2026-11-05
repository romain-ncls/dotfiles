// spanreed: shadesmar's helper for what QML can't do (docs/hyprland.md),
// owning D-Bus names. Plasma's OSD service, which backdrop and spotify-vol
// call (org.kde.plasmashell, /org/kde/osdService), passed on to the shell's
// OSD with qs ipc call; and the Bluetooth pairing agent (bluetooth.go).
// Hyprland's session only: in Plasma, plasmashell owns the name and
// bluedevil is the agent.
package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"strconv"
	"strings"

	"github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5/introspect"
)

const (
	busName = "org.kde.plasmashell"
	osdPath = "/org/kde/osdService"
	osdName = "org.kde.osdService"
)

// dev: in a dev rig (modules/hyprland/dev), which shares the machine's
// system bus.
func dev() bool {
	return os.Getenv("HYPR_DEV") != ""
}

// shell calls function fn of the shell's IPC target (qs ipc call):
// shadesmar's, or in a dev rig the shell at $SPANREED_SHELL, by path, as
// the rig's shell and the session's are the same config.
func shell(target, fn string, args ...string) error {
	which := []string{"-c", "shadesmar"}
	if p := os.Getenv("SPANREED_SHELL"); p != "" && dev() {
		which = []string{"-p", p}
	}
	cmd := exec.Command("qs", append(append(which, "ipc", "call", target, fn), args...)...)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("%v: %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}

// osd serves the methods of Plasma's OSD service that our tools call.
type osd struct{}

// ShowText: a message with an icon (backdrop: a wallpaper liked…).
func (osd) ShowText(icon, text string) *dbus.Error {
	go show("text", icon, text)
	return nil
}

// MediaPlayerVolumeChanged: a player's volume (spotify-vol).
func (osd) MediaPlayerVolumeChanged(percent int32, player, icon string) *dbus.Error {
	go show("player", strconv.Itoa(int(percent)), player, icon)
	return nil
}

// show calls the OSD's function fn in shadesmar (Osd.qml), off the
// caller's call: the callers wait for a reply.
func show(fn string, args ...string) {
	if err := shell("osd", fn, args...); err != nil {
		log.Printf("osd %s: %v", fn, err)
	}
}

const introspection = `
<node>
	<interface name="` + osdName + `">
		<method name="showText">
			<arg name="icon" type="s" direction="in"/>
			<arg name="text" type="s" direction="in"/>
		</method>
		<method name="mediaPlayerVolumeChanged">
			<arg name="percent" type="i" direction="in"/>
			<arg name="playerName" type="s" direction="in"/>
			<arg name="playerIcon" type="s" direction="in"/>
		</method>
	</interface>` + introspect.IntrospectDataString + `
</node>`

func main() {
	log.SetFlags(0)
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		log.Fatal(err)
	}
	methods := map[string]string{"ShowText": "showText", "MediaPlayerVolumeChanged": "mediaPlayerVolumeChanged"}
	if err := conn.ExportWithMap(osd{}, methods, osdPath, osdName); err != nil {
		log.Fatal(err)
	}
	if err := conn.Export(introspect.Introspectable(introspection), osdPath, "org.freedesktop.DBus.Introspectable"); err != nil {
		log.Fatal(err)
	}
	reply, err := conn.RequestName(busName, dbus.NameFlagDoNotQueue)
	if err != nil {
		log.Fatal(err)
	}
	if reply != dbus.RequestNameReplyPrimaryOwner {
		log.Printf("%s is taken (Plasma's session?)", busName)
		os.Exit(1)
	}
	bluetooth := func(fn string, args ...string) error { return shell("bluetooth", fn, args...) }
	if err := serveAgent(conn, bluetooth); err != nil {
		log.Printf("bluetooth: no pairing agent: %v", err)
	}
	select {}
}
