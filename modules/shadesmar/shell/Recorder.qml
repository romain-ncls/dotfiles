// Screen recordings, on Spectacle's keys (modules/hyprland's binds.lua):
// Meta+Shift+R a region (picked with slurp), Meta+Alt+R the screen under the
// pointer; the same key again, or a click on the bar's dot (Recording.qml),
// stops. wl-screenrec records, on the GPU, the pointer in, to
// ~/Videos/Recordings/<date>.mp4. A region is framed just outside it while
// it's recorded: the frame isn't in the video. Then a notification: a click
// opens the video; Make a GIF (ffmpeg: its own palette, 30 fps, 1280 wide at
// most) and Show in Files. qs -c shadesmar ipc call recorder region|screen|stop
// (SHADESMAR_RECORDER: another recorder taking the same arguments, for the
// dev rigs).
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: recorder

    // "", "picking", "recording" or "stopping"
    property string state: ""
    readonly property bool busy: state === "recording" || state === "stopping"
    // the region recorded, in the layout ({x, y, w, h}), or null: a screen
    property var region: null
    property string file: ""
    property real started: 0
    property int seconds: 0

    readonly property string program: Quickshell.env("SHADESMAR_RECORDER") || "wl-screenrec"
    readonly property string folder: Theme.home + "/Videos/Recordings"

    function toggle(what) {
        if (state === "recording")
            stop()
        else if (state === "")
            start(what)
    }

    function start(what) {
        state = "picking"
        if (what === "region")
            pick.running = true
        else
            pointer.running = true
    }

    function record(target, region) {
        file = `${folder}/${Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss")}.mp4`
        recorder.region = region
        rec.command = ["sh", "-c", 'mkdir -p "$1" && shift && exec "$@"', "sh", folder, program, ...target, "-f", file]
        rec.running = true
        started = Date.now()
        seconds = 0
        state = "recording"
    }

    function stop() {
        if (state !== "recording")
            return
        state = "stopping"
        rec.signal(2) // SIGINT: it writes the end of the file, then quits
    }

    // ~ for the home
    function shown(path) {
        return path.startsWith(Theme.home + "/") ? "~" + path.slice(Theme.home.length) : path
    }

    // The screen under the pointer (the focused one may be another: the
    // focus moves with the pointer only once it moves); the focused one if
    // the pointer is nowhere.
    Process {
        id: pointer

        command: ["hyprctl", "-j", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = null
                try {
                    p = JSON.parse(text)
                } catch (e) {}
                const m = p ? Hyprland.monitors.values.find(m => m.scale > 0 && p.x >= m.x && p.x < m.x + m.width / m.scale && p.y >= m.y && p.y < m.y + m.height / m.scale) : null
                const screen = m ?? Hyprland.focusedMonitor
                if (screen)
                    recorder.record(["-o", screen.name], null)
                else
                    recorder.state = ""
            }
        }
    }

    // slurp's frame in lumar's colors, the size shown as it's dragged. Its
    // stdin empty: from a pipe, it would wait for boxes to choose from.
    Process {
        id: pick

        command: ["sh", "-c", 'exec slurp "$@" < /dev/null', "sh", "-d", "-w", "2", "-c", `${Theme.accent}ff`, "-b", `${Theme.frameColor}66`, "-s", "#00000000"]
        // "x,y wxh"; nothing on Escape. (Its output once it's all read: the
        // process may be said to have exited before.)
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.trim().match(/^(-?\d+),(-?\d+) (\d+)x(\d+)$/)
                if (!m) {
                    recorder.state = ""
                    return
                }
                recorder.record(["-g", text.trim()], {
                    x: +m[1],
                    y: +m[2],
                    w: +m[3],
                    h: +m[4]
                })
            }
        }
    }

    Process {
        id: rec

        stderr: StdioCollector {
            id: errors
        }
        onExited: code => {
            const failed = recorder.state !== "stopping" || code !== 0
            recorder.state = ""
            recorder.region = null
            if (failed)
                recorder.notify(["-u", "critical", "Recording failed", errors.text.trim().split("\n").slice(-3).join("\n")], null)
            else
                recorder.saved(recorder.file)
        }
    }

    Timer {
        running: recorder.busy
        repeat: true
        interval: 250
        onTriggered: recorder.seconds = Math.floor((Date.now() - recorder.started) / 1000)
    }

    // A notification through notify-send, which waits for its answer (the
    // action picked, on its stdout); answered(action), when it's answered.
    function notify(args, answered) {
        notifier.createObject(recorder, {
            command: ["notify-send", "-a", "Recordings", "-i", "media-record", ...args],
            answered: answered
        })
    }

    function saved(path) {
        const gif = path.endsWith(".mp4")
        notify(["-A", "default=Open", ...(gif ? ["-A", "gif=Make a GIF"] : []), "-A", "folder=Show in Files", gif ? "Recording saved" : "GIF saved", shown(path)], action => {
            if (action === "default")
                Quickshell.execDetached(["xdg-open", path])
            else if (action === "folder")
                Quickshell.execDetached(["nautilus", "--select", path])
            else if (action === "gif")
                recorder.toGif(path)
        })
    }

    function toGif(path) {
        const out = path.replace(/\.mp4$/, ".gif")
        converter.createObject(recorder, {
            command: ["ffmpeg", "-v", "error", "-y", "-i", path, "-vf", "fps=30,scale='min(iw,1280)':-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle", "-loop", "0", out],
            out: out
        })
    }

    Component {
        id: notifier

        Process {
            id: asking

            property var answered: null

            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    if (asking.answered && text.trim() !== "")
                        asking.answered(text.trim())
                    asking.destroy()
                }
            }
        }
    }

    Component {
        id: converter

        Process {
            property string out: ""

            running: true
            stderr: StdioCollector {
                id: problem
            }
            onExited: code => {
                if (code === 0)
                    recorder.saved(out)
                else
                    recorder.notify(["-u", "critical", "GIF failed", problem.text.trim().split("\n").slice(-3).join("\n")], null)
                destroy()
            }
        }
    }

    GlobalShortcut {
        appid: "shadesmar"
        name: "record-region"
        description: "Record a region of the screens"
        onPressed: recorder.toggle("region")
    }

    GlobalShortcut {
        appid: "shadesmar"
        name: "record-screen"
        description: "Record the screen under the pointer"
        onPressed: recorder.toggle("screen")
    }

    IpcHandler {
        target: "recorder"

        function region(): void {
            recorder.toggle("region")
        }
        function screen(): void {
            recorder.toggle("screen")
        }
        function stop(): void {
            recorder.stop()
        }
    }

    // The region's frame, 1 px outside it, on every screen it's on; the
    // pointer goes through.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: frame

            required property var modelData
            readonly property var r: recorder.region

            screen: modelData
            visible: r !== null && recorder.busy && r.x < modelData.x + modelData.width && r.x + r.w > modelData.x && r.y < modelData.y + modelData.height && r.y + r.h > modelData.y
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "shadesmar-recording"

            Rectangle {
                visible: frame.r !== null
                x: frame.r ? frame.r.x - frame.modelData.x - 3 : 0
                y: frame.r ? frame.r.y - frame.modelData.y - 3 : 0
                width: frame.r ? frame.r.w + 6 : 0
                height: frame.r ? frame.r.h + 6 : 0
                color: "transparent"
                border.width: 2
                border.color: Theme.warn
            }
        }
    }
}
