import QtQuick

// A ring that fills with progress, or circles while the amount is unknown.
Item {
    id: root
    property real value: 0
    property bool indeterminate: false
    property bool motion: true
    property color color: "#c4aff1"
    property color track: "#37363f"
    property real lineWidth: 7
    property real shown: value
    property real spin: 0
    default property alias content: holder.data
    implicitWidth: 112; implicitHeight: 112

    Behavior on shown { enabled: root.motion; NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
    onValueChanged: shown = value
    NumberAnimation on spin { from: 0; to: 1; duration: 1300; loops: Animation.Infinite; running: root.indeterminate && root.motion && root.visible }

    onShownChanged: canvas.requestPaint()
    onSpinChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()
    onIndeterminateChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            var c = getContext("2d"); c.reset();
            var r = Math.min(width, height) / 2 - root.lineWidth / 2 - 1, cx = width / 2, cy = height / 2;
            c.lineWidth = root.lineWidth; c.lineCap = "round";
            c.strokeStyle = root.track; c.beginPath(); c.arc(cx, cy, r, 0, Math.PI * 2); c.stroke();
            var from = -Math.PI / 2, sweep = Math.PI * 2 * Math.max(0, Math.min(1, root.shown));
            if (root.indeterminate) { from += Math.PI * 2 * root.spin; sweep = Math.PI * 0.6; }
            if (sweep <= 0.001) return;
            c.strokeStyle = root.color; c.beginPath(); c.arc(cx, cy, r, from, from + sweep); c.stroke();
        }
    }
    Item { id: holder; anchors.fill: parent }
}
