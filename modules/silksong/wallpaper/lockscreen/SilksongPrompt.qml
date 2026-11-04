/*
    SPDX-FileCopyrightText: 2014 Aleix Pol Gonzalez <aleixpol@blue-systems.com>
    SPDX-FileCopyrightText: 2016 David Edmundson <davidedmundson@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

// The Silksong prompt: Plasma 6.7's LockScreenUi.qml and MainBlock.qml with the game's look: the
// pause menu's column between Hornet's dialogue fleur and the weaver's prompt fleur, the full
// stops the game ends other characters' lines with for the characters typed, the inventory's
// hairline under them, messages written out as dialogue and ended with Hornet's needle, Sleep and
// Switch User as menu items, and the aquarium behind darkened and blurred while the prompt is up.
// What it does is Plasma's: the same calls, messages, timers and keys. The art comes from kit
// (ui/Kit.qml, tools/extract_ui.py).
//
// It draws only, in QtQuick alone, for any lock screen: what it asks of one goes through locker,
// which Plasma's (SilksongLockUi.qml) and Hyprland's (../quickshell/Locker.qml) give, with:
//   signals    failed(), succeeded(bool hadPrompt), message(string text), askedSecret(),
//              readerFailed(int kind, string text)
//   properties userName, capsLock, graceLocked, passwordSync (an object whose password every
//              screen's prompt shares), canSuspend, canSwitchUser, layoutName ("": no button),
//              batteryText and batteryName ("": none), readerKinds and readers ([{kind, label}]:
//              the fingerprint and smartcard readers' hints), mediaControls and osd (a file to
//              load, or "")
//   functions  start(), respond(password), unlock(), suspend(), switchUser(), switchLayout()

import QtQml
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Effects
import Qt5Compat.GraphicalEffects as GE

Item {
    id: lockScreenUi

    required property QtObject locker
    required property QtObject kit
    required property url art
    // What blurs behind the prompt: the lock screen's wallpaper.
    property Item backdrop
    // The desktop's animation speeds (Plasma's Kirigami.Units), and the shake's.
    property int veryLongDuration: 400
    property int humanMoment: 2000
    property int shakeDuration: 600
    property real osdMargin: 18
    // The layout's button, where Plasma puts its layout switcher (it takes the wheel there).
    readonly property Item layoutArea: layoutButton
    // Up, rather than the aquarium alone.
    readonly property bool shown: lockScreenRoot.uiVisible

    // Effects need the GPU; with software rendering, the veil alone.
    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software
    readonly property color ink: "#f3ece2"

    property string notification
    signal clearPassword()
    signal notificationRepeated()

    function tr(context, text) {
        return (typeof i18ndc === "function" ? i18ndc("plasma_shell_org.kde.plasma.desktop", context, text) : text).replace("&", "");
    }

    function handleMessage(msg) {
        if (!notification) {
            notification += msg;
        } else if (notification.includes(msg)) {
            notificationRepeated();
        } else {
            notification += "\n" + msg
        }
    }

    Connections {
        target: lockScreenUi.locker
        function onFailed() {
            const msg = lockScreenUi.tr("@info:status", "Unlocking failed");
            lockScreenUi.handleMessage(msg);
            graceLockTimer.restart();
            notificationRemoveTimer.restart();
            rejectPasswordAnimation.start();
        }

        function onSucceeded(hadPrompt) {
            if (hadPrompt) {
                lockScreenUi.locker.unlock();
            } else {
                prompt.noPassword = true;
                unlockButton.forceActiveFocus();
            }
        }

        function onMessage(text) {
            lockScreenUi.handleMessage(text);
        }

        function onAskedSecret() {
            prompt.showPassword = false;
            passwordBox.forceActiveFocus();
        }
    }

    // Breeze's RejectPasswordAnimation: the target shaken sideways, disabled meanwhile.
    component Shake: QtObject {
        id: shake
        property Item target
        signal finished()
        readonly property Animation animation: PathAnimation {
            target: Item { id: fakeTarget }
            alwaysRunToEnd: true
            duration: lockScreenUi.shakeDuration
            easing.type: Easing.OutCubic
            onFinished: shake.finished()
            path: Path {
                PathPolyline {
                    path: {
                        const swing = Application.layoutDirection === Qt.RightToLeft ? 15 : -15;
                        const here = Qt.point(swing, 0);
                        const there = Qt.point(-swing, 0);
                        return [Qt.point(0, 0), here, there, here, there, here, there, Qt.point(0, 0)];
                    }
                }
            }
        }
        readonly property Binding disable: Binding {
            target: shake.target
            property: "enabled"
            value: false
            when: shake.animation.running
            restoreMode: Binding.RestoreBindingOrValue
        }
        readonly property Binding move: Binding {
            target: shake.target
            property: "transform"
            value: Translate {
                x: fakeTarget.x
            }
            restoreMode: Binding.RestoreBindingOrValue
        }
        function start() {
            animation.start();
        }
    }

    Shake {
        id: rejectPasswordAnimation
        target: entry
    }

    FontLoader { id: trajan; source: lockScreenUi.art + lockScreenUi.kit.fontTrajan }
    FontLoader { id: trajanBold; source: lockScreenUi.art + lockScreenUi.kit.fontTrajanBold }
    FontLoader { id: perpetua; source: lockScreenUi.art + lockScreenUi.kit.fontPerpetua }

    // One of the game's ornaments, growing open from its centre (its frames in Kit.qml) each time
    // the prompt comes up, then holding its last frame.
    component Fleur: Image {
        id: fleur
        required property var frames
        property int frame: frames.length - 1
        function play() {
            frame = 0;
            grow.restart();
        }
        source: lockScreenUi.art + frames[frame]
        cache: true
        Timer {
            id: grow
            interval: 42 // the game's 24 frames a second
            repeat: true
            onTriggered: {
                if (fleur.frame < fleur.frames.length - 1) {
                    fleur.frame++;
                } else {
                    stop();
                }
            }
        }
    }

    // A menu item: the game's type, its selection mark either side when hovered or focused.
    component GameItem: Item {
        id: menuItem
        property alias text: label.text
        signal clicked()
        implicitWidth: label.implicitWidth + 92
        implicitHeight: label.implicitHeight + 16
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label.text
        Accessible.onPressAction: clicked()
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        Keys.onSpacePressed: clicked()
        readonly property bool lit: mouse.containsMouse || activeFocus
        Text {
            id: label
            anchors.centerIn: parent
            font.family: trajan.name
            font.pixelSize: 25
            font.letterSpacing: 4
            font.capitalization: Font.AllUppercase
            color: lockScreenUi.ink
            opacity: menuItem.lit ? 1 : 0.82
        }
        Repeater {
            model: 2
            Image {
                required property int index
                source: lockScreenUi.art + lockScreenUi.kit.mark
                width: 28
                height: 23
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
                x: index === 0 ? 0 : menuItem.width - width
                mirror: index === 0
                opacity: menuItem.lit ? 0.95 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: menuItem.clicked()
        }
    }

    // A reader's hint, replaced a moment by its error, as in Plasma's prompt.
    component FailableLabel: Text {
        id: _failableLabel
        required property int kind
        required property string label

        visible: lockScreenUi.locker.readerKinds & kind
        text: label
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        font.family: perpetua.name
        font.italic: true
        font.pixelSize: 24
        color: Qt.rgba(0.95, 0.93, 0.89, 0.8)

        Shake {
            id: _rejectAnimation
            target: _failableLabel
            onFinished: _timer.restart()
        }

        Connections {
            target: lockScreenUi.locker
            function onReaderFailed(kind, text) {
                if (kind & _failableLabel.kind) {
                    _failableLabel.text = text
                    _rejectAnimation.start()
                }
            }
        }
        Timer {
            id: _timer
            interval: lockScreenUi.humanMoment
            onTriggered: {
                _failableLabel.text = Qt.binding(() => _failableLabel.label)
            }
        }
    }

    MouseArea {
        id: lockScreenRoot
        objectName: "lockScreenRoot"

        property bool uiVisible: false
        property bool seenPositionChange: false
        property bool blockUI: containsMouse && passwordBox.text.length > 0

        x: parent.x
        y: parent.y
        width: parent.width
        height: parent.height
        hoverEnabled: true
        cursorShape: uiVisible ? Qt.ArrowCursor : Qt.BlankCursor
        drag.filterChildren: true
        onPressed: uiVisible = true;
        onPositionChanged: {
            uiVisible = seenPositionChange;
            seenPositionChange = true;
        }
        onUiVisibleChanged: {
            if (uiVisible) {
                Window.window.requestActivate();
                prompt.reveal();
            }

            if (blockUI) {
                fadeoutTimer.running = false;
            } else if (uiVisible) {
                fadeoutTimer.restart();
            }
            lockScreenUi.locker.start();
        }
        onBlockUIChanged: {
            if (blockUI) {
                fadeoutTimer.running = false;
                uiVisible = true;
            } else {
                fadeoutTimer.restart();
            }
        }
        onExited: {
            uiVisible = false;
        }
        Keys.onEscapePressed: {
            // If the escape key is pressed, the lock screen may turn the screen off (kscreenlocker does).
            // We do not want to show the password prompt in this case.
            if (uiVisible) {
                uiVisible = false;
                lockScreenUi.clearPassword();
            }
        }
        Keys.onPressed: event => {
            uiVisible = true;
            event.accepted = false;
        }
        Timer {
            id: fadeoutTimer
            interval: 10000
            onTriggered: {
                if (!lockScreenRoot.blockUI) {
                    prompt.showPassword = false;
                    lockScreenRoot.uiVisible = false;
                }
            }
        }
        Timer {
            id: notificationRemoveTimer
            interval: 3000
            onTriggered: lockScreenUi.notification = ""
        }
        Timer {
            id: graceLockTimer
            interval: 3000
            onTriggered: {
                lockScreenUi.clearPassword();
                lockScreenUi.locker.start();
            }
        }

        // 0 while the aquarium is alone, 1 under the prompt: what's behind it darkens and blurs
        // over the same time as Plasma's.
        property real factor: uiVisible ? 1 : 0
        Behavior on factor {
            NumberAnimation {
                duration: lockScreenUi.veryLongDuration * 2
                easing.type: Easing.InOutQuad
            }
        }

        // Made only while it shows: a blur kept ready would redraw the aquarium twice all along.
        Loader {
            anchors.fill: parent
            active: !lockScreenUi.softwareRendering && lockScreenRoot.factor > 0
            sourceComponent: MultiEffect {
                source: lockScreenUi.backdrop
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: 32
                blur: 0.85 * lockScreenRoot.factor
            }
        }
        GE.RadialGradient {
            anchors.fill: parent
            visible: opacity > 0
            opacity: lockScreenRoot.factor
            horizontalRadius: width * 0.7
            verticalRadius: height * 0.65
            verticalOffset: height * 0.02
            gradient: Gradient {
                // A veil of 55% at the centre, 80% at the edges, over the aquarium dimmed to 92%.
                GradientStop { position: 0; color: Qt.rgba(0.024, 0.016, 0.04, 0.586) }
                GradientStop { position: 1; color: Qt.rgba(0.024, 0.016, 0.04, 0.816) }
            }
        }

        Item {
            id: prompt
            objectName: "prompt"

            property bool showPassword: false
            property bool noPassword: false
            readonly property real cy: height / 2

            function reveal() {
                topFleur.play();
                hairline.play();
                bottomFleur.play();
            }

            anchors.fill: parent
            opacity: lockScreenRoot.uiVisible ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                NumberAnimation {
                    duration: lockScreenUi.veryLongDuration
                    easing.type: Easing.InOutQuad
                }
            }

            // The soft dark halo the game's titles have on its scenes, on everything at once.
            layer.enabled: !lockScreenUi.softwareRendering && visible
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "black"
                shadowOpacity: 0.95
                shadowBlur: 0.55
                blurMax: 40
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
            }

            Fleur {
                id: topFleur
                frames: lockScreenUi.kit.fleurTop
                anchors.horizontalCenter: parent.horizontalCenter
                y: prompt.cy - 265 - height / 2
            }

            Text {
                id: clock
                property date now: new Date()
                anchors.horizontalCenter: parent.horizontalCenter
                y: prompt.cy - 131 - height / 2
                font.family: trajan.name
                font.pixelSize: 112
                font.letterSpacing: 5
                color: lockScreenUi.ink
                text: Qt.formatTime(now, Qt.locale().timeFormat(Locale.ShortFormat))
                Timer {
                    interval: 1000
                    repeat: true
                    triggeredOnStart: true
                    running: prompt.visible
                    onTriggered: clock.now = new Date()
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: prompt.cy - 67 - height / 2
                font.family: perpetua.name
                font.italic: true
                font.pixelSize: 32
                color: "#e2d8ca"
                text: Qt.locale().toString(clock.now, "dddd d MMMM")
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: prompt.cy + 36 - height / 2
                font.family: trajanBold.name
                font.bold: true
                font.pixelSize: 30
                font.letterSpacing: 4.8
                font.capitalization: Font.AllUppercase
                color: lockScreenUi.ink
                text: lockScreenUi.locker.userName
            }

            // The password: a full stop per character, or the characters themselves while the eyes are
            // open; the hairline under them. They keep their size while they fit, then get smaller
            // (down to 60%), then the field grows (up to 1100 wide), then the first ones slide out
            // at the left.
            Item {
                id: entry
                objectName: "entry"
                readonly property int count: passwordBox.text.length
                // The full stops are 22 high and 12 apart at full size; the field keeps 100 clear
                // each side, for the eyes.
                readonly property real dotWidth: 22 * dotSize.implicitWidth / Math.max(1, dotSize.implicitHeight)
                readonly property real natural: count === 0 ? 0
                    : prompt.showPassword ? shownSize.implicitWidth
                    : count * dotWidth + (count - 1) * 12
                readonly property real fitScale: natural > 360 ? Math.max(0.6, 360 / natural) : 1
                property real glyphScale: fitScale
                Behavior on glyphScale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

                readonly property real fitWidth: Math.round(Math.min(1100, Math.max(560, natural * fitScale + 200)))

                width: fitWidth
                Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                height: 104
                anchors.horizontalCenter: parent.horizontalCenter
                y: prompt.cy + 124 - height / 2
                visible: !prompt.noPassword
                enabled: !graceLockTimer.running

                // The full stop, read at its full size here (22 high), once for all of them.
                Image {
                    id: dotSize
                    visible: false
                    source: lockScreenUi.art + lockScreenUi.kit.dot
                    sourceSize.height: 22
                }
                // The shown password at full size, to measure it.
                Text {
                    id: shownSize
                    visible: false
                    font.family: perpetua.name
                    font.pixelSize: 32
                    font.letterSpacing: 2.5
                    text: prompt.showPassword ? passwordBox.text : ""
                }

                QQC2.TextField {
                    id: passwordBox
                    objectName: "passwordBox"
                    anchors.fill: parent
                    anchors.rightMargin: eyes.width
                    opacity: 0
                    echoMode: TextInput.Password
                    text: lockScreenUi.locker.passwordSync.password
                    focus: true
                    enabled: !lockScreenUi.locker.graceLocked
                    // As in Plasma's: the field is how a key wakes the prompt; no blinking cursor.
                    cursorVisible: false
                    Accessible.name: lockScreenUi.tr("@info:placeholder in text field", "Password")

                    onAccepted: {
                        if (lockScreenRoot.uiVisible) {
                            prompt.startLogin();
                        }
                    }
                    // A key wakes the prompt and is typed as well: the field takes the keys it
                    // types, so lockScreenRoot only hears the others (Escape among them). Tab
                    // goes on to the eyes and the menu.
                    Keys.onPressed: event => {
                        if (event.key !== Qt.Key_Escape) {
                            lockScreenRoot.uiVisible = true;
                        }
                        if (event.key === Qt.Key_Tab) {
                            eyes.forceActiveFocus(Qt.TabFocusReason);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backtab) {
                            (switchItem.visible ? switchItem : eyes).forceActiveFocus(Qt.BacktabFocusReason);
                            event.accepted = true;
                        } else {
                            event.accepted = false;
                        }
                    }

                    Connections {
                        target: lockScreenUi
                        function onClearPassword() {
                            passwordBox.forceActiveFocus()
                            passwordBox.text = "";
                            passwordBox.text = Qt.binding(() => lockScreenUi.locker.passwordSync.password);
                        }
                        function onNotificationRepeated() {
                            message.retype();
                        }
                    }
                }
                Binding {
                    target: lockScreenUi.locker.passwordSync
                    property: "password"
                    value: passwordBox.text
                }

                // Sized and placed for where the field is going, so that it doesn't seem to overflow
                // while the field widens.
                Item {
                    id: glyphs
                    objectName: "glyphs"
                    readonly property bool overflowing: entry.natural * entry.fitScale > width + 0.5
                    x: (entry.width - width) / 2
                    width: entry.fitWidth - 200
                    y: 20 - height / 2
                    height: 60
                    clip: overflowing
                    visible: entry.count > 0
                    // Past the field's widest, the first ones fade out at the left.
                    layer.enabled: overflowing && !lockScreenUi.softwareRendering
                    layer.effect: GE.OpacityMask {
                        maskSource: glyphsFade
                    }

                    Row {
                        id: dots
                        visible: !prompt.showPassword
                        x: glyphs.overflowing ? glyphs.width - width : (glyphs.width - width) / 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12 * entry.glyphScale
                        Repeater {
                            model: prompt.showPassword ? 0 : entry.count
                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                source: lockScreenUi.art + lockScreenUi.kit.dot
                                sourceSize.height: 22
                                width: entry.dotWidth * entry.glyphScale
                                height: 22 * entry.glyphScale
                                smooth: true
                            }
                        }
                    }
                    Text {
                        id: shownText
                        visible: prompt.showPassword
                        x: glyphs.overflowing ? glyphs.width - width : (glyphs.width - width) / 2
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: perpetua.name
                        font.pixelSize: 32 * entry.glyphScale
                        font.letterSpacing: 2.5 * entry.glyphScale
                        color: lockScreenUi.ink
                        text: prompt.showPassword ? passwordBox.text : ""
                    }
                }
                Rectangle {
                    id: glyphsFade
                    width: glyphs.width
                    height: glyphs.height
                    visible: false
                    layer.enabled: glyphs.layer.enabled
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 56 / glyphsFade.width; color: "black" }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 20 - height / 2
                    visible: entry.count === 0
                    font.family: perpetua.name
                    font.italic: true
                    font.pixelSize: 28
                    color: Qt.rgba(0.95, 0.93, 0.89, 0.62)
                    text: lockScreenUi.tr("@info:placeholder in text field", "Password")
                }

                // The inventory's hairline, as wide as the field less the eyes' room, opening from
                // its centre with the fleurs.
                Image {
                    id: hairline
                    property real open: 1
                    function play() {
                        opening.restart();
                    }
                    source: lockScreenUi.art + lockScreenUi.kit.hairline
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 53
                    width: entry.width - 78
                    height: 2
                    smooth: true
                    transform: Scale {
                        origin.x: hairline.width / 2
                        xScale: hairline.open
                    }
                    NumberAnimation {
                        id: opening
                        target: hairline
                        property: "open"
                        from: 0
                        to: 1
                        duration: 340
                        easing.type: Easing.OutQuad
                    }
                }

                // The eyes: half-closed while the password is hidden, open while it shows.
                Item {
                    id: eyes
                    objectName: "eyes"
                    width: 84
                    height: 48
                    anchors.right: parent.right
                    anchors.rightMargin: -6
                    y: 20 - height / 2
                    activeFocusOnTab: true
                    KeyNavigation.tab: sleepItem
                    KeyNavigation.backtab: passwordBox
                    Accessible.role: Accessible.CheckBox
                    Accessible.checked: prompt.showPassword
                    Accessible.name: prompt.showPassword ? lockScreenUi.tr("@action:button", "Hide password") : lockScreenUi.tr("@action:button", "Show password")
                    function toggle() {
                        prompt.showPassword = !prompt.showPassword;
                        passwordBox.forceActiveFocus();
                    }
                    Keys.onSpacePressed: toggle()
                    Keys.onReturnPressed: toggle()
                    Image {
                        anchors.centerIn: parent
                        width: 74
                        fillMode: Image.PreserveAspectFit
                        source: lockScreenUi.art + (prompt.showPassword ? lockScreenUi.kit.eyesOpen : lockScreenUi.kit.eyesLidded)
                        opacity: eyesMouse.containsMouse || eyes.activeFocus ? 1 : 0.85
                    }
                    MouseArea {
                        id: eyesMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: eyes.toggle()
                    }
                }
            }

            // Without a password (an account that has none), a single menu item unlocks.
            GameItem {
                id: unlockButton
                visible: prompt.noPassword
                anchors.horizontalCenter: parent.horizontalCenter
                y: prompt.cy + 104 - height / 2
                text: lockScreenUi.tr("@action:button no-password unlock", "Unlock")
                onClicked: lockScreenUi.locker.unlock()
            }

            function startLogin() {
                const password = passwordBox.text
                // As in Plasma's: focus off the field before the app may close (QTBUG-55460).
                eyes.forceActiveFocus();
                lockScreenUi.locker.respond(password);
            }

            // Under the hairline: Caps Lock and the lock screen's messages, written out as dialogue
            // is and ended with Hornet's needle, and the fingerprint and smartcard readers' hints
            // as Plasma's prompt lists them. The weaver's fleur moves down to let them in.
            Column {
                id: slot
                objectName: "slot"
                width: parent.width
                y: prompt.cy + 172 - message.height / 2
                spacing: 6

                Row {
                    id: message
                    readonly property string full: {
                        const parts = [];
                        if (lockScreenUi.locker.capsLock) {
                            parts.push(lockScreenUi.tr("@info:status", "Caps Lock is on"));
                        }
                        if (lockScreenUi.notification) {
                            parts.push(lockScreenUi.notification);
                        }
                        return parts.join(" • ");
                    }
                    property int shown: full.length
                    function retype() {
                        shown = 0;
                        typing.restart();
                    }
                    onFullChanged: retype()
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10
                    visible: full.length > 0
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: perpetua.name
                        font.italic: lockScreenUi.locker.capsLock && !lockScreenUi.notification
                        font.pixelSize: 30
                        color: lockScreenUi.locker.capsLock && !lockScreenUi.notification ? "#edd3ae" : lockScreenUi.ink
                        text: message.full.substring(0, message.shown)
                    }
                    // Hornet's needle, as at the end of her lines, bobbing.
                    Image {
                        id: needle
                        property int frame: lockScreenUi.kit.needle.length - 1
                        anchors.verticalCenter: parent.verticalCenter
                        visible: message.shown >= message.full.length
                        source: lockScreenUi.art + lockScreenUi.kit.needle[frame]
                        sourceSize.height: 36
                        height: 36
                        width: 9
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        onVisibleChanged: {
                            if (visible) {
                                frame = 0;
                                needleFrames.restart();
                            }
                        }
                        Timer {
                            id: needleFrames
                            interval: 42
                            repeat: true
                            onTriggered: {
                                if (needle.frame < lockScreenUi.kit.needle.length - 1) {
                                    needle.frame++;
                                } else {
                                    stop();
                                }
                            }
                        }
                        transform: Translate {
                            id: bob
                        }
                        SequentialAnimation {
                            running: needle.visible && prompt.visible
                            loops: Animation.Infinite
                            NumberAnimation { target: bob; property: "y"; from: -3; to: 4; duration: 550; easing.type: Easing.InOutSine }
                            NumberAnimation { target: bob; property: "y"; from: 4; to: -3; duration: 550; easing.type: Easing.InOutSine }
                        }
                    }
                    Timer {
                        id: typing
                        interval: 28
                        repeat: true
                        onTriggered: {
                            if (message.shown < message.full.length) {
                                message.shown++;
                            } else {
                                stop();
                            }
                        }
                    }
                }

                Repeater {
                    model: lockScreenUi.locker.readers
                    FailableLabel {
                        required property var modelData
                        kind: modelData.kind
                        label: modelData.label
                    }
                }
            }

            // The weaver's fleur closes the column: 34 under the hairline, or under what the slot
            // holds (60: the gap, and half the fleur's height).
            Item {
                id: bottomLine
                objectName: "bottomFleur"
                width: parent.width
                y: slot.height > 0 ? slot.y + slot.height + 60 : prompt.cy + 192
                Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                Fleur {
                    id: bottomFleur
                    frames: lockScreenUi.kit.fleurBottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: -height / 2
                }
            }

            Loader {
                anchors.horizontalCenter: parent.horizontalCenter
                y: bottomLine.y + 56
                width: 480
                source: lockScreenUi.locker.mediaControls
            }

            Row {
                id: menuRow
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 110 - height / 2
                spacing: 28
                GameItem {
                    id: sleepItem
                    KeyNavigation.tab: switchItem
                    KeyNavigation.backtab: eyes
                    text: lockScreenUi.tr("@action:button", "Slee&p")
                    visible: lockScreenUi.locker.canSuspend
                    onClicked: lockScreenUi.locker.suspend()
                }
                GameItem {
                    id: switchItem
                    KeyNavigation.tab: passwordBox
                    KeyNavigation.backtab: sleepItem
                    text: lockScreenUi.tr("@action:button", "Switch &User")
                    visible: lockScreenUi.locker.canSwitchUser
                    onClicked: lockScreenUi.locker.switchUser()
                }
            }

            // Plasma's footer, in the game's type and on the menu's line: the keyboard layout (only
            // with more than one) and the battery, 72 from the sides.
            GameItem {
                id: layoutButton
                anchors.left: parent.left
                anchors.leftMargin: 72 - 46
                anchors.verticalCenter: menuRow.verticalCenter
                visible: lockScreenUi.locker.layoutName !== ""
                text: lockScreenUi.locker.layoutName
                Accessible.description: lockScreenUi.tr("Button to change keyboard layout", "Switch layout")
                onClicked: lockScreenUi.locker.switchLayout()
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 72
                anchors.verticalCenter: menuRow.verticalCenter
                visible: lockScreenUi.locker.batteryText !== ""
                font.family: trajan.name
                font.pixelSize: 20
                font.letterSpacing: 2
                color: Qt.rgba(0.95, 0.93, 0.89, 0.8)
                text: lockScreenUi.locker.batteryText
                Accessible.name: lockScreenUi.locker.batteryName
            }
        }

        Loader {
            z: 2
            source: lockScreenUi.locker.osd
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: lockScreenUi.osdMargin
            }
        }

        PropertyAnimation {
            id: launchAnimation
            target: lockScreenRoot
            property: "opacity"
            from: 0
            to: 1
            duration: lockScreenUi.veryLongDuration * 2
        }

        Component.onCompleted: launchAnimation.start();
    }
}
