import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "." as Local
import "components"
import "../lib/kit" as V

Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property var shell: null
  property var manifest: null
  property bool opened: false
  property real openProgress: 1

  V.Theme {
    id: tokens
    readonly property var settings: root.shell && root.shell.barConfig && root.shell.barConfig.velunori ? root.shell.barConfig.velunori : ({})
    bar: ({velunori: {apiVersion: 1, accentName: settings.accent || "lavender", motion: settings.motion !== false}})
  }

  function open(payloadJson) {
    root.opened = true
    Local.Runtime.windowOpen = true
    Qt.callLater(function() { view.takeFocus() })
  }

  function close() {
    root.opened = false
    Local.Runtime.windowOpen = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide("velunori.update")
  }

  Component.onDestruction: Local.Runtime.windowOpen = false

  NumberAnimation { id: openAnim; target: root; property: "openProgress"; from: 0; to: 1; duration: 150; easing.type: Easing.OutCubic }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "velunori-update"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    onVisibleChanged: if (visible) { openAnim.stop(); root.openProgress = 1; if (tokens.motion) openAnim.start() }

    Rectangle { anchors.fill: parent; color: Commons.Color.menu.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    Rectangle {
      id: card
      width: Math.min(view.implicitWidth, panel.width - Style.gapsOut * 2)
      height: Math.min(view.implicitHeight, panel.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      radius: tokens.radius
      color: tokens.background
      border.color: tokens.border
      opacity: root.openProgress
      scale: 0.97 + 0.03 * root.openProgress
      clip: true

      MouseArea { anchors.fill: parent; onClicked: {} }

      UpdateView {
        id: view
        anchors.fill: parent
        anchors.margins: 1
        backend: Local.Runtime.backend
        theme: tokens
        onCloseRequested: root.dismiss()
      }
    }
  }
}
