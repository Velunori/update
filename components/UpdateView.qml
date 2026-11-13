pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../velunori.core/kit" as V
import "../UpdateLogic.js" as Logic

// The whole window content. It only reads `backend` (the service, or a stand-in
// in tests) and calls its start/answer/refresh functions.
Item {
    id: root
    property var backend: null
    property var theme: V.Theme {}
    signal closeRequested()

    readonly property string view: backend ? backend.view : "checking"
    readonly property var check: backend ? backend.check : ({})
    readonly property var run: backend ? backend.run : ({})
    readonly property var updates: check.updates || []
    readonly property var release: check.release || null
    readonly property bool busy: view === "running" || view === "password" || view === "confirm"
    readonly property bool motion: theme.motion
    readonly property color ok: "#a0ddbf"
    readonly property color warn: "#e8c28a"
    readonly property color danger: "#f0a0a8"
    readonly property color hover: "#37363f"
    readonly property var stepNow: Logic.activeStep(run)
    readonly property string question: run.prompt && run.prompt.question ? run.prompt.question : ""
    readonly property bool restartChoice: Logic.restartQuestion(question)
    property int tab: 0
    property bool sent: false
    implicitWidth: 760; implicitHeight: 540
    readonly property bool narrow: width < 620
    readonly property color statusColor: view === "uptodate" ? ok : view === "failed" || view === "error" ? danger : theme.accent
    readonly property string versionTitle: check.omarchy ? "Omarchy " + String(check.omarchy.new).split("-")[0] : check.installed ? "Omarchy " + String(check.installed).split("-")[0] : ""
    readonly property var displaySteps: run.steps && (busy || view === "failed" || (backend && backend.justUpdated)) ? run.steps : [{label:"Snapshot",state:"pending"},{label:"System packages",state:"pending"},{label:"App updates",state:"pending"},{label:"Finish",state:"pending"}]

    function takeFocus() { if (view === "password") password.forceActiveFocus(); else keys.forceActiveFocus(); }
    onViewChanged: {
        sent = false;
        if (view !== "password") password.text = "";
        // Progress is what matters while it runs and when it fails.
        if (view === "running" || view === "failed") tab = 2;
        else if (view === "available" || view === "uptodate") tab = 0;
        Qt.callLater(takeFocus);
    }
    Connections { target: root.backend; function onRunChanged() { if (root.view === "password") root.sent = false; } }

    function submitPassword() {
        if (!backend || sent || password.text.length === 0) return;
        var value = password.text;
        password.text = "";
        sent = true;
        backend.answer({kind: "password", value: value});
    }
    function scrollByWheel(list, event) {
        var delta = event.pixelDelta.y ? event.pixelDelta.y * 3 : event.angleDelta.y / 120 * 180;
        if (!delta) { event.accepted = false; return; }
        list.cancelFlick();
        var minimum = list.originY || 0;
        list.contentY = Math.max(minimum, Math.min(minimum + Math.max(0, list.contentHeight - list.height), list.contentY - delta));
        event.accepted = true;
    }
    function primary() {
        if (!backend) return;
        if (view === "available" || view === "failed") backend.start();
        else if (view === "uptodate" || view === "error") backend.refresh(true);
    }

    readonly property string title: view === "available" ? "Ready to update"
        : view === "running" ? (run.phase === "running" ? "Updating…" : "Starting…")
        : view === "password" ? "Password needed"
        : view === "confirm" ? (restartChoice ? "Restart to finish" : "One question")
        : view === "failed" ? "Update did not finish"
        : view === "checking" ? "Checking for updates…"
        : view === "error" ? "Could not check for updates"
        : backend && backend.justUpdated ? "Update complete" : "System is up to date"
    readonly property string subtitle: {
        if (view === "available") return updates.length + (updates.length === 1 ? " package available" : " packages available");
        if (view === "running") return stepNow ? stepNow.label + (run.detail ? " · " + run.detail : "") : "Getting ready";
        if (view === "password") return run.prompt && run.prompt.retry ? "That password was not accepted. Try again." : "Installing packages needs your password.";
        if (view === "confirm") return question;
        if (view === "failed") return run.interrupted ? "The update was interrupted." : stepNow ? "Stopped during: " + stepNow.label : "See the log for details.";
        if (view === "error") return check.error || "Check your connection and try again.";
        if (view === "checking") return "";
        var parts = [];
        if (check.installed) parts.push("Omarchy " + String(check.installed).split("-")[0]);
        if (check.checkedAt && backend) parts.push("checked " + Logic.ago(backend.now - check.checkedAt));
        return parts.join(" · ");
    }

    Item {
        id: keys
        anchors.fill: parent; focus: true
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.closeRequested(); event.accepted = true; }
            else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right) { root.tab = (root.tab + 1) % 3; event.accepted = true; }
            else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left) { root.tab = (root.tab + 2) % 3; event.accepted = true; }
            else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.view !== "confirm") { root.primary(); event.accepted = true; }
        }
    }

    ColumnLayout {
        anchors.fill: parent; spacing: 0
        RowLayout {
            Layout.fillWidth: true; Layout.margins: 18; spacing: 14
            Text { text: "VELUNORI"; color: root.theme.accent; font.pixelSize: 11; font.letterSpacing: 3 }
            Rectangle { implicitWidth: 1; implicitHeight: 18; color: root.theme.border }
            Text { text: "System update"; color: root.theme.muted; font.pixelSize: 13; Layout.fillWidth: true }
            V.Button { objectName: "updateClose"; text: "✕"; implicitWidth: 28; implicitHeight: 28; accent: root.theme.accent; Accessible.name: "Close update window"; onClicked: root.closeRequested() }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.theme.border }
        ColumnLayout {
            visible: root.narrow
            Layout.fillWidth: true; Layout.margins: 16; spacing: 4
            Text { text: root.title; color: root.theme.text; font.pixelSize: 17; font.weight: Font.DemiBold; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            Text { text: root.subtitle; textFormat: Text.PlainText; color: root.theme.muted; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true; maximumLineCount: 2; elide: Text.ElideRight }
        }
        RowLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0; spacing: 0
            ColumnLayout {
                visible: !root.narrow
                Layout.preferredWidth: 188; Layout.maximumWidth: 188; Layout.fillHeight: true; Layout.margins: 20; spacing: 10
                Rectangle {
                    implicitWidth: 38; implicitHeight: 38; radius: 11; color: root.theme.surface
                    border.color: root.statusColor
                    Text { anchors.centerIn: parent; text: root.view === "uptodate" ? "✓" : root.view === "failed" || root.view === "error" ? "!" : "↻"; color: root.statusColor; font.pixelSize: 26 }
                }
                Text { objectName: "updateTitle"; text: root.title; Layout.fillWidth: true; color: root.theme.text; font.pixelSize: 16; font.weight: Font.Medium; wrapMode: Text.WordWrap }
                Text { text: root.versionTitle; visible: text !== ""; color: root.theme.text; font.pixelSize: 20; font.weight: Font.DemiBold; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                Text { objectName: "updateSubtitle"; text: root.subtitle; textFormat: Text.PlainText; color: root.view === "password" && root.run.prompt && root.run.prompt.retry ? root.warn : root.theme.muted; font.pixelSize: 12; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight; Layout.fillWidth: true }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.theme.border; Layout.topMargin: 6; Layout.bottomMargin: 4 }
                Text { text: root.busy || root.view === "failed" ? "UPDATE PROGRESS" : "UPDATE FLOW"; color: root.theme.muted; font.pixelSize: 10; font.letterSpacing: 1.5 }
                ListView {
                    id: stepList; objectName: "updateSteps"
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0
                    model: root.displaySteps; spacing: 0; clip: true
                    readonly property int activeIndex: root.displaySteps.findIndex(function(step) { return step.state === "active" || step.state === "failed"; })
                    onActiveIndexChanged: Qt.callLater(function() { if (activeIndex >= 0) positionViewAtIndex(activeIndex, ListView.Contain); })
                    boundsBehavior: Flickable.StopAtBounds
                    WheelHandler { target: null; acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad; blocking: true; onWheel: function(event) { root.scrollByWheel(stepList, event); } }
                    ScrollBar.vertical: ScrollBar { policy: stepList.contentHeight > stepList.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }
                    delegate: Item {
                        id: step
                        required property var modelData
                        required property int index
                        width: ListView.view.width; height: 29
                        Rectangle { x: 7; y: 18; width: 1; height: 17; color: root.theme.border; visible: step.index < root.displaySteps.length - 1 }
                        Rectangle {
                            x: 2; y: 7; width: 11; height: 11; radius: 6
                            color: step.modelData.state === "done" ? root.ok : step.modelData.state === "active" ? root.theme.accent : step.modelData.state === "failed" ? root.danger : root.theme.background
                            border.color: step.modelData.state === "pending" ? root.theme.border : color
                            Text { anchors.centerIn: parent; visible: step.modelData.state === "done"; text: "✓"; font.pixelSize: 8; color: root.theme.background }
                        }
                        Text { x: 25; width: parent.width - 37; anchors.verticalCenter: parent.verticalCenter; text: step.modelData.label; elide: Text.ElideRight; color: step.modelData.state === "pending" ? root.theme.muted : root.theme.text; font.pixelSize: 12; font.weight: step.modelData.state === "active" ? Font.DemiBold : Font.Normal }
                    }
                }
                Text { visible: !root.busy && root.view !== "failed" && root.view !== "uptodate"; text: "Progress will appear here"; color: root.theme.muted; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            }
            Rectangle { visible: !root.narrow; Layout.fillHeight: true; implicitWidth: 1; color: root.theme.border }
            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0; Layout.margins: 20; spacing: 16
                RowLayout {
                    Layout.fillWidth: true; spacing: 4
                    Repeater {
                        model: ["Highlights", root.updates.length > 0 ? "Packages · " + root.updates.length : "Packages", "Activity"]
                        V.Button {
                            required property int index
                            required property string modelData
                            objectName: "updateTab" + index
                            implicitWidth: contentItem.implicitWidth + 24; implicitHeight: 30
                            text: modelData; primary: root.tab === index; accent: root.theme.accent
                            onClicked: root.tab = index
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
                // Actual release content, without standalone raw URL paragraphs.
                Flickable {
                    id: notes
                    visible: root.tab === 0
                    Layout.fillWidth: true; Layout.fillHeight: true
                    contentWidth: width; contentHeight: notesColumn.implicitHeight; clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    WheelHandler { target: null; acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad; blocking: true; onWheel: function(event) { root.scrollByWheel(notes, event); } }
                    ScrollBar.vertical: ScrollBar { policy: notes.contentHeight > notes.height + 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }
                    ColumnLayout {
                        id: notesColumn
                        width: notes.width - 12; spacing: 8
                        Text {
                            visible: !!root.release
                            text: "What’s new"
                            color: root.theme.text; font.pixelSize: 16; font.weight: Font.DemiBold
                        }
                        Text {
                            visible: !!root.release && !root.check.omarchy
                            Layout.topMargin: -4
                            text: "The version you are running"
                            color: root.theme.muted; font.pixelSize: 12
                        }
                        Repeater {
                            model: Logic.releaseBlocks(root.release ? root.release.blocks : [])
                            RowLayout {
                                id: block
                                required property var modelData
                                Layout.fillWidth: true; spacing: 8
                                Layout.topMargin: modelData.type === "h" ? 6 : 0
                                Text { visible: block.modelData.type === "li"; Layout.alignment: Qt.AlignTop; text: "•"; color: root.theme.accent; font.pixelSize: 13 }
                                Text {
                                    Layout.fillWidth: true; wrapMode: Text.WordWrap; textFormat: Text.PlainText
                                    text: block.modelData.text
                                    color: block.modelData.type === "h" ? root.theme.text : "#d6d4de"
                                    font.pixelSize: block.modelData.type === "h" ? 14 : 13
                                    font.weight: block.modelData.type === "h" ? Font.DemiBold : Font.Normal
                                    lineHeight: 1.25
                                }
                            }
                        }
                        Text {
                            visible: !root.release
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: root.view === "checking" ? "Looking for release notes…" : "Release notes are not available right now."
                            color: root.theme.muted; font.pixelSize: 13
                        }

                        Text {
                            visible: !!root.check.last && !root.busy
                            Layout.fillWidth: true; Layout.topMargin: 6; wrapMode: Text.WordWrap
                            text: {
                                var last = root.check.last, at = last ? Logic.parseStamp(last.at) : null;
                                return last ? "Last package changes: " + (at ? Qt.formatDateTime(at, "d MMM yyyy, HH:mm") : last.at) + " · " + last.count + (last.count === 1 ? " package" : " packages") : "";
                            }
                            color: root.theme.muted; font.pixelSize: 12
                        }
                    }
                }

                V.Button {
                    objectName: "updateNotesLink"
                    visible: root.tab === 0 && !!root.release && !!root.release.url
                    Layout.topMargin: 4; implicitHeight: 32; accent: root.theme.accent
                    text: "Read full release notes ↗"
                    onClicked: root.backend.openUrl(root.release.url)
                }

                // Packages
                ListView {
                    id: packages
                    objectName: "updatePackages"
                    visible: root.tab === 1
                    Layout.fillWidth: true; Layout.fillHeight: true
                    model: root.updates; clip: true; spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    WheelHandler { target: null; acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad; blocking: true; onWheel: function(event) { root.scrollByWheel(packages, event); } }
                    ScrollBar.vertical: ScrollBar { policy: packages.contentHeight > packages.height + 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }
                    delegate: RowLayout {
                        id: pkg
                        required property var modelData
                        width: ListView.view.width - 12; height: 28; spacing: 8
                        Text { text: pkg.modelData.name; color: root.theme.text; font.pixelSize: 13; elide: Text.ElideRight; Layout.fillWidth: true }
                        Rectangle {
                            visible: pkg.modelData.source === "aur"
                            implicitWidth: aurLabel.implicitWidth + 10; implicitHeight: 18; radius: 6; color: root.hover
                            Text { id: aurLabel; anchors.centerIn: parent; text: "AUR"; color: root.theme.muted; font.pixelSize: 10 }
                        }
                        Text { text: pkg.modelData.old + " →"; color: root.theme.muted; font.pixelSize: 12; font.family: "monospace"; elide: Text.ElideLeft; Layout.maximumWidth: 150 }
                        Text { text: pkg.modelData.new; color: root.ok; font.pixelSize: 12; font.family: "monospace"; elide: Text.ElideRight; Layout.maximumWidth: 150 }
                    }
                    Text {
                        visible: root.updates.length === 0
                        anchors.centerIn: parent
                        text: root.view === "checking" ? "Checking…" : "Nothing to update"
                        color: root.theme.muted; font.pixelSize: 13
                    }
                }


                Rectangle {
                    visible: root.tab === 2
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0
                    radius: 10; color: root.theme.surface; border.color: root.theme.border
                    ListView {
                        id: log; objectName: "updateLog"
                        anchors.fill: parent; anchors.margins: 12
                        model: root.run.tail || []; clip: true; spacing: 4
                        boundsBehavior: Flickable.StopAtBounds
                        property bool follow: true
                        onMovementEnded: follow = atYEnd
                        onCountChanged: if (follow) Qt.callLater(positionViewAtEnd)
                        WheelHandler { target: null; acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad; blocking: true; onWheel: function(event) { root.scrollByWheel(log, event); log.follow = log.atYEnd; } }
                        ScrollBar.vertical: ScrollBar { policy: log.contentHeight > log.height + 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }
                        delegate: Text { required property string modelData; width: ListView.view.width - 12; text: modelData; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; color: "#bdbbc8"; font.pixelSize: 11; font.family: "monospace" }
                        Text { visible: log.count === 0; width: parent.width - 12; anchors.centerIn: parent; text: "Update activity will appear here"; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter; color: root.theme.muted; font.pixelSize: 13 }
                    }
                }
            }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.theme.border }
        ColumnLayout {
            id: footer; objectName: "updateFooter"
            Layout.fillWidth: true; Layout.margins: 18; spacing: 10
            Text { visible: root.backend && root.backend.startError !== ""; text: root.backend ? root.backend.startError : ""; color: root.danger; wrapMode: Text.WordWrap; font.pixelSize: 12; Layout.fillWidth: true }
            Text { visible: root.view === "confirm"; text: root.question; textFormat: Text.PlainText; color: root.theme.text; wrapMode: Text.WordWrap; font.pixelSize: 13; Layout.fillWidth: true }
            RowLayout {
                Layout.fillWidth: true; spacing: 12
                ColumnLayout {
                    visible: root.view !== "password"; Layout.fillWidth: true; spacing: 5
                    Text { text: root.busy ? "Updating · " + (root.run.percent || 0) + "%" : root.view === "failed" ? "Review Activity before retrying" : root.view === "uptodate" ? "Your system is current" : root.view === "checking" ? "Checking for updates…" : root.view === "error" ? "Try checking again" : "Snapshot before installation"; color: root.theme.text; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    Text { text: root.busy ? "Closing this window keeps the update running." : root.view === "available" ? "Keep power connected. The update cannot be stopped once started." : ""; visible: text !== ""; color: root.theme.muted; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    ProgressBar {
                        id: progress; objectName: "updateProgress"
                        visible: root.busy || root.view === "checking"
                        Layout.fillWidth: true; implicitHeight: 4
                        value: root.busy ? (root.run.percent || 0) / 100 : 0
                        indeterminate: root.view === "checking" || (root.view === "running" && root.run.phase !== "running")
                        property real sweep: 0
                        background: Rectangle { radius: 2; color: root.theme.border }
                        contentItem: Item {
                            clip: true
                            Rectangle {
                                x: progress.indeterminate ? parent.width * (root.motion ? progress.sweep : .375) : 0
                                width: progress.indeterminate ? parent.width * .25 : parent.width * progress.position
                                height: parent.height; radius: 2; color: root.theme.accent
                            }
                        }
                        NumberAnimation on sweep { running: progress.visible && progress.indeterminate && root.motion; from: -.25; to: 1; duration: 1200; loops: Animation.Infinite }
                    }
                }
                TextField {
                    id: password; objectName: "updatePassword"
                    visible: root.view === "password"; Layout.fillWidth: true; implicitHeight: 38
                    leftPadding: 12; rightPadding: 12; echoMode: TextInput.Password; enabled: !root.sent
                    placeholderText: "Password to continue"; placeholderTextColor: root.theme.muted; color: root.theme.text; font.pixelSize: 13
                    Accessible.name: "Password for the update"
                    background: Rectangle { radius: 10; color: root.theme.surface; border.color: password.activeFocus ? root.theme.accent : root.theme.border }
                    onAccepted: root.submitPassword()
                    Keys.onEscapePressed: root.closeRequested()
                }
                V.Button {
                    objectName: "updatePrimary"
                    visible: ["available", "failed", "uptodate", "error", "password"].indexOf(root.view) >= 0
                    implicitWidth: 136; implicitHeight: 38; Layout.minimumHeight: 38
                    primary: root.view === "available" || root.view === "password"; accent: root.theme.accent
                    enabled: root.view === "password" ? !root.sent && password.text.length > 0 : !(root.backend && root.backend.checking)
                    text: root.view === "available" ? "Update now" : root.view === "failed" ? "Try again" : root.view === "password" ? (root.sent ? "Checking…" : "Continue") : root.backend && root.backend.checking ? "Checking…" : "Check again"
                    onClicked: { if (root.view === "password") root.submitPassword(); else root.primary(); }
                }
                V.Button { visible: root.view === "failed"; implicitWidth: 78; implicitHeight: 38; text: "Dismiss"; accent: root.theme.accent; onClicked: root.backend.dismissFailure() }
                V.Button { objectName: "updateConfirmYes"; visible: root.view === "confirm"; implicitWidth: 112; implicitHeight: 38; primary: true; accent: root.theme.accent; text: root.restartChoice ? "Restart now" : "Yes"; onClicked: root.backend.answer({kind: "confirm", value: true}) }
                V.Button { objectName: "updateConfirmNo"; visible: root.view === "confirm"; implicitWidth: 78; implicitHeight: 38; accent: root.theme.accent; text: root.restartChoice ? "Later" : "No"; onClicked: root.backend.answer({kind: "confirm", value: false}) }
            }
        }
    }
}
