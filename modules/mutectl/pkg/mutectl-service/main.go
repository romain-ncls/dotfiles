// mutectl-service relays mute commands to the call clients (the Vencord
// plugin, the Teams Chrome extension) as Server-Sent Events.
//
// POST /mute, /unmute or /afk broadcasts an event of that name to every
// client subscribed to GET /sse. Clients listen with
// EventSource.addEventListener(<name>), so the event name is what matters.
package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"sync"
)

var commands = []string{"mute", "unmute", "afk"}

type hub struct {
	mu      sync.Mutex
	clients map[chan string]struct{}
}

func (h *hub) subscribe() chan string {
	ch := make(chan string, 8)
	h.mu.Lock()
	h.clients[ch] = struct{}{}
	h.mu.Unlock()
	return ch
}

func (h *hub) unsubscribe(ch chan string) {
	h.mu.Lock()
	delete(h.clients, ch)
	h.mu.Unlock()
}

func (h *hub) broadcast(cmd string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for ch := range h.clients {
		select {
		case ch <- cmd:
		default: // client stalled with a full buffer: drop rather than block the others
		}
	}
}

func (h *hub) serveSSE(w http.ResponseWriter, r *http.Request) {
	rc := http.NewResponseController(w)
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.WriteHeader(http.StatusOK)
	if err := rc.Flush(); err != nil {
		return
	}

	ch := h.subscribe()
	defer h.unsubscribe(ch)

	for {
		select {
		case <-r.Context().Done(): // client disconnected
			return
		case cmd := <-ch:
			// EventSource drops events without a data line, so always send one.
			if _, err := fmt.Fprintf(w, "event: %s\ndata: %s\n\n", cmd, cmd); err != nil {
				return
			}
			if err := rc.Flush(); err != nil {
				return
			}
		}
	}
}

func main() {
	addr := flag.String("addr", "127.0.0.1:4815", "listen address")
	flag.Parse()

	h := &hub{clients: make(map[chan string]struct{})}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /sse", h.serveSSE)
	for _, cmd := range commands {
		mux.HandleFunc("POST /"+cmd, func(w http.ResponseWriter, r *http.Request) {
			h.broadcast(cmd)
			w.WriteHeader(http.StatusNoContent)
		})
	}

	// The Chrome extension connects from the Teams origin.
	cors := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		mux.ServeHTTP(w, r)
	})

	log.Fatal(http.ListenAndServe(*addr, cors))
}
