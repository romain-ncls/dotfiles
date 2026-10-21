/*
 * Backdrop wallpaper: shows the picture the backdrop daemon publishes as the
 * only file in ~/.local/share/backdrop/current, with like/dislike in the
 * desktop context menu.
 *
 * The lock screen greeter loads this file too. It cannot host QtWidgets (a
 * KIO SSL dialog raised there is what crashed the PoTD wallpaper), so this
 * file only reads a local file: talking to the daemon is left to
 * Backend.qml, which only plasmashell loads.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Window
import QtCore
import Qt.labs.folderlistmodel

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

WallpaperItem {
    id: root

    // plasmashell rather than the lock screen greeter.
    readonly property bool interactive: Qt.application.name.indexOf("plasmashell") !== -1
    property string imageUrl
    property var info: ({})

    contextualActions: interactive ? [likeAction, dislikeAction, nextAction, aboutAction, openAction] : []

    function showCurrent() {
        // Sorted newest first: while the daemon swaps pictures the folder
        // briefly holds both.
        const url = currentFolder.count > 0 ? "file://" + currentFolder.get(0, "filePath") : "";
        if (url === imageUrl) {
            return;
        }
        imageUrl = url;
        imageView.loadImage();
        refreshInfo();
    }

    function refreshInfo() {
        backend.item?.run("info --json", stdout => {
            try {
                root.info = JSON.parse(stdout);
            } catch (e) {
                root.info = {};
            }
        });
    }

    function command(verb) {
        backend.item?.run(verb, () => root.refreshInfo());
    }

    PlasmaCore.Action {
        id: likeAction
        text: root.info.liked ? "Liked" : root.info.title ? `Like “${root.info.title}”` : "Like This Wallpaper"
        icon.name: "love"
        enabled: !!root.info.id && !root.info.liked
        onTriggered: root.command("like")
    }
    PlasmaCore.Action {
        id: dislikeAction
        text: "Dislike and Show Another"
        icon.name: "dialog-cancel"
        enabled: !!root.info.id
        onTriggered: root.command("dislike")
    }
    PlasmaCore.Action {
        id: nextAction
        text: "Next Wallpaper"
        icon.name: "go-next-skip"
        onTriggered: root.command("next")
    }
    PlasmaCore.Action {
        id: aboutAction
        text: root.info.title ? `About “${root.info.title}”` : "About This Wallpaper"
        icon.name: "help-about-symbolic"
        visible: !!root.info.infoUrl
        onTriggered: Qt.openUrlExternally(root.info.infoUrl)
    }
    PlasmaCore.Action {
        id: openAction
        text: "Open Wallpaper Image"
        icon.name: "document-open"
        visible: root.imageUrl !== ""
        onTriggered: Qt.openUrlExternally(root.imageUrl)
    }

    FolderListModel {
        id: currentFolder
        folder: StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/backdrop/current"
        nameFilters: ["*.jpg", "*.jpeg", "*.png"]
        showDirs: false
        sortField: FolderListModel.Time

        // The swap can land in a single rescan that keeps count at 1.
        onCountChanged: Qt.callLater(root.showCurrent)
        onRowsInserted: Qt.callLater(root.showCurrent)
        onRowsRemoved: Qt.callLater(root.showCurrent)
        onDataChanged: Qt.callLater(root.showCurrent)
        onModelReset: Qt.callLater(root.showCurrent)
        onStatusChanged: Qt.callLater(root.showCurrent)
    }

    Loader {
        id: backend
        active: root.interactive
        source: Qt.resolvedUrl("Backend.qml")
        onLoaded: root.refreshInfo()
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    // Cross-fades between pictures, as the PoTD wallpaper does.
    QQC2.StackView {
        id: imageView
        anchors.fill: parent

        readonly property int fillMode: root.configuration.FillMode
        readonly property size sourceSize: Qt.size(imageView.width * Screen.devicePixelRatio, imageView.height * Screen.devicePixelRatio)
        property Item pendingImage
        property bool doesSkipAnimation: true

        onFillModeChanged: Qt.callLater(imageView.loadImage)
        onSourceSizeChanged: Qt.callLater(imageView.loadImage)

        function loadImage() {
            if (root.imageUrl === "") {
                return;
            }
            if (imageView.pendingImage) {
                imageView.pendingImage.statusChanged.disconnect(imageView.replaceWhenLoaded);
                imageView.pendingImage.destroy();
                imageView.pendingImage = null;
            }
            imageView.doesSkipAnimation = imageView.empty || sourceSize !== imageView.currentItem.sourceSize;
            imageView.pendingImage = imageComponent.createObject(imageView, {
                "source": root.imageUrl,
                "fillMode": imageView.fillMode,
                "opacity": imageView.doesSkipAnimation ? 1 : 0,
                "sourceSize": imageView.sourceSize,
                "width": imageView.width,
                "height": imageView.height,
            });
            imageView.pendingImage.statusChanged.connect(imageView.replaceWhenLoaded);
            imageView.replaceWhenLoaded();
        }

        function replaceWhenLoaded() {
            const image = imageView.pendingImage;
            if (image.status === Image.Loading) {
                return;
            }
            image.statusChanged.disconnect(imageView.replaceWhenLoaded);
            imageView.pendingImage = null;
            if (image.status !== Image.Ready) {
                image.destroy(); // keep showing the previous picture
                return;
            }
            imageView.replace(image, {}, imageView.doesSkipAnimation ? QQC2.StackView.Immediate : QQC2.StackView.Transition);
        }

        Component {
            id: imageComponent

            Image {
                asynchronous: true
                cache: false
                autoTransform: true
                smooth: true

                QQC2.StackView.onActivated: root.accentColorChanged()
                QQC2.StackView.onDeactivated: destroy()
                QQC2.StackView.onRemoved: destroy()
            }
        }

        replaceEnter: Transition {
            OpacityAnimator {
                id: replaceEnterOpacityAnimator
                to: 1
                duration: Math.round(Kirigami.Units.veryLongDuration * 3)
            }
        }
        // Keep the old picture until the new one has faded in, so the black
        // background never shows through.
        replaceExit: Transition {
            PauseAnimation {
                duration: replaceEnterOpacityAnimator.duration + 500
            }
        }
    }

    Component.onCompleted: showCurrent()
}
