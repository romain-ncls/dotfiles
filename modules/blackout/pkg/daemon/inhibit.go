package main

import (
	"log"

	"github.com/godbus/dbus/v5"
)

// PowerDevil's inhibitions with the ChangeScreenSettings policy: the battery
// applet's "block sleep and screen locking", and apps that ask PowerDevil
// directly. org.freedesktop.ScreenSaver inhibitions go to KWin, which holds
// back the idle event itself. PowerDevil applies an inhibition after a few
// seconds.
const (
	powerDevil  = "org.kde.Solid.PowerManagement"
	policyPath  = "/org/kde/Solid/PowerManagement/PolicyAgent"
	policyAgent = "org.kde.Solid.PowerManagement.PolicyAgent"
)

// watchInhibitions sends whether something keeps the screen on now, then
// again whenever PowerDevil's inhibitions change.
func watchInhibitions(out chan<- bool) error {
	bus, err := dbus.ConnectSessionBus()
	if err != nil {
		return err
	}
	if err := bus.AddMatchSignal(
		dbus.WithMatchObjectPath(policyPath),
		dbus.WithMatchInterface("org.freedesktop.DBus.Properties"),
		dbus.WithMatchMember("PropertiesChanged"),
		dbus.WithMatchArg(0, policyAgent),
	); err != nil {
		bus.Close()
		return err
	}
	// A PowerDevil that restarts starts with no inhibitions, and says nothing.
	if err := bus.AddMatchSignal(
		dbus.WithMatchSender("org.freedesktop.DBus"),
		dbus.WithMatchMember("NameOwnerChanged"),
		dbus.WithMatchArg(0, powerDevil),
	); err != nil {
		bus.Close()
		return err
	}
	signals := make(chan *dbus.Signal, 8)
	bus.Signal(signals)
	agent := bus.Object(powerDevil, policyPath)
	failed := false
	check := func() {
		var on bool
		if err := agent.Call(policyAgent+".HasInhibition", 0, uint32(changeScreenSettings)).Store(&on); err != nil {
			if !failed {
				log.Printf("PowerDevil: %v", err)
			}
			failed = true
			on = false
		} else {
			failed = false
		}
		out <- on
	}
	go func() {
		check()
		for range signals {
			check()
		}
	}()
	return nil
}
