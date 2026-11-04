// The Silksong prompt's locker in Hyprland (SilksongPrompt.qml lists what it asks of one): the
// password through PAM (/etc/pam.d/silksong-lock, as KDE's lock screen asks it), Caps Lock from
// Hyprland, the battery from UPower. No Sleep, Switch User or keyboard layout: one user, one
// layout, and sleep is the lid's or the idle's. One for every screen, as Plasma's authenticator.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Services.UPower

Scope {
    id: locker

    signal failed()
    signal succeeded(bool hadPrompt)
    signal message(string text)
    signal askedSecret()
    signal readerFailed(int kind, string text)
    // The password was right: the lock screen unlocks the session (shell.qml).
    signal unlocked()

    // The full name, as Plasma's lock screen shows it, else the login.
    property string userName: Quickshell.env("USER") ?? ""
    property bool capsLock: false
    // Checking the password: nothing more is typed meanwhile.
    readonly property bool graceLocked: busy
    readonly property QtObject passwordSync: QtObject {
        property string password
    }
    readonly property bool canSuspend: false
    readonly property bool canSwitchUser: false
    readonly property string layoutName: ""
    readonly property var device: UPower.displayDevice
    readonly property int percent: device ? Math.round(device.percentage * 100) : 0
    readonly property string batteryText: device && device.isLaptopBattery ? percent + "%" : ""
    readonly property string batteryName: `Battery at ${percent}%`
    readonly property int readerKinds: 0
    readonly property var readers: []
    readonly property url mediaControls: ""
    readonly property url osd: ""
    // How many screens show the prompt (LockSurface.qml): Caps Lock is read meanwhile.
    property int promptsShown: 0

    property bool busy: false
    property bool hadPrompt: false
    property bool authenticated: false
    // Typed (and Enter pressed) before PAM asked for it: given as soon as it does.
    property string pending: ""

    function start() {
        if (!pam.active && !authenticated) {
            hadPrompt = false;
            pam.start();
        }
    }
    function respond(password) {
        if (pam.active && pam.responseRequired) {
            busy = true;
            pam.respond(password);
        } else {
            pending = password;
            start();
        }
    }
    function unlock() {
        if (authenticated) {
            unlocked();
        }
    }
    function suspend() {}
    function switchUser() {}
    function switchLayout() {}

    PamContext {
        id: pam

        config: "silksong-lock"
        // The dev rigs try the lock screen with a test PAM config, never the real password.
        configDirectory: Quickshell.env("HYPR_DEV") ? Quickshell.env("SILKSONG_LOCK_TEST_PAM") ?? "/etc/pam.d" : "/etc/pam.d"

        onPamMessage: {
            if (pam.responseRequired) {
                locker.busy = false;
                locker.hadPrompt = true;
                if (locker.pending !== "") {
                    const password = locker.pending;
                    locker.pending = "";
                    locker.busy = true;
                    pam.respond(password);
                } else if (pam.responseVisible) {
                    locker.message(pam.message);
                } else {
                    locker.askedSecret();
                }
            } else if (pam.message !== "") {
                locker.message(pam.message);
            }
        }
        onCompleted: result => {
            locker.busy = false;
            locker.pending = "";
            if (result === PamResult.Success) {
                locker.authenticated = true;
                locker.succeeded(locker.hadPrompt);
            } else {
                locker.failed();
            }
        }
        onError: error => {
            console.warn("Silksong lock screen: PAM:", PamError.toString(error));
            locker.busy = false;
            locker.pending = "";
            locker.failed();
        }
    }

    Process {
        id: fullName

        running: true
        command: ["getent", "passwd", Quickshell.env("USER") ?? ""]
        stdout: StdioCollector {
            onStreamFinished: {
                const gecos = (text.split(":")[4] ?? "").split(",")[0].trim();
                if (gecos !== "") {
                    locker.userName = gecos;
                }
            }
        }
    }

    // Caps Lock: Hyprland keeps it on every keyboard alike.
    Process {
        id: keyboards

        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    locker.capsLock = JSON.parse(text).keyboards.some(k => k.capsLock);
                } catch (e) {
                    locker.capsLock = false;
                }
            }
        }
    }
    Timer {
        interval: 400
        repeat: true
        triggeredOnStart: true
        running: locker.promptsShown > 0
        onTriggered: keyboards.running = true
    }
}
