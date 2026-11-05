#!/bin/bash
# The Silksong lock screen's cost on Hyprland (README, Lock screen), as modules/hyprland's
# lock-screen runs it (quickshell/), in a headless Hyprland (modules/hyprland/dev/headless.sh):
# locked over a terminal, held, unlocked with a test password, a few times over. Nothing of it
# shows on the desk, and nothing reaches the session it's run from: the rig has its own Wayland
# display and its own D-Bus, and its own PAM config with the password "hornet".
#
#     tools/lockbench.sh [--locks N] [--hold S] [--load N] [--weight W] [--battery] [--config DIR] [--keep]
#
# For each lock, in ms after it starts: when the paintings show (the first screen, the last),
# when the worlds have everything they show, when they wash in, when the paintings are gone;
# over that time, each screen's frames, the longest time between two and how many took over
# 25 ms (a frame missed at 60 Hz), and the GUI thread's longest gap between two of a window's
# syncs (held, which the brush, on the render thread, rides through; or with nothing to sync, the
# world still); then, held locked (--hold, 8 s), the process's CPU (% of one
# core), GPU (render engine ms a second) and the fewest frames a second of its screens; its
# peak memory; how it ended. Last, the median of each over the locks (--locks, 3). --load runs
# N busy loops meanwhile, at the lock's own priority: a machine under load, the rig's
# compositor kept out of its way as the session's is. --weight runs the lock with that CPU
# weight (cgroup's cpu.weight, 100 by default): under load (10 loops on 12 threads) 1000 didn't
# help, the GPU slowing as the CPU takes the laptop's power. --battery has the lock think it's
# on battery, its worlds then still (shell.qml's onBattery). --config benches another copy of
# quickshell/; --keep keeps the logs. The render loop's timing is logged
# (qt.scenegraph.time.renderloop), which costs a little CPU. One bench at a time (a lock file),
# the rig and the lock under a memory cap.
set -u
here=$(dirname "$(realpath "$0")")
wallpaper=$(dirname "$here")
repo=$(realpath "$wallpaper/../../..")
locks=3 hold=8 load=0 cfg=$wallpaper/quickshell keep=0 weight= power=ac
while [ $# -gt 0 ]; do
    case $1 in
        --locks) locks=$2; shift 2 ;;
        --hold) hold=$2; shift 2 ;;
        --load) load=$2; shift 2 ;;
        --config) cfg=$(realpath "$2"); shift 2 ;;
        --keep) keep=1; shift ;;
        --weight) weight=$2; shift 2 ;;
        --battery) power=battery; shift ;;
        *) sed -n '2,/^set -u/{/^set -u/d; s/^# \{0,1\}//p}' "$0"; exit 2 ;;
    esac
done
run=${XDG_RUNTIME_DIR:-/tmp}
exec 9> "$run/silksong-lockbench.lock"
flock -n 9 || { echo "lockbench: another one is running" >&2; exit 1; }
tmp=$(mktemp -d "$run/silksong-lockbench.XXXXXX")
H= WL= rig= bus= loads=
cleanup() {
    for p in $loads; do kill "$p" 2> /dev/null; done
    [ -n "$H" ] && hyprctl -i "$H" dispatch 'hl.dsp.exit()' > /dev/null 2>&1
    if [ -n "$rig" ]; then
        for _ in $(seq 1 50); do kill -0 "$rig" 2> /dev/null || break; sleep 0.1; done
    fi
    [ -n "$bus" ] && kill "$bus" 2> /dev/null
    if [ $keep = 1 ]; then echo "logs kept in $tmp" >&2; else rm -rf "$tmp"; fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# The test password, and a session bus of the rig's own.
mkdir -p "$tmp/pam"
cat > "$tmp/pam/check" << 'EOF'
#!/bin/sh
# The bench's test password: "hornet".
pw=$(head -c 200 | tr -d '\000')
[ "$pw" = hornet ]
EOF
chmod +x "$tmp/pam/check"
printf 'auth [success=done default=ignore] pam_exec.so expose_authtok quiet %s\nauth requisite pam_deny.so\naccount required pam_permit.so\n' \
    "$tmp/pam/check" > "$tmp/pam/silksong-lock"
cat > "$tmp/bus.conf" << 'EOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <auth>EXTERNAL</auth>
  <policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>
</busconfig>
EOF
dbus-daemon --config-file="$tmp/bus.conf" --print-address=1 --print-pid=1 --fork > "$tmp/bus.out"
BUS=$(sed -n 1p "$tmp/bus.out") bus=$(sed -n 2p "$tmp/bus.out")

# The rig: the Hyprland instance that wasn't there before, never the session's own.
before=$(hyprctl instances -j 2> /dev/null | jq -r '.[].instance')
"$repo/modules/hyprland/dev/headless.sh" > "$tmp/headless.log" 2>&1 9>&- &
rig=$!
for _ in $(seq 1 100); do
    new=$(hyprctl instances -j 2> /dev/null | jq -r --arg before "$before" \
        '.[] | select(.instance as $i | ($before | split("\n") | index($i)) == null) | "\(.instance) \(.wl_socket)"' | head -1)
    [ -n "$new" ] && break
    sleep 0.2
done
read -r H WL <<< "${new:-}"
if [ -z "$H" ] || [ -z "$WL" ] || [ "$WL" = "${WAYLAND_DISPLAY:-}" ]; then
    echo "lockbench: no headless Hyprland came up (see $tmp/headless.log)" >&2
    keep=1
    exit 1
fi
for _ in $(seq 1 50); do
    [ "$(hyprctl -i "$H" -j monitors 2> /dev/null | jq length)" -ge 3 ] 2> /dev/null && break
    sleep 0.2
done
# The rig's compositor out of the load's way, as the session's is (in its login session's scope,
# beside all the apps' slice, which the load is in): else it's starved too, and the lock's frames
# wait for it.
hp=$(hyprctl instances -j | jq -r --arg h "$H" '.[] | select(.instance == $h) | .pid')
systemctl --user set-property --runtime "$(sed -n 's|^0::.*/||p' "/proc/$hp/cgroup")" CPUWeight=10000 2> /dev/null
# From here on everything this runs (the terminal, wtype) is the rig's.
export WAYLAND_DISPLAY=$WL HYPRLAND_INSTANCE_SIGNATURE=$H DBUS_SESSION_BUS_ADDRESS=$BUS HYPR_DEV=headless \
    GTK_A11Y=none NO_AT_BRIDGE=1
hyprctl -i "$H" dispatch 'hl.dsp.focus({ monitor = "LAPTOP" })' > /dev/null
setsid -f ghostty --gtk-single-instance=false -e sh -c 'man -P cat Hyprland; exec sleep 600' > /dev/null 2>&1 9>&-
sleep 2

for _ in $(seq 1 "$load"); do
    sh -c 'while :; do :; done' 9>&- &
    loads="$loads $!"
done

# CPU ticks (utime + stime), GPU render engine ns (each DRM client once), the time in ms.
sample() {
    local cpu gpu
    cpu=$(awk '{ print $14 + $15 }' "/proc/$1/stat" 2> /dev/null)
    gpu=$(cat /proc/"$1"/fdinfo/* 2> /dev/null | awk '/^drm-client-id:/ { id = $2 } /^drm-engine-render:/ { if ($2 > g[id]) g[id] = $2 }
        END { s = 0; for (i in g) s += g[i]; print s }')
    echo "${cpu:-0} ${gpu:-0} $(($(date +%s%N) / 1000000))"
}
tck=$(getconf CLK_TCK)

echo "lockbench: $locks locks held ${hold} s, load $load${weight:+, CPU weight $weight}, on $power, $(git -C "$repo" log -1 --format='%h %s' | cut -c1-70)"
: > "$tmp/values"
for n in $(seq 1 "$locks"); do
    log=$tmp/lock-$n.log
    SILKSONG_LOCK_TEST_PAM=$tmp/pam SILKSONG_LOCK_POWER=$power SILKSONG_DESK=DP-3:476x268,eDP-1:344x215,HDMI-A-1:476x268 \
        QT_LOGGING_RULES="qt.scenegraph.time.renderloop=true" \
        systemd-run --user --scope -q -p MemoryMax=3G ${weight:+-p CPUWeight=$weight} qs --log-times -p "$cfg" > "$log" 2>&1 9>&- &
    q=$!
    for _ in $(seq 1 200); do
        grep -q 'the screens as they were, let go' "$log" && break
        kill -0 $q 2> /dev/null || break
        sleep 0.1
    done
    s1=$(sample $q)
    sleep "$hold"
    s2=$(sample $q)
    hwm=$(awk '/^VmHWM/ { print int($2 / 1024) }' "/proc/$q/status" 2> /dev/null)
    sleep 0.3
    wtype hornet
    wtype -k Return
    for _ in $(seq 1 50); do kill -0 $q 2> /dev/null || break; sleep 0.1; done
    if kill -0 $q 2> /dev/null; then
        kill $q
        status=killed
    else
        wait $q
        status=$?
        [ "$status" = 0 ] && status=unlocked || status="exit $status"
    fi
    gawk -v n="$n" -v s1="$s1" -v s2="$s2" -v tck="$tck" -v hwm="${hwm:-0}" -v status="$status" -v values="$tmp/values" '
        function ms(d, t,   p) { # "YYYY-MM-DD" "HH:MM:SS.mmm": ms since the epoch
            p = d " " t; gsub(/[-:]/, " ", p)
            return mktime(substr(p, 1, 19)) * 1000 + substr(t, 10, 3)
        }
        function show(v) { return v == "" ? "-" : int(v) }
        BEGIN { split(s1, a); split(s2, b); t1 = a[3]; t2 = b[3] }
        { sub(/\x1b\[[0-9;]*m/, ""); gsub(/\x1b\[[0-9;]*m/, "") }
        $0 ~ /Launching config/ && t0 == "" { t0 = ms($1, $2) }
        /Silksong lock screen: .* painting shown/ { t = ms($1, $2) - t0; if (shown1 == "") shown1 = t; shown2 = t; end = "" }
        /Silksong lock screen: .* world revealed/ { world = ms($1, $2) - t0 }
        /Silksong lock screen: .* world washing in/ && wash == "" { wash = ms($1, $2) - t0 }
        /Silksong lock screen: .* painting gone/ { gone = ms($1, $2) - t0 }
        /\[render thread .*syncAndRender: start, elapsed since last call: / {
            match($0, /\[window (0x[0-9a-f]+)\]/, wm); win = wm[1]; e = $NF == "ms" ? $(NF - 1) : $NF; t = ms($1, $2)
            if (shown1 != "" && t - t0 >= shown1 && (gone == "" || t - t0 <= gone)) {
                f[win]++; if (e > longest[win]) longest[win] = e; if (e > 25) over[win]++
            }
            if (t >= t1 && t <= t2) held[win]++
        }
        /\[gui thread\] polishAndSync: start, elapsed since last call: / {
            e = $NF == "ms" ? $(NF - 1) : $NF; t = ms($1, $2) - t0
            if (shown1 != "" && t >= shown1 && (gone == "" || t <= gone) && e > gui) gui = e
        }
        END {
            screens = 0; frames = 0; long = 0; missed = 0; fps = ""
            for (w in f) if (f[w] >= 20) {
                screens++; frames += f[w]; missed += over[w]; if (longest[w] > long) long = longest[w]
                r = held[w] / ((t2 - t1) / 1000); if (fps == "" || r < fps) fps = r
            }
            cpu = (b[1] - a[1]) / tck / ((t2 - t1) / 1000) * 100
            gpu = (b[2] - a[2]) / 1e6 / ((t2 - t1) / 1000)
            printf "lock %d: shown %s-%s, world %s, wash %s, gone %s ms · %d screens, %d frames, longest %s ms, %d over 25 ms · GUI gap %s ms · locked: CPU %.0f %%, GPU %.1f ms/s, %s fps · %d MB · %s\n",
                n, show(shown1), show(shown2), show(world), show(wash), show(gone), screens, frames, show(long), missed, show(gui),
                cpu, gpu, show(fps), hwm, status
            printf "%s %s %s %s %s %s %s %s %.1f %.2f %s %s\n", shown2, world, wash, gone, long, missed, gui, frames, cpu, gpu, fps == "" ? 0 : fps, hwm >> values
        }' "$log"
    sleep 1
done
[ "$locks" -gt 1 ] && sort -n "$tmp/values" | gawk -v n="$locks" '
    { for (i = 1; i <= NF; i++) v[i][NR] = $i }
    END {
        for (i = 1; i <= 12; i++) { k = asort(v[i], s); m[i] = s[int((k + 1) / 2)] }
        printf "median: shown %d, world %d, wash %d, gone %d ms · longest frame %d ms, %d over 25 ms · GUI gap %d ms · locked: CPU %.0f %%, GPU %.1f ms/s, %d fps · %d MB\n",
            m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[9], m[10], m[11], m[12]
    }'
exit 0
