import QtQuick
import Quickshell
import Quickshell.Io
import "." as Local
import "UpdateLogic.js" as Logic

Item {
  id: service
  visible: false

  // Injected by omarchy-shell.
  property var shell: null

  property var check: ({})
  property var run: ({phase: "idle"})
  property bool starting: false
  property var dismissedRun: 0
  property string startError: ""
  property bool firstState: true
  property real now: Date.now() / 1000
  readonly property bool checking: checkProcess.running
  readonly property bool running: run.phase === "running" || starting
  readonly property var updates: check.updates || []
  readonly property string view: Logic.viewFor(check, run, checking, starting, dismissedRun)
  readonly property bool justUpdated: Logic.justUpdated(check, run)
  readonly property bool windowOpen: Local.Runtime.windowOpen
  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("backend.py").toString().replace(/^(file|qs):\/\//, ""))

  function refresh(force) {
    if (checkProcess.running || running) return
    if (!force && check.checkedAt && now - check.checkedAt < 600) return
    checkProcess.running = true
  }

  // Runs in its own systemd scope: the update restarts the shell at its end,
  // and the shell's unit takes every process in its control group with it.
  function start() {
    if (running) return
    startError = ""
    starting = true
    dismissedRun = 0
    Quickshell.execDetached(["systemd-run", "--user", "--scope", "--collect", "--quiet", "--unit=velunori-update-" + Date.now(), "python3", helper, "run"])
    startGuard.restart()
    pollState()
  }

  function answer(message) {
    if (answerProcess.running) return
    answerProcess.message = JSON.stringify(message) + "\n"
    answerProcess.running = true
  }

  function dismissFailure() { dismissedRun = run.startedAt || 0 }
  function pollState() { if (!stateProcess.running) stateProcess.running = true }
  function show() { if (shell) shell.summon("velunori.update", "{}") }
  function hide() { if (shell) shell.hide("velunori.update") }
  function openUrl(url) { if (String(url).indexOf("https://") === 0) Quickshell.execDetached(["xdg-open", url]) }

  function acceptState(next) {
    var previous = run.phase
    run = next
    if (next.phase === "running") { starting = false; startGuard.stop() }
    if (previous === "running" && next.phase !== "running") refresh(true)
    if (firstState) {
      firstState = false
      // The update's last act is restarting the shell, which closed the
      // window. Bring it back to show how the run ended.
      var fresh = next.finishedAt && Date.now() / 1000 - next.finishedAt < 45
      if (next.phase === "running" || ((next.phase === "done" || next.phase === "failed") && fresh)) show()
    }
  }

  Component.onDestruction: if (Local.Runtime.backend === service) Local.Runtime.backend = null
  Component.onCompleted: {
    Local.Runtime.backend = service
    cachedProcess.running = true
    pollState()
  }
  onWindowOpenChanged: if (windowOpen) { now = Date.now() / 1000; pollState(); refresh(false) }

  Timer { interval: service.running ? 400 : 3000; running: service.running || service.windowOpen; repeat: true; onTriggered: service.pollState() }
  Timer { interval: 30000; running: service.windowOpen; repeat: true; onTriggered: service.now = Date.now() / 1000 }
  Timer { interval: 21600000; running: true; repeat: true; onTriggered: service.refresh(true) }
  Timer {
    id: startGuard
    interval: 8000
    onTriggered: if (service.starting) { service.starting = false; service.startError = "The update could not be started." }
  }

  Process {
    id: cachedProcess
    command: ["python3", service.helper, "cached"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { var cached = JSON.parse(text); if (cached.checkedAt && !service.check.checkedAt) service.check = cached } catch (error) {}
        // Look again unless the remembered answer is under an hour old.
        if (!service.check.checkedAt || Date.now() / 1000 - service.check.checkedAt > 3600) service.refresh(true)
      }
    }
  }
  Process {
    id: checkProcess
    command: ["python3", service.helper, "check"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { var result = JSON.parse(text); if (result.checkedAt) service.check = result } catch (error) {}
        service.now = Date.now() / 1000
      }
    }
  }
  Process {
    id: stateProcess
    command: ["python3", service.helper, "state"]
    stdout: StdioCollector {
      onStreamFinished: { try { service.acceptState(JSON.parse(text)) } catch (error) {} }
    }
  }
  Process {
    id: answerProcess
    property string message: ""
    command: ["python3", service.helper, "answer"]
    stdinEnabled: true
    onStarted: { write(message); message = "" }
    onExited: service.pollState()
  }

  IpcHandler {
    target: "velunori.update"
    function show(): void { service.show() }
    function hide(): void { service.hide() }
    function check(): void { service.refresh(true) }
    function status(): string {
      return JSON.stringify({version: "0.1.0", view: service.view, updates: service.updates.length, phase: service.run.phase || "idle", checkedAt: service.check.checkedAt || 0})
    }
  }
  // omarchy-update ends by telling the built-in indicator to look again; this
  // plugin stands in for it, so it answers to the same name.
  IpcHandler {
    target: "omarchy.system-update"
    function refresh(): void { service.refresh(true) }
    function clear(): void { service.refresh(true) }
  }
}
