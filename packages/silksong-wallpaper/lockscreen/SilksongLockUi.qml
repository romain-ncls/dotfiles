/*
    SPDX-FileCopyrightText: 2014 Aleix Pol Gonzalez <aleixpol@blue-systems.com>
    SPDX-FileCopyrightText: 2016 David Edmundson <davidedmundson@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Plasma 6.7's LockScreenUi.qml and MainBlock.qml with the game's look: the pause menu's column
// between Hornet's dialogue fleur and the weaver's prompt fleur, the full stops the game ends
// other characters' lines with for the characters typed, the inventory's hairline under them,
// messages written out as dialogue and ended with Hornet's needle, Sleep and Switch User as menu
// items, and the aquarium behind darkened and blurred while the prompt is up. What it does is
// Plasma's: the same authenticator calls, messages, timers and keys. The art comes from root.kit
// (ui/Kit.qml, tools/extract_ui.py).

import QtQml
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Effects
import Qt5Compat.GraphicalEffects as GE

import org.kde.kirigami as Kirigami
import org.kde.kscreenlocker as ScreenLocker
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.plasma.private.sessions
import org.kde.plasma.private.battery
import org.kde.plasma.workspace.components as PW
import org.kde.breeze.components

Item {
    id: lockScreenUi

    // Effects need the GPU; with software rendering, the veil alone.
    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software
    readonly property QtObject kit: root.kit
    readonly property url art: root.uiDir
    readonly property color ink: "#f3ece2"

    function tr(context, text) {
        return (typeof i18ndc === "function" ? i18ndc("plasma_shell_org.kde.plasma.desktop", context, text) : text).replace("&", "");
    }

    function handleMessage(msg) {
        if (!root.notification) {
            root.notification += msg;
        } else if (root.notification.includes(msg)) {
            root.notificationRepeated();
        } else {
            root.notification += "\n" + msg
        }
    }

    Connections {
        target: authenticator
        function onFailed(kind) {
            if (kind != 0) { // if this is coming from the noninteractive authenticators
                return;
            }
            const msg = lockScreenUi.tr("@info:status", "Unlocking failed");
            lockScreenUi.handleMessage(msg);
            graceLockTimer.restart();
            notificationRemoveTimer.restart();
            rejectPasswordAnimation.start();
        }

        function onSucceeded() {
            if (authenticator.hadPrompt) {
                Qt.quit();
            } else {
                prompt.noPassword = true;
                unlockButton.forceActiveFocus();
            }
        }

        function onInfoMessageChanged() {
            lockScreenUi.handleMessage(authenticator.infoMessage);
        }

        function onErrorMessageChanged() {
            lockScreenUi.handleMessage(authenticator.errorMessage);
        }

        function onPromptChanged(msg) {
            lockScreenUi.handleMessage(authenticator.prompt);
        }
        function onPromptForSecretChanged(msg) {
            prompt.showPassword = false;
            passwordBox.forceActiveFocus();
        }
    }

    SessionManagement {
        id: sessionManagement
    }

    KeyboardIndicator.KeyState {
        id: capsLockState
        key: Qt.Key_CapsLock
    }

    Connections {
        target: sessionManagement
        function onAboutToSuspend() {
            root.clearPassword();
        }
    }

    RejectPasswordAnimation {
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

        visible: authenticator.authenticatorTypes & kind
        text: label
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        font.family: perpetua.name
        font.italic: true
        font.pixelSize: 24
        color: Qt.rgba(0.95, 0.93, 0.89, 0.8)

        RejectPasswordAnimation {
            id: _rejectAnimation
            target: _failableLabel
            onFinished: _timer.restart()
        }

        Connections {
            target: authenticator
            function onNoninteractiveError(kind, authenticator) {
                if (kind & _failableLabel.kind) {
                    _failableLabel.text = Qt.binding(() => authenticator.errorMessage)
                    _rejectAnimation.start()
                }
            }
        }
        Timer {
            id: _timer
            interval: Kirigami.Units.humanMoment
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
            authenticator.startAuthenticating();
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
            // If the escape key is pressed, kscreenlocker will turn off the screen.
            // We do not want to show the password prompt in this case.
            if (uiVisible) {
                uiVisible = false;
                root.clearPassword();
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
            onTriggered: root.notification = ""
        }
        Timer {
            id: graceLockTimer
            interval: 3000
            onTriggered: {
                root.clearPassword();
                authenticator.startAuthenticating();
            }
        }

        // 0 while the aquarium is alone, 1 under the prompt: what's behind it darkens and blurs
        // over the same time as Plasma's.
        property real factor: uiVisible ? 1 : 0
        Behavior on factor {
            NumberAnimation {
                duration: Kirigami.Units.veryLongDuration * 2
                easing.type: Easing.InOutQuad
            }
        }

        // Made only while it shows: a blur kept ready would redraw the aquarium twice all along.
        Loader {
            anchors.fill: parent
            active: !lockScreenUi.softwareRendering && lockScreenRoot.factor > 0
            sourceComponent: MultiEffect {
                source: wallpaper
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
                    duration: Kirigami.Units.veryLongDuration
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
                text: root.userName
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
                    text: PasswordSync.password
                    focus: true
                    enabled: !authenticator.graceLocked
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
                        target: root
                        function onClearPassword() {
                            passwordBox.forceActiveFocus()
                            passwordBox.text = "";
                            passwordBox.text = Qt.binding(() => PasswordSync.password);
                        }
                        function onNotificationRepeated() {
                            message.retype();
                        }
                    }
                }
                Binding {
                    target: PasswordSync
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
                onClicked: Qt.quit()
            }

            function startLogin() {
                const password = passwordBox.text
                // As in Plasma's: focus off the field before the app may close (QTBUG-55460).
                eyes.forceActiveFocus();
                authenticator.respond(password);
            }

            // Under the hairline: Caps Lock and the authenticator's messages, written out as dialogue
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
                        if (capsLockState.locked) {
                            parts.push(lockScreenUi.tr("@info:status", "Caps Lock is on"));
                        }
                        if (root.notification) {
                            parts.push(root.notification);
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
                        font.italic: capsLockState.locked && !root.notification
                        font.pixelSize: 30
                        color: capsLockState.locked && !root.notification ? "#edd3ae" : lockScreenUi.ink
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

                FailableLabel {
                    kind: ScreenLocker.Authenticator.Fingerprint
                    label: lockScreenUi.tr("@info:usagetip", "(or scan your fingerprint on the reader)")
                }
                FailableLabel {
                    kind: ScreenLocker.Authenticator.Smartcard
                    label: lockScreenUi.tr("@info:usagetip", "(or scan your smartcard)")
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
                active: config.showMediaControls
                source: "MediaControls.qml"
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
                    visible: sessionManagement.canSuspend
                    onClicked: sessionManagement.suspend()
                }
                GameItem {
                    id: switchItem
                    KeyNavigation.tab: passwordBox
                    KeyNavigation.backtab: sleepItem
                    text: lockScreenUi.tr("@action:button", "Switch &User")
                    visible: sessionManagement.canSwitchUser
                    onClicked: sessionManagement.switchUser()
                }
            }

            // Plasma's footer, in the game's type and on the menu's line: the keyboard layout (only
            // with more than one) and the battery, 72 from the sides.
            GameItem {
                id: layoutButton
                anchors.left: parent.left
                anchors.leftMargin: 72 - 46
                anchors.verticalCenter: menuRow.verticalCenter
                visible: keyboardLayoutSwitcher.hasMultipleKeyboardLayouts
                text: keyboardLayoutSwitcher.layoutNames.shortName ?? ""
                Accessible.description: lockScreenUi.tr("Button to change keyboard layout", "Switch layout")
                onClicked: keyboardLayoutSwitcher.keyboardLayout.switchToNextLayout()
                PW.KeyboardLayoutSwitcher {
                    id: keyboardLayoutSwitcher
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                }
            }
            Text {
                BatteryControlModel {
                    id: batteryControl
                }
                anchors.right: parent.right
                anchors.rightMargin: 72
                anchors.verticalCenter: menuRow.verticalCenter
                visible: batteryControl.hasInternalBatteries
                font.family: trajan.name
                font.pixelSize: 20
                font.letterSpacing: 2
                color: Qt.rgba(0.95, 0.93, 0.89, 0.8)
                text: typeof i18nd === "function" ? i18nd("plasma_lookandfeel_org.kde.lookandfeel", "%1%", batteryControl.percent) : batteryControl.percent + "%"
                Accessible.name: typeof i18nd === "function" ? i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Battery at %1%", batteryControl.percent) : text
            }
        }

        Loader {
            z: 2
            active: root.viewVisible
            source: "LockOsd.qml"
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: Kirigami.Units.gridUnit
            }
        }

        PropertyAnimation {
            id: launchAnimation
            target: lockScreenRoot
            property: "opacity"
            from: 0
            to: 1
            duration: Kirigami.Units.veryLongDuration * 2
        }

        Component.onCompleted: launchAnimation.start();
    }
}
