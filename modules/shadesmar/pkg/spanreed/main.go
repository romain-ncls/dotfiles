// spanreed: shadesmar's helper for what QML can't do (docs/hyprland.md),
// owning D-Bus names. For now Plasma's OSD service, which backdrop and
// spotify-vol call (org.kde.plasmashell, /org/kde/osdService), passed on to
// the shell's OSD with qs ipc call. Hyprland's session only: in Plasma,
// plasmashell owns the name.
package main

import (
	"log"
	"os"
	"os/exec"
	"strconv"

	"github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5/introspect"
)

const (
	busName = "org.kde.plasmashell"
	osdPath = "/org/kde/osdService"
	osdName = "org.kde.osdService"
)

// osd serves the methods of Plasma's OSD service that our tools call.
type osd struct{}

// ShowText: a message with an icon (backdrop: a wallpaper liked…).
func (osd) ShowText(icon, text string) *dbus.Error {
	go shell("text", icon, text)
	return nil
}

// MediaPlayerVolumeChanged: a player's volume (spotify-vol).
func (osd) MediaPlayerVolumeChanged(percent int32, player, icon string) *dbus.Error {
	go shell("player", strconv.Itoa(int(percent)), player, icon)
	return nil
}

// shell calls the OSD's function fn in shadesmar (Osd.qml), off the
// caller's call: the callers wait for a reply.
func shell(fn string, args ...string) {
	cmd := exec.Command("qs", append([]string{"-c", "shadesmar", "ipc", "call", "osd", fn}, args...)...)
	if out, err := cmd.CombinedOutput(); err != nil {
		log.Printf("osd %s: %v: %s", fn, err, out)
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
	select {}
}
