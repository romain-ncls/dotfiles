/*
    SPDX-FileCopyrightText: 2014 Aleix Pol Gonzalez <aleixpol@blue-systems.com>
    SPDX-FileCopyrightText: 2016 David Edmundson <davidedmundson@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

// The Silksong prompt (SilksongPrompt.qml) on Plasma's lock screen, which LockScreen.qml loads:
// Plasma 6.7's LockScreenUi.qml's plumbing, given to the prompt as its locker. kscreenlocker's
// authenticator, sessions (Sleep, Switch User), Caps Lock, the battery, the keyboard layout, the
// fingerprint and smartcard readers, the media controls and the OSD.

import QtQuick

import org.kde.kirigami as Kirigami
import org.kde.kscreenlocker as ScreenLocker
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.plasma.private.sessions
import org.kde.plasma.private.battery
import org.kde.plasma.workspace.components as PW

SilksongPrompt {
    id: prompt

    kit: root.kit
    art: root.uiDir
    backdrop: wallpaper
    veryLongDuration: Kirigami.Units.veryLongDuration
    humanMoment: Kirigami.Units.humanMoment
    // Breeze's RejectPasswordPathAnimation: its own speed, but none with animations off.
    shakeDuration: Kirigami.Units.longDuration <= 1 ? 1 : 600
    osdMargin: Kirigami.Units.gridUnit

    locker: QtObject {
        id: locker

        signal failed()
        signal succeeded(bool hadPrompt)
        signal message(string text)
        signal askedSecret()
        signal readerFailed(int kind, string text)

        readonly property string userName: root.userName
        readonly property bool capsLock: capsLockState.locked
        readonly property bool graceLocked: authenticator.graceLocked ?? false // gone in Plasma 6.8
        readonly property QtObject passwordSync: PasswordSync
        readonly property bool canSuspend: sessionManagement.canSuspend
        readonly property bool canSwitchUser: sessionManagement.canSwitchUser
        readonly property string layoutName: keyboardLayoutSwitcher.hasMultipleKeyboardLayouts ? keyboardLayoutSwitcher.layoutNames.shortName ?? "" : ""
        readonly property string batteryText: !batteryControl.hasInternalBatteries ? ""
            : typeof i18nd === "function" ? i18nd("plasma_lookandfeel_org.kde.lookandfeel", "%1%", batteryControl.percent) : batteryControl.percent + "%"
        readonly property string batteryName: typeof i18nd === "function" ? i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Battery at %1%", batteryControl.percent) : batteryText
        readonly property int readerKinds: authenticator.authenticatorTypes
        readonly property var readers: [
            { kind: ScreenLocker.Authenticator.Fingerprint, label: prompt.tr("@info:usagetip", "(or scan your fingerprint on the reader)") },
            { kind: ScreenLocker.Authenticator.Smartcard, label: prompt.tr("@info:usagetip", "(or scan your smartcard)") },
        ]
        readonly property url mediaControls: config.showMediaControls ? Qt.resolvedUrl("MediaControls.qml") : ""
        readonly property url osd: root.viewVisible ? Qt.resolvedUrl("LockOsd.qml") : ""

        function start() {
            authenticator.startAuthenticating();
        }
        function respond(password) {
            authenticator.respond(password);
        }
        function unlock() {
            Qt.quit();
        }
        function suspend() {
            sessionManagement.suspend();
        }
        function switchUser() {
            sessionManagement.switchUser();
        }
        function switchLayout() {
            keyboardLayoutSwitcher.keyboardLayout.switchToNextLayout();
        }
    }

    Connections {
        target: authenticator
        function onFailed(kind) {
            if (kind != 0) { // if this is coming from the noninteractive authenticators
                return;
            }
            locker.failed();
        }
        function onSucceeded() {
            locker.succeeded(authenticator.hadPrompt);
        }
        function onInfoMessageChanged() {
            locker.message(authenticator.infoMessage);
        }
        function onErrorMessageChanged() {
            locker.message(authenticator.errorMessage);
        }
        function onPromptChanged(msg) {
            locker.message(authenticator.prompt);
        }
        function onPromptForSecretChanged(msg) {
            locker.askedSecret();
        }
        function onNoninteractiveError(kind, authenticator) {
            locker.readerFailed(kind, authenticator.errorMessage);
        }
    }

    SessionManagement {
        id: sessionManagement
    }
    Connections {
        target: sessionManagement
        function onAboutToSuspend() {
            prompt.clearPassword();
        }
    }
    Connections {
        target: root
        function onClearPassword() {
            prompt.clearPassword();
        }
    }

    KeyboardIndicator.KeyState {
        id: capsLockState
        key: Qt.Key_CapsLock
    }

    BatteryControlModel {
        id: batteryControl
    }

    // In the layout's button, for the wheel.
    PW.KeyboardLayoutSwitcher {
        id: keyboardLayoutSwitcher
        parent: prompt.layoutArea
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
    }
}
