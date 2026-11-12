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
    implicitWidth: 680; implicitHeight: 430

    function takeFocus() { if (view === "password") password.forceActiveFocus(); else keys.forceActiveFocus(); }
    onViewChanged: {
        sent = false;
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
    function primary() {
        if (!backend) return;
        if (view === "available" || view === "failed") backend.start();
        else if (view === "uptodate" || view === "error") backend.refresh(true);
    }

    readonly property string title: view === "available" ? "Update available"
        : view === "running" ? (run.phase === "running" ? "Updating…" : "Starting…")
        : view === "password" ? "Password needed"
        : view === "confirm" ? (restartChoice ? "Restart to finish" : "One question")
        : view === "failed" ? "Update did not finish"
        : view === "checking" ? "Checking for updates…"
        : view === "error" ? "Could not check for updates"
        : backend && backend.justUpdated ? "Update complete" : "System is up to date"
    readonly property string subtitle: {
        if (view === "available") return Logic.summary(check);
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

    RowLayout {
        anchors.fill: parent; spacing: 0

        // ------------------------------------------------ status and action
        ColumnLayout {
            Layout.preferredWidth: 236; Layout.maximumWidth: 236; Layout.fillHeight: true
            Layout.margins: 20; spacing: 14
            Item { Layout.fillHeight: true }
            ProgressRing {
                id: ring
                objectName: "updateRing"
                Layout.alignment: Qt.AlignHCenter
                motion: root.motion
                indeterminate: root.view === "checking" || (root.view === "running" && root.run.phase !== "running")
                value: root.busy ? (root.run.percent || 0) / 100 : (root.view === "uptodate" ? 1 : 0)
                color: root.view === "uptodate" ? root.ok : root.view === "failed" || root.view === "error" ? root.danger : root.theme.accent
                Column {
                    anchors.centerIn: parent
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.view === "available" ? root.updates.length
                            : root.busy ? (root.run.percent || 0) + "%"
                            : root.view === "uptodate" ? "✓" : root.view === "failed" || root.view === "error" ? "!" : ""
                        color: root.view === "uptodate" ? root.ok : root.view === "failed" || root.view === "error" ? root.danger : root.theme.text
                        font.pixelSize: 26; font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: text !== ""
                        text: root.view === "available" ? (root.updates.length === 1 ? "update" : "updates")
                            : root.busy && root.run.steps ? "step " + Math.min(root.run.steps.length, (root.run.step || 0) + 1) + " of " + root.run.steps.length : ""
                        color: root.theme.muted; font.pixelSize: 12
                    }
                }
            }
            Text {
                objectName: "updateTitle"
                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                text: root.title; color: root.theme.text; font.pixelSize: 18; font.weight: Font.DemiBold
            }
            Text {
                objectName: "updateSubtitle"
                Layout.fillWidth: true; Layout.topMargin: -8; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                visible: text !== ""
                text: root.subtitle
                color: root.view === "password" && root.run.prompt && root.run.prompt.retry ? root.warn : root.theme.muted
                font.pixelSize: 12; textFormat: Text.PlainText; maximumLineCount: 4; elide: Text.ElideRight
            }
            TextField {
                id: password
                objectName: "updatePassword"
                visible: root.view === "password"
                Layout.fillWidth: true; implicitHeight: 38; leftPadding: 12; rightPadding: 12
                echoMode: TextInput.Password
                enabled: !root.sent
                placeholderText: "Password"; placeholderTextColor: root.theme.muted; color: root.theme.text; font.pixelSize: 13
                Accessible.name: "Password for the update"
                background: Rectangle { radius: 12; color: root.theme.background; border.color: password.activeFocus ? root.theme.accent : root.theme.border }
                onAccepted: root.submitPassword()
                Keys.onEscapePressed: root.closeRequested()
            }
            V.Button {
                objectName: "updatePrimary"
                visible: ["available", "failed", "uptodate", "error", "password"].indexOf(root.view) >= 0
                Layout.fillWidth: true; implicitHeight: 38
                primary: root.view === "available" || root.view === "password"; accent: root.theme.accent
                enabled: root.view === "password" ? !root.sent && password.text.length > 0 : !(root.backend && root.backend.checking)
                text: root.view === "available" ? "Update now" : root.view === "failed" ? "Try again"
                    : root.view === "password" ? (root.sent ? "Checking…" : "Continue")
                    : root.backend && root.backend.checking ? "Checking…" : "Check again"
                onClicked: { if (root.view === "password") root.submitPassword(); else root.primary(); }
            }
            RowLayout {
                visible: root.view === "confirm"
                Layout.fillWidth: true; spacing: 8
                V.Button {
                    objectName: "updateConfirmYes"
                    Layout.fillWidth: true; implicitWidth: 80; implicitHeight: 38; primary: true; accent: root.theme.accent
                    text: root.restartChoice ? "Restart now" : "Yes"
                    onClicked: root.backend.answer({kind: "confirm", value: true})
                }
                V.Button {
                    objectName: "updateConfirmNo"
                    Layout.fillWidth: true; implicitWidth: 80; implicitHeight: 38; accent: root.theme.accent
                    text: root.restartChoice ? "Later" : "No"
                    onClicked: root.backend.answer({kind: "confirm", value: false})
                }
            }
            V.Button {
                visible: root.view === "failed"
                Layout.fillWidth: true; implicitHeight: 34; accent: root.theme.accent
                text: "Dismiss"
                onClicked: root.backend.dismissFailure()
            }
            Text {
                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                visible: text !== ""
                text: root.backend && root.backend.startError ? root.backend.startError
                    : root.view === "available" ? "A snapshot is made first. Once started, the update cannot be stopped. Keep power connected."
                    : root.busy ? "Do not turn off your computer. Esc hides this window; the update keeps running." : ""
                color: root.backend && root.backend.startError ? root.danger : root.warn; font.pixelSize: 11
            }
            Item { Layout.fillHeight: true }
        }

        Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: root.theme.border }

        // ------------------------------------------------------------ details
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true
            color: root.theme.surface
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 16; spacing: 12
                RowLayout {
                    spacing: 4
                    Repeater {
                        model: ["What's new", root.updates.length > 0 ? "Packages " + root.updates.length : "Packages", "Log"]
                        Rectangle {
                            id: tabButton
                            required property int index
                            required property string modelData
                            objectName: "updateTab" + index
                            implicitWidth: tabLabel.implicitWidth + 24; implicitHeight: 28; radius: 9
                            color: root.tab === index ? root.hover : "transparent"
                            Behavior on color { enabled: root.motion; ColorAnimation { duration: 90 } }
                            Text { id: tabLabel; anchors.centerIn: parent; text: tabButton.modelData; color: root.tab === tabButton.index ? root.theme.text : root.theme.muted; font.pixelSize: 13 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.tab = tabButton.index }
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                // What's new
                Flickable {
                    id: notes
                    visible: root.tab === 0
                    Layout.fillWidth: true; Layout.fillHeight: true
                    contentWidth: width; contentHeight: notesColumn.implicitHeight; clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: notes.contentHeight > notes.height + 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }
                    ColumnLayout {
                        id: notesColumn
                        width: notes.width - 12; spacing: 8
                        Text {
                            visible: !!root.release
                            text: root.release ? "Omarchy " + root.release.version : ""
                            color: root.theme.text; font.pixelSize: 16; font.weight: Font.DemiBold
                        }
                        Text {
                            visible: !!root.release && !root.check.omarchy
                            Layout.topMargin: -4
                            text: "The version you are running"
                            color: root.theme.muted; font.pixelSize: 12
                        }
                        Repeater {
                            model: root.release ? root.release.blocks : []
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
                        V.Button {
                            objectName: "updateNotesLink"
                            visible: !!root.release && !!root.release.url
                            Layout.topMargin: 4; implicitHeight: 32; accent: root.theme.accent
                            text: "Open full release notes"
                            onClicked: root.backend.openUrl(root.release.url)
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

                // Packages
                ListView {
                    id: packages
                    objectName: "updatePackages"
                    visible: root.tab === 1
                    Layout.fillWidth: true; Layout.fillHeight: true
                    model: root.updates; clip: true; spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
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

                // Log
                ColumnLayout {
                    visible: root.tab === 2
                    Layout.fillWidth: true; Layout.fillHeight: true; spacing: 10
                    GridLayout {
                        visible: !!root.run.steps && root.run.steps.length > 0
                        Layout.fillWidth: true; flow: GridLayout.TopToBottom; rows: Math.ceil((root.run.steps || []).length / 2); columnSpacing: 14; rowSpacing: 7
                        Repeater {
                            model: root.run.steps || []
                            RowLayout {
                                id: step
                                required property var modelData
                                Layout.fillWidth: true; spacing: 8
                                Item {
                                    implicitWidth: 16; implicitHeight: 16
                                    Rectangle {
                                        anchors.fill: parent; radius: 8
                                        visible: step.modelData.state !== "active"
                                        color: step.modelData.state === "done" ? root.ok : step.modelData.state === "failed" ? root.danger : "transparent"
                                        border.color: step.modelData.state === "pending" ? root.theme.border : "transparent"; border.width: 1.5
                                        Text { anchors.centerIn: parent; visible: step.modelData.state !== "pending"; text: step.modelData.state === "failed" ? "!" : "✓"; color: root.theme.background; font.pixelSize: 10; font.weight: Font.Bold }
                                    }
                                    ProgressRing { anchors.fill: parent; visible: step.modelData.state === "active"; indeterminate: true; motion: root.motion; lineWidth: 2; color: root.theme.accent; track: root.hover }
                                }
                                Text {
                                    Layout.fillWidth: true; elide: Text.ElideRight
                                    text: step.modelData.label
                                    color: step.modelData.state === "pending" ? root.theme.muted : root.theme.text
                                    font.pixelSize: 13; font.weight: step.modelData.state === "active" ? Font.DemiBold : Font.Normal
                                }
                            }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        radius: 10; color: root.theme.background; border.color: root.theme.border
                        ListView {
                            id: log
                            objectName: "updateLog"
                            anchors.fill: parent; anchors.margins: 10
                            model: root.run.tail || []; clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            // Follow the output unless the reader has scrolled up.
                            property bool follow: true
                            onMovementEnded: follow = atYEnd
                            onCountChanged: if (follow) Qt.callLater(positionViewAtEnd)
                            ScrollBar.vertical: ScrollBar { policy: log.contentHeight > log.height + 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }
                            delegate: Text {
                                required property string modelData
                                width: ListView.view.width - 12
                                text: modelData; textFormat: Text.PlainText; elide: Text.ElideRight
                                color: "#bdbbc8"; font.pixelSize: 11; font.family: "monospace"
                            }
                            Text {
                                visible: log.count === 0
                                anchors.centerIn: parent
                                text: "No update has run since you logged in"
                                color: root.theme.muted; font.pixelSize: 13
                            }
                        }
                    }
                }
            }
        }
    }
}
