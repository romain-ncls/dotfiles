/*
 * Runs backdrop CLI commands for main.qml. A separate file because
 * plasma5support is on plasmashell's QML import path but not on the lock
 * screen greeter's, and main.qml must load in both.
 */
import QtQuick
import org.kde.plasma.plasma5support as P5Support

P5Support.DataSource {
    engine: "executable"
    connectedSources: []

    property var callbacks: ({})

    // @backdrop@ is replaced by the binary's store path at build time.
    function run(args, callback) {
        const cmd = "@backdrop@ " + args;
        callbacks[cmd] = callback;
        connectSource(cmd);
    }

    onNewData: (source, data) => {
        disconnectSource(source);
        const callback = callbacks[source];
        delete callbacks[source];
        callback?.(data["stdout"]);
    }
}
