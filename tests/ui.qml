//@ pragma OmarchyLoadPatch
import QtQuick
import Quickshell
import "velunori.update/components"
import "velunori.update/UpdateLogic.js" as Logic
import "velunori.core/kit" as V

ShellRoot {
    id: testRoot
    property string failure: ""
    function check(value, message) { if (!value) failure += message + "; "; }
    function checkFooter() {
        var footer = find(view, "updateFooter");
        var point = footer.mapToItem(view, 0, 0);
        check(point.y >= 0 && point.y + footer.height <= view.height + 1, "action footer fits window");
        for (var name of ["updatePrimary", "updatePassword", "updateConfirmYes", "updateConfirmNo"]) {
            var item = find(view, name);
            if (!item.visible) continue;
            var pos = item.mapToItem(view, 0, 0);
            check(pos.y >= 0 && pos.y + item.height <= view.height + 1 && pos.x >= 0 && pos.x + item.width <= view.width + 1, name + " stays fully visible");
        }
    }
    function find(parent, name) { if (parent.objectName === name) return parent; var kids = parent.children || []; for (var i = 0; i < kids.length; i++) { var hit = find(kids[i], name); if (hit) return hit; } return null; }
    readonly property var steps: ["Preparing", "Snapshot", "Keyring", "System packages", "Migrations", "AUR packages", "Cleanup", "Finishing"]
    function runAt(index, extra) {
        var rows = [];
        for (var i = 0; i < steps.length; i++) rows.push({id: "s" + i, label: steps[i], state: i < index ? "done" : i === index ? "active" : "pending"});
        var state = {phase: "running", startedAt: 50, step: index, steps: rows, percent: 47, detail: "23 of 74 · hyprland", prompt: null,
            tail: ["Update system packages", "(21/74) upgrading mesa", "(22/74) upgrading pipewire", "(23/74) upgrading hyprland"]};
        for (var key in extra || {}) state[key] = extra[key];
        return state;
    }
    QtObject {
        id: fake
        property var check: ({checkedAt: 1000, installed: "4.0.6-1", error: "",
            updates: [{name: "omarchy", old: "4.0.6-1", new: "4.5.0-3", source: "repo"}, {name: "hyprland", old: "0.53.1-1", new: "0.53.3-1", source: "repo"},
                {name: "linux", old: "7.2.8.arch1-1", new: "7.2.9.arch1-1", source: "repo"}, {name: "vesktop-bin", old: "1.6.7-5", new: "1.6.9-1", source: "aur"}],
            omarchy: {name: "omarchy", old: "4.0.6-1", new: "4.5.0-3"},
            release: {version: "4.5.0", title: "v4.5.0", url: "https://example.invalid/notes", blocks: [
                {type: "p", text: "The first big feature release since Quattro, with a traditional desktop mode next to the tiling default."},
                {type: "h", text: "Highlights"}, {type: "li", text: "Traditional desktop mode"}, {type: "li", text: "Native install on Apple Silicon"}, {type: "li", text: "Fifty languages"}]},
            last: {at: "2026-10-21T10:03:33+0200", count: 2}})
        property var run: ({phase: "idle"})
        property bool checking: false
        property bool starting: false
        property var dismissedRun: 0
        property string startError: ""
        property real now: 1300
        readonly property var updates: check.updates || []
        readonly property string view: Logic.viewFor(check, run, checking, starting, dismissedRun)
        readonly property bool justUpdated: Logic.justUpdated(check, run)
        property int starts: 0
        property int refreshes: 0
        property var answers: []
        property string opened: ""
        function start() { starts++; }
        function refresh(force) { refreshes++; }
        function answer(message) { answers = answers.concat([message]); }
        function dismissFailure() { dismissedRun = run.startedAt; }
        function openUrl(url) { opened = url; }
    }
    V.Theme { id: tokens; bar: ({velunori: {apiVersion: 1, accentName: "lavender", motion: true}}) }
    FloatingWindow {
        visible: true; implicitWidth: Number(Quickshell.env("VELUNORI_TEST_WIDTH") || 760); implicitHeight: Number(Quickshell.env("VELUNORI_TEST_HEIGHT") || 540); color: "transparent"
        Rectangle {
            id: surface
            anchors.fill: parent; radius: 18; color: "#202026"; border.color: "#48464f"; clip: true
            UpdateView { id: view; anchors.fill: parent; anchors.margins: 1; backend: fake; theme: tokens }
        }
    }
    function setState(name) {
        var clean = JSON.parse(JSON.stringify(fake.check)); clean.updates = []; clean.omarchy = null; clean.installed = "4.5.0-3";
        if (name === "running") fake.run = runAt(3);
        else if (name === "password") fake.run = runAt(1, {percent: 2, detail: "", tail: [], prompt: {kind: "password", retry: false}});
        else if (name === "confirm") fake.run = runAt(7, {percent: 97, detail: "", prompt: {kind: "confirm", question: "Linux kernel has been updated. Reboot?"}});
        else if (name === "failed") { var failed = runAt(3); failed.phase = "failed"; failed.steps[3].state = "failed"; failed.tail = failed.tail.concat(["error: failed to commit transaction (conflicting files)", "Something went wrong during the update!"]); fake.run = failed; }
        else if (name === "uptodate") { fake.check = clean; fake.run = ({phase: "idle"}); }
        else if (name === "checking") { fake.check = ({}); fake.checking = true; }
        else fake.run = ({phase: "idle"});
    }
    Timer {
        interval: 300; running: true
        onTriggered: {
            var preview = Quickshell.env("VELUNORI_PREVIEW_PATH");
            if (preview) {
                setState(Quickshell.env("VELUNORI_PREVIEW_STATE") || "available");
                var tab = Quickshell.env("VELUNORI_PREVIEW_TAB");
                grab.start();
                if (tab) Qt.callLater(function() { view.tab = Number(tab); });
                return;
            }
            var title = find(view, "updateTitle"), subtitle = find(view, "updateSubtitle"), primary = find(view, "updatePrimary"), password = find(view, "updatePassword");
            check(view.view === "available" && title.text === "Ready to update" && subtitle.text === "4 packages available", "pending updates are summarised");
            check(view.tab === 0 && find(view, "updatePackages").count === 4, "release notes open first and every package is listed");
            find(view, "updateNotesLink").clicked(); check(fake.opened === "https://example.invalid/notes", "release notes link opens through the backend");
            primary.clicked(); check(fake.starts === 1, "Update now starts the update");

            setState("password");
            check(view.view === "password" && password.visible && password.echoMode === TextInput.Password, "password is asked in a masked field");
            check(!primary.enabled, "an empty password cannot be sent");
            password.text = "hunter2"; primary.clicked();
            check(fake.answers.length === 1 && fake.answers[0].kind === "password" && fake.answers[0].value === "hunter2", "password goes to the backend once");
            check(password.text === "" && !password.enabled, "the field is cleared and locked after sending");
            primary.clicked(); check(fake.answers.length === 1, "a second submit sends nothing");
            fake.run = runAt(1, {prompt: {kind: "password", retry: true}});
            check(password.enabled && subtitle.text.indexOf("not accepted") >= 0, "a rejected password can be entered again");

            setState("running");
            check(view.view === "running" && view.tab === 2 && title.text === "Updating…", "running switches to the log");
            check(subtitle.text === "System packages · 23 of 74 · hyprland" && find(view, "updateLog").count === 4, "current step, package progress and output are shown");
            check(!primary.visible && Math.abs(find(view, "updateProgress").value - 0.47) < 0.001, "no action while running; bar shows progress");

            setState("confirm");
            check(title.text === "Restart to finish" && find(view, "updateConfirmYes").text === "Restart now", "reboot question reads as a restart choice");
            find(view, "updateConfirmNo").clicked();
            check(fake.answers.length === 2 && fake.answers[1].kind === "confirm" && fake.answers[1].value === false, "Later answers no");

            setState("failed");
            check(title.text === "Update did not finish" && subtitle.text === "Stopped during: System packages" && primary.text === "Try again" && view.tab === 2, "failure names the step and shows the log");
            fake.dismissFailure(); check(view.view === "available", "dismissing a failure returns to the pending updates");

            setState("uptodate");
            check(title.text === "System is up to date" && subtitle.text === "Omarchy 4.5.0 · checked 5 minutes ago" && primary.text === "Check again", "up to date state");
            check(find(view, "updatePackages").count === 0, "nothing is pending");
            primary.clicked(); check(fake.refreshes === 1, "Check again asks the backend");
            setState("checking"); check(title.text === "Checking for updates…" && find(view, "updateProgress").indeterminate, "checking state");
            footerProbe.start();
        }
    }
    Timer {
        id: footerProbe; interval: 80
        property var states: ["available", "password", "running", "confirm", "failed", "uptodate", "checking"]
        property int index: 0
        onTriggered: {
            checkFooter();
            if (index < states.length) {
                var initial = JSON.parse(JSON.stringify(fake.check));
                initial.checkedAt = 1000; initial.updates = [{name:"omarchy",old:"4.0.6",new:"4.5.0"}]; initial.omarchy = initial.updates[0];
                fake.checking = false; fake.check = initial;
                setState(states[index++]); restart();
            } else {
                console.log(failure === "" ? "UPDATE_TEST_PASSED" : "UPDATE_TEST_FAILED " + failure);
                Qt.quit();
            }
        }
    }
    Timer {
        id: grab
        interval: 700
        onTriggered: surface.grabToImage(function(result) {
            console.log(result.saveToFile(Quickshell.env("VELUNORI_PREVIEW_PATH")) ? "UPDATE_PREVIEW_SAVED" : "UPDATE_PREVIEW_FAILED");
            Qt.quit();
        })
    }
}
