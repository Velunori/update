// Which screen the window shows. Kept free of QML so it can be tested alone.
function viewFor(check, run, checking, starting, dismissedRun) {
    var phase = run && run.phase || "idle";
    if (phase === "running") {
        if (run.prompt && run.prompt.kind === "password") return "password";
        if (run.prompt && run.prompt.kind === "confirm") return "confirm";
        return "running";
    }
    if (starting) return "running";
    if (phase === "failed" && run.startedAt !== dismissedRun) return "failed";
    if (!check || !check.checkedAt) return checking ? "checking" : "error";
    if ((check.updates || []).length > 0) return "available";
    if (check.error) return checking ? "checking" : "error";
    return "uptodate";
}

function justUpdated(check, run) {
    return !!run && run.phase === "done" && !!check && check.checkedAt >= run.finishedAt && (check.updates || []).length === 0;
}

function ago(seconds) {
    if (!(seconds >= 0)) return "";
    if (seconds < 90) return "just now";
    if (seconds < 3600) return Math.round(seconds / 60) + " minutes ago";
    if (seconds < 86400 * 2) return Math.round(seconds / 3600) + " hours ago";
    return Math.round(seconds / 86400) + " days ago";
}

// pacman writes offsets as +0200; the engine only parses +02:00.
function parseStamp(text) {
    var value = new Date(String(text || "").replace(/([+-]\d\d)(\d\d)$/, "$1:$2"));
    return isNaN(value.getTime()) ? null : value;
}

function activeStep(run) {
    var steps = run && run.steps || [];
    for (var i = 0; i < steps.length; i++) if (steps[i].state === "active" || steps[i].state === "failed") return steps[i];
    return null;
}

function restartQuestion(question) { return /reboot|restart/i.test(String(question || "")); }

function summary(check) {
    var updates = check && check.updates || [];
    var count = updates.length + (updates.length === 1 ? " package" : " packages");
    return check && check.omarchy ? "Omarchy " + String(check.omarchy.new).split("-")[0] + " · " + count : count;
}

// Standalone links already have a pinned action in the view. Keep all prose
// and structured highlights; never synthesize a release summary.
function releaseBlocks(blocks) {
    return (blocks || []).filter(function(block) {
        return !/^(?:release notes\s*:\s*)?https?:\/\/\S+\s*$/i.test(String(block.text || "").trim());
    });
}
