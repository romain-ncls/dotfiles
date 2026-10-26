import QtQuick

// One frame of an extracted clip, drawn with the sprite's anchor at this
// item's origin, so placing the item places the character's feet.
Item {
    id: sprite

    required property var sheet // a Sprites.qml manifest entry
    required property url dataDir
    property int frame: 0
    property bool mirrored: false
    property real pixelScale: 1 // screen pixels per sheet pixel

    readonly property int cell: sheet.sequence[Math.min(frame, sheet.frames - 1)]

    transform: Scale {
        xScale: sprite.mirrored ? -1 : 1
    }

    Item {
        x: -sprite.sheet.anchorX * sprite.pixelScale
        y: -sprite.sheet.anchorY * sprite.pixelScale
        width: sprite.sheet.cellWidth * sprite.pixelScale
        height: sprite.sheet.cellHeight * sprite.pixelScale
        clip: true

        Image {
            source: sprite.dataDir + "/" + sprite.sheet.file
            x: -(sprite.cell % sprite.sheet.columns) * sprite.sheet.cellWidth * sprite.pixelScale
            y: -Math.floor(sprite.cell / sprite.sheet.columns) * sprite.sheet.cellHeight * sprite.pixelScale
            width: implicitWidth * sprite.pixelScale
            height: implicitHeight * sprite.pixelScale
            smooth: true
            mipmap: true
        }
    }
}
