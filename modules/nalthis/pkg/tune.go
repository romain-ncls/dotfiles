package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

// tune shows the four knobs as sliders: arrows move them and the session
// follows live (after a short pause, so holding a key doesn't flood KDE).
// Enter saves to the repo, Esc puts the saved palette back.
func tune() error {
	saved, err := loadKnobs()
	if err != nil {
		return err
	}
	restore, err := rawTerminal()
	if err != nil {
		return err
	}
	fmt.Print("\x1b[?1049h\x1b[?25l") // alternate screen, hide cursor
	defer func() {
		fmt.Print("\x1b[?25h\x1b[?1049l")
		restore()
	}()

	keys := make(chan string)
	go func() {
		buf := make([]byte, 16)
		for {
			n, err := os.Stdin.Read(buf)
			if err != nil {
				close(keys)
				return
			}
			keys <- string(buf[:n])
		}
	}()

	k, row, status := saved, 0, ""
	var pending <-chan time.Time
	for {
		draw(k, saved, row, status)
		select {
		case <-pending:
			pending = nil
			status = ""
			if err := apply(k); err != nil {
				status = "apply failed: " + err.Error()
			}
		case key, ok := <-keys:
			if !ok {
				return nil
			}
			kn := KnobList[row]
			changed := true
			switch key {
			case "\x1b[A", "k":
				row, changed = (row+len(KnobList)-1)%len(KnobList), false
			case "\x1b[B", "j":
				row, changed = (row+1)%len(KnobList), false
			case "\x1b[D", "h":
				*kn.Get(&k) -= kn.Step
			case "\x1b[C", "l":
				*kn.Get(&k) += kn.Step
			case "\x1b[5~", "H":
				*kn.Get(&k) += kn.BigStep
			case "\x1b[6~", "L":
				*kn.Get(&k) -= kn.BigStep
			case "d":
				k = Defaults
			case "\r", "\n":
				if err := saveKnobs(k); err != nil {
					status = "save failed: " + err.Error()
					continue
				}
				return apply(k)
			case "\x1b", "q", "\x03":
				if k == saved {
					return nil
				}
				return apply(saved)
			default:
				changed = false
			}
			if changed {
				k.Clamp()
				status = "applying…"
				pending = time.After(250 * time.Millisecond)
			}
		}
	}
}

// rawTerminal puts the terminal in raw mode and returns how to undo it.
func rawTerminal() (func(), error) {
	stty := func(args ...string) (string, error) {
		cmd := exec.Command("stty", args...)
		cmd.Stdin = os.Stdin
		out, err := cmd.Output()
		return strings.TrimSpace(string(out)), err
	}
	state, err := stty("-g")
	if err != nil {
		return nil, fmt.Errorf("tune needs a terminal: %w", err)
	}
	if _, err := stty("raw", "-echo"); err != nil {
		return nil, err
	}
	return func() { stty(state) }, nil
}

const sliderWidth = 36

func bg(c RGB) string { return fmt.Sprintf("\x1b[48;2;%d;%d;%dm", c[0], c[1], c[2]) }
func fg(c RGB) string { return fmt.Sprintf("\x1b[38;2;%d;%d;%dm", c[0], c[1], c[2]) }

func draw(k, saved Knobs, row int, status string) {
	p := Compute(k)
	var b strings.Builder
	line := func(format string, a ...any) { fmt.Fprintf(&b, format+"\x1b[K\r\n", a...) }
	b.WriteString("\x1b[H")
	line("")
	line("  \x1b[1mNalthis palette\x1b[0m   %s", map[bool]string{true: "saved", false: "\x1b[33mnot saved\x1b[0m"}[k == saved])
	line("")
	for i, kn := range KnobList {
		v := *kn.Get(&k)
		pos := int((v - kn.Min) / (kn.Max - kn.Min) * (sliderWidth - 1))
		var track strings.Builder
		for x := 0; x < sliderWidth; x++ {
			t := kn.Min + (kn.Max-kn.Min)*float64(x)/(sliderWidth-1)
			kk := k
			*kn.Get(&kk) = t
			c := Compute(kk).Pane
			if kn.Name == "accent" {
				c = Compute(kk).Accent
			}
			mark := " "
			if x == pos {
				mark = "\x1b[1m" + fg(p.Text) + "●\x1b[22m"
			}
			track.WriteString(bg(c) + mark)
		}
		cursor, label := "  ", kn.Label
		if i == row {
			cursor, label = fg(p.AccentText)+"› \x1b[0m", "\x1b[1m"+kn.Label+"\x1b[0m"
		}
		line("  %s%-12s%s\x1b[0m  %s", cursor, label+strings.Repeat(" ", max(0, 10-len(kn.Label))), track.String(), knobValue(kn.Name, v))
	}
	line("")
	swatch := func(c RGB, name string) string { return bg(c) + "      \x1b[0m " + name + "  " }
	line("  %s%s%s%s%s", swatch(p.Frame, "frame"), swatch(p.Base, "base"), swatch(p.Pane, "pane"), swatch(p.Raised, "raised"), swatch(p.Overlay, "overlay"))
	line("  %s%s", swatch(p.Accent, "accent"), swatch(p.AccentText, "accent text"))
	line("")
	line("  %s  %sText  %sSecondary  %sDisabled  %sLink  \x1b[0m", bg(p.Base), fg(p.Text), fg(p.Text2), fg(p.Text3), fg(p.AccentText))
	line("  %s  %s  Selected  \x1b[0m%s  %s  Button  \x1b[0m", bg(p.Base), bg(p.Accent)+fg(p.Text), bg(p.Base), bg(p.Raised)+fg(p.Text))
	line("")
	line("  \x1b[2m↑↓ choose   ←→ adjust   PgUp/PgDn big steps   d defaults   Enter save   Esc cancel\x1b[0m")
	line("  %s", status)
	b.WriteString("\x1b[J")
	os.Stdout.WriteString(b.String())
}

func knobValue(name string, v float64) string {
	switch name {
	case "hue", "accent":
		return fmt.Sprintf("%3.0f°", v)
	case "tint":
		return fmt.Sprintf("×%.2f", v)
	}
	return fmt.Sprintf("%+.3f", v)
}
