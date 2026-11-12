pragma ComponentBehavior: Bound
import QtQuick
import qs.Ui
import "../velunori.core/kit" as V
import "." as Local

Item {
    id: root
    property var bar: null
    property var settings: ({})
    property string moduleName: "velunori.update"
    readonly property var backend: Local.Runtime.backend
    readonly property string view: backend ? backend.view : "uptodate"
    readonly property bool busy: !!backend && backend.running
    // Hidden while there is nothing to do, like the indicator it replaces.
    readonly property bool wanted: view === "available" || view === "failed" || busy
    onBusyChanged: if (!busy) glyph.rotation = 0
    visible: wanted
    implicitWidth: wanted ? 34 : 0
    implicitHeight: bar ? bar.barSize : 40
    V.Theme { id: theme; bar: root.bar }
    WidgetButton {
        anchors.fill: parent; bar: root.bar; labelVisible: false; hasVisualContent: true
        active: !!root.backend && root.backend.windowOpen
        tooltipText: root.busy ? "Updating… " + (root.backend.run.percent || 0) + "%"
            : root.view === "failed" ? "The last update did not finish"
            : root.backend ? root.backend.updates.length + " updates available" : "Updates"
        onPressed: function(button) {
            if (button !== Qt.LeftButton || !root.backend) return;
            if (root.backend.windowOpen) root.backend.hide(); else root.backend.show();
        }
        Canvas {
            id: glyph
            anchors.centerIn: parent; width: 18; height: 18
            property color ink: root.view === "failed" ? "#f0a0a8" : theme.accent
            onInkChanged: requestPaint()
            RotationAnimation on rotation { from: 0; to: 360; duration: 1400; loops: Animation.Infinite; running: root.busy && theme.motion && root.visible }
            onPaint: {
                var c = getContext("2d"); c.reset(); c.strokeStyle = ink; c.lineWidth = 1.5; c.lineCap = "round"; c.lineJoin = "round";
                c.beginPath(); c.arc(9, 9, 5.5, Math.PI * 1.15, Math.PI * 1.95); c.stroke();
                c.beginPath(); c.arc(9, 9, 5.5, Math.PI * 0.15, Math.PI * 0.95); c.stroke();
                c.beginPath(); c.moveTo(14.6, 4.2); c.lineTo(14.4, 7.6); c.lineTo(11.2, 6.6); c.stroke();
                c.beginPath(); c.moveTo(3.4, 13.8); c.lineTo(3.6, 10.4); c.lineTo(6.8, 11.4); c.stroke();
            }
        }
    }
}
