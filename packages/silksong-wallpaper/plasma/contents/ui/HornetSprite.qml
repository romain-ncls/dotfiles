import QtQuick

// Hornet's current frame, drawn with her anchor at this item's origin (her feet). One set of
// sheets serves every zone: she is coloured for the zone she's in on the GPU
// (shaders/hornet.frag), so crossing into another zone costs nothing.
Item {
    id: sprite

    required property var sheet // the clip's Sprites.qml entry
    required property Image texture // that clip's sheet, loaded
    required property var grade // the zone's colours (World.qml zones[].grade)
    required property Image lut // the zone's camera curves, loaded
    property int frame: 0
    property bool mirrored: false
    property real pixelScale: 1 // screen pixels per sheet pixel

    readonly property int cell: sheet.sequence[Math.min(frame, sheet.frames - 1)]
    readonly property int rows: Math.ceil((Math.max.apply(null, sheet.sequence) + 1) / sheet.columns)
    readonly property bool shaded: GraphicsInfo.api !== GraphicsInfo.Software
    readonly property bool ready: texture !== null && lut !== null

    transform: Scale {
        xScale: sprite.mirrored ? -1 : 1
    }

    Item {
        x: -sprite.sheet.anchorX * sprite.pixelScale
        y: -sprite.sheet.anchorY * sprite.pixelScale
        width: sprite.sheet.cellWidth * sprite.pixelScale
        height: sprite.sheet.cellHeight * sprite.pixelScale
        clip: !sprite.shaded

        // Stand-ins while her sheet or the zone's curves are still loading.
        Image {
            id: nothing
            visible: false
        }

        ShaderEffect {
            visible: sprite.shaded && sprite.ready
            anchors.fill: parent

            readonly property Image source: sprite.texture ?? nothing
            readonly property Image lut: sprite.lut ?? nothing
            readonly property vector4d cell: Qt.vector4d((sprite.cell % sprite.sheet.columns) / sprite.sheet.columns,
                                                         Math.floor(sprite.cell / sprite.sheet.columns) / sprite.rows,
                                                         1 / sprite.sheet.columns, 1 / sprite.rows)
            readonly property vector4d ambient: Qt.vector4d(sprite.grade.ambient[0], sprite.grade.ambient[1],
                                                            sprite.grade.ambient[2], 1)
            readonly property real heroSaturation: sprite.grade.heroSaturation
            readonly property real saturation: sprite.grade.saturation

            fragmentShader: Qt.resolvedUrl("shaders/hornet.frag.qsb")
        }

        // Without a GPU (the software renderer of tools/preview.qml) she keeps the sheets' colours.
        Image {
            visible: !sprite.shaded && sprite.ready
            source: visible ? sprite.texture.source : ""
            sourceSize: visible ? sprite.texture.sourceSize : Qt.size(0, 0)
            x: -(sprite.cell % sprite.sheet.columns) * parent.width
            y: -Math.floor(sprite.cell / sprite.sheet.columns) * parent.height
            width: parent.width * sprite.sheet.columns
            height: parent.height * sprite.rows
            smooth: true
        }
    }
}
