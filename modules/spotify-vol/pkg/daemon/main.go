// spotify-vol controls Spotify's volume over its MPRIS DBus interface.
//
// Driving MPRIS Volume (rather than the PipeWire stream node) sets Spotify's
// *own* internal volume, so the in-app slider, the audio stream and KDE all
// stay in sync. It also survives Spotify recycling its stream node on pause.
//
// Usage:
//
//	spotify-vol up|down        adjust by ±5%
//	spotify-vol set <0-100>    set absolute percentage
//	spotify-vol get            print current percentage
//	spotify-vol daemon         Super+Shift+Scroll listener (see input.go)
package main

import (
	"fmt"
	"os"
	"strconv"

	"github.com/godbus/dbus/v5"
)

const (
	mprisService = "org.mpris.MediaPlayer2.spotify"
	mprisPath    = "/org/mpris/MediaPlayer2"
	mprisVolume  = "org.mpris.MediaPlayer2.Player.Volume"

	osdService = "org.kde.plasmashell"
	osdPath    = "/org/kde/osdService"
	osdMethod  = "org.kde.osdService.mediaPlayerVolumeChanged"

	step = 0.05
)

func usage() {
	fmt.Fprintln(os.Stderr, "usage: spotify-vol {up|down|set <0-100>|get|daemon}")
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	if os.Args[1] == "daemon" {
		runDaemon()
		return
	}

	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		fmt.Fprintln(os.Stderr, "spotify-vol:", err)
		os.Exit(1)
	}
	defer conn.Close()

	cur, ok := getVolume(conn)
	if !ok {
		return // Spotify not running / no MPRIS endpoint -> nothing to do.
	}

	switch os.Args[1] {
	case "up":
		applyVolume(conn, cur+step)
	case "down":
		applyVolume(conn, cur-step)
	case "set":
		if len(os.Args) < 3 {
			usage()
			os.Exit(1)
		}
		p, err := strconv.ParseFloat(os.Args[2], 64)
		if err != nil {
			usage()
			os.Exit(1)
		}
		applyVolume(conn, p/100)
	case "get":
		fmt.Println(percent(cur))
	default:
		usage()
		os.Exit(1)
	}
}

func percent(v float64) int { return int(v*100 + 0.5) }

// getVolume returns Spotify's MPRIS volume in [0,1]; ok is false when Spotify
// is not reachable on the bus.
func getVolume(conn *dbus.Conn) (vol float64, ok bool) {
	v, err := conn.Object(mprisService, mprisPath).GetProperty(mprisVolume)
	if err != nil {
		return 0, false
	}
	f, isFloat := v.Value().(float64)
	return f, isFloat
}

// applyVolume clamps to [0,1], sets the MPRIS volume and shows the KDE OSD.
func applyVolume(conn *dbus.Conn, vol float64) {
	if vol < 0 {
		vol = 0
	} else if vol > 1 {
		vol = 1
	}
	obj := conn.Object(mprisService, mprisPath)
	if err := obj.SetProperty(mprisVolume, dbus.MakeVariant(vol)); err != nil {
		fmt.Fprintln(os.Stderr, "spotify-vol:", err)
		return
	}
	// Spotify-branded Plasma OSD popup; failure here is non-fatal.
	conn.Object(osdService, osdPath).Call(osdMethod, 0, int32(percent(vol)), "Spotify", "spotify")
}
