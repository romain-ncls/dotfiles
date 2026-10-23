// backdrop picks desktop and lock screen wallpapers from Windows Spotlight,
// Bing and Wallhaven, and learns from likes and dislikes which ones to show.
//
// The daemon keeps a pool of prefetched images so a dislike swaps the
// wallpaper instantly. It publishes the current image as the only file in
// $XDG_DATA_HOME/backdrop/current, which the Plasma wallpaper plugin
// (../plasma) watches: the lock screen greeter never touches the network.
//
// Usage:
//
//	backdrop daemon [--config f]  run the wallpaper daemon
//	backdrop like                 like the current wallpaper
//	backdrop dislike              dislike it and show another one
//	backdrop next                 show another one without judging this one
//	backdrop info [--json]        describe the current wallpaper
//	backdrop open                 open the current wallpaper's info page
//	backdrop stats                show what the daemon has learned
//	backdrop setup                use Backdrop on the desktop and lock screen
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/godbus/dbus/v5"
)

// pluginID must match ../plasma/metadata.json.
const pluginID = "com.github.romain-ncls.backdrop"

func usage() {
	fmt.Fprintln(os.Stderr, `usage: backdrop <command>

  daemon [--config file]  run the wallpaper daemon
  like                    like the current wallpaper
  dislike                 dislike it and show another one
  next                    show another one without judging this one
  info [--json]           describe the current wallpaper
  open                    open the current wallpaper's info page
  stats                   show what the daemon has learned
  setup                   use Backdrop on the desktop and lock screen`)
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	cmd, args := os.Args[1], os.Args[2:]

	var err error
	switch cmd {
	case "daemon":
		fs := flag.NewFlagSet("daemon", flag.ExitOnError)
		config := fs.String("config", "", "JSON file overriding the default settings")
		fs.Parse(args)
		err = runDaemon(*config)
	case "like", "dislike", "next":
		var inf Info
		if err = request("POST", "/"+cmd, &inf); err == nil {
			printAction(cmd, inf)
		}
	case "info":
		var inf Info
		if err = request("GET", "/current", &inf); err == nil {
			if len(args) > 0 && args[0] == "--json" {
				err = json.NewEncoder(os.Stdout).Encode(inf)
			} else {
				printInfo(inf)
			}
		}
	case "open":
		var inf Info
		if err = request("GET", "/current", &inf); err == nil {
			target := inf.InfoURL
			if target == "" {
				target = inf.File
			}
			err = exec.Command("xdg-open", target).Start()
		}
	case "stats":
		var st Stats
		if err = request("GET", "/stats", &st); err == nil {
			printStats(st)
		}
	case "setup":
		err = setup()
	default:
		usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "backdrop:", err)
		os.Exit(1)
	}
}

func dataDir() string {
	if d := os.Getenv("XDG_DATA_HOME"); d != "" {
		return filepath.Join(d, "backdrop")
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".local", "share", "backdrop")
}

func socketPath() string {
	dir := os.Getenv("XDG_RUNTIME_DIR")
	if dir == "" {
		dir = fmt.Sprintf("/run/user/%d", os.Getuid())
	}
	return filepath.Join(dir, "backdrop.sock")
}

// request calls the daemon's HTTP API over its unix socket and decodes the
// JSON reply into out.
func request(method, path string, out any) error {
	client := &http.Client{
		Timeout: 30 * time.Second,
		Transport: &http.Transport{
			DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
				var d net.Dialer
				return d.DialContext(ctx, "unix", socketPath())
			},
		},
	}
	req, err := http.NewRequest(method, "http://backdrop"+path, nil)
	if err != nil {
		return err
	}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("daemon not reachable (is backdrop.service running?): %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("%s", strings.TrimSpace(string(body)))
	}
	return json.Unmarshal(body, out)
}

func printAction(cmd string, inf Info) {
	switch {
	case cmd == "like":
		fmt.Printf("Liked %q\n", inf.Title)
	case inf.Pending:
		fmt.Println("Fetching a new wallpaper, it will show up in a moment")
	default:
		fmt.Printf("Now showing %q\n", inf.Title)
	}
}

func printInfo(inf Info) {
	if inf.ID == "" {
		fmt.Println("No wallpaper yet, the daemon is still fetching")
		return
	}
	fmt.Println(inf.Title)
	for _, line := range []string{inf.Place, inf.Credit} {
		if line != "" {
			fmt.Println("  " + line)
		}
	}
	status := fmt.Sprintf("%s, predicted like %.0f%%", inf.Source, 100*inf.Like)
	if inf.Liked {
		status += ", liked"
	}
	fmt.Println("  " + status)
	if inf.InfoURL != "" {
		fmt.Println("  " + inf.InfoURL)
	}
	fmt.Printf("  next change %s, %d in the pool\n", inf.Next.Local().Format("Mon 15:04"), inf.Pool)
}

func printStats(st Stats) {
	fmt.Printf("%d likes, %d dislikes, %d pictures in the pool\n\n", st.Likes, st.Dislikes, st.Pool)
	fmt.Printf("%-10s %7s %8s %6s %9s\n", "source", "config", "learned", "likes", "dislikes")
	for _, s := range st.Sources {
		fmt.Printf("%-10s %7.2f %+8.2f %6d %9d\n", s.Name, s.Weight, s.Learned, s.Likes, s.Dislikes)
	}
	for _, group := range []struct {
		title    string
		features []FeatureWeight
	}{{"More of", st.Loved}, {"Less of", st.Hated}} {
		if len(group.features) == 0 {
			continue
		}
		fmt.Printf("\n%s:\n", group.title)
		for _, f := range group.features {
			fmt.Printf("  %+.2f  %s (%d)\n", f.Weight, f.Name, f.Count)
		}
	}
}

// setup makes Backdrop the wallpaper plugin of every desktop and of the lock
// screen.
func setup() error {
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		return err
	}
	defer conn.Close()
	script := fmt.Sprintf("desktops().forEach(d => { d.wallpaperPlugin = %q; });", pluginID)
	call := conn.Object("org.kde.plasmashell", "/PlasmaShell").Call("org.kde.PlasmaShell.evaluateScript", 0, script)
	if call.Err != nil {
		return fmt.Errorf("desktop: %w", call.Err)
	}
	// The greeter reads this on every lock, nothing to restart.
	out, err := exec.Command("kwriteconfig6", "--file", "kscreenlockerrc",
		"--group", "Greeter", "--key", "WallpaperPlugin", pluginID).CombinedOutput()
	if err != nil {
		return fmt.Errorf("lock screen: %v: %s", err, out)
	}
	fmt.Println("Backdrop is now the desktop and lock screen wallpaper")
	return nil
}
