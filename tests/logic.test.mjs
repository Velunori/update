import fs from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';
const logic = vm.createContext({});
vm.runInContext(fs.readFileSync(new URL('../UpdateLogic.js', import.meta.url), 'utf8'), logic);
const pending = {checkedAt: 100, updates: [{name: 'omarchy', old: '4.0.6-1', new: '4.5.0-3'}, {name: 'linux'}], omarchy: {new: '4.5.0-3'}};
const clean = {checkedAt: 100, updates: []};

test('a running update always wins, and its questions pick the screen', () => {
    assert.equal(logic.viewFor(pending, {phase: 'running'}, false, false, 0), 'running');
    assert.equal(logic.viewFor(pending, {phase: 'running', prompt: {kind: 'password'}}, true, false, 0), 'password');
    assert.equal(logic.viewFor(clean, {phase: 'running', prompt: {kind: 'confirm'}}, false, false, 0), 'confirm');
    assert.equal(logic.viewFor(pending, {phase: 'idle'}, false, true, 0), 'running');
});
test('a failure stays visible until dismissed, then the check result shows', () => {
    assert.equal(logic.viewFor(pending, {phase: 'failed', startedAt: 7}, false, false, 0), 'failed');
    assert.equal(logic.viewFor(pending, {phase: 'failed', startedAt: 7}, false, false, 7), 'available');
});
test('no answer yet is checking, not up to date', () => {
    assert.equal(logic.viewFor({}, {phase: 'idle'}, true, false, 0), 'checking');
    assert.equal(logic.viewFor({}, {phase: 'idle'}, false, false, 0), 'error');
    assert.equal(logic.viewFor({checkedAt: 5, updates: [], error: 'offline'}, {phase: 'idle'}, false, false, 0), 'error');
    assert.equal(logic.viewFor(clean, {phase: 'idle'}, false, false, 0), 'uptodate');
    assert.equal(logic.viewFor(clean, {phase: 'done'}, true, false, 0), 'uptodate');
});
test('"update complete" needs a check made after the run ended', () => {
    assert.equal(logic.justUpdated({checkedAt: 90, updates: []}, {phase: 'done', finishedAt: 95}), false);
    assert.equal(logic.justUpdated({checkedAt: 99, updates: []}, {phase: 'done', finishedAt: 95}), true);
    assert.equal(logic.justUpdated({checkedAt: 99, updates: [{}]}, {phase: 'done', finishedAt: 95}), false);
});
test('wording helpers', () => {
    assert.equal(logic.summary(pending), 'Omarchy 4.5.0 · 2 packages');
    assert.equal(logic.summary({updates: [{}]}), '1 package');
    assert.equal(logic.ago(30), 'just now');
    assert.equal(logic.ago(600), '10 minutes ago');
    assert.equal(logic.ago(7200), '2 hours ago');
    assert.equal(logic.parseStamp('2026-10-21T10:03:33+0200').toISOString(), '2026-10-21T08:03:33.000Z');
    assert.equal(logic.parseStamp('nonsense'), null);
    assert.equal(logic.restartQuestion('Linux kernel has been updated. Reboot?'), true);
    assert.equal(logic.restartQuestion('Remove orphans?'), false);
    assert.equal(logic.activeStep({steps: [{state: 'done'}, {state: 'failed', label: 'System packages'}]}).label, 'System packages');
});
