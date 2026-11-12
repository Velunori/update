#!/usr/bin/env python3
"""Velunori Update helper: looks for updates and drives `omarchy-update`.

The update itself is Omarchy's own command, run unchanged in a pseudo-terminal.
This helper only observes it (which step is running, package progress) and
passes the two kinds of answers it may wait for: the sudo password and yes/no
questions. The password is written straight to the terminal that asked for it
while echo is off; it is never stored, logged or put in arguments.
"""
import contextlib
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import time
import urllib.request

RUNTIME = Path(os.environ.get('XDG_RUNTIME_DIR') or tempfile.gettempdir()) / 'velunori/update'
CACHE = Path(os.environ.get('XDG_CACHE_HOME') or Path.home() / '.cache') / 'velunori/update'
STATE = RUNTIME / 'state.json'
CONTROL = RUNTIME / 'control.sock'
LOCK = RUNTIME / 'run.lock'
CHECK = CACHE / 'check.json'
RELEASES = 'https://api.github.com/repos/omacom/omarchy/releases?per_page=15'
PACMAN_LOG = Path('/var/log/pacman.log')
# analyze-logs reads this path; `script` normally writes it for omarchy-update.
OMARCHY_LOG = Path('/tmp/omarchy-update.log')
UPDATE_COMMAND = ['omarchy-update', '-y']
# sudo prints this instead of its localized prompt, so a password request is
# recognised without guessing at translations.
SUDO_PROMPT = 'Password required for the update: '

STEPS = [
    ('prepare', 'Preparing', 2),
    ('snapshot', 'Snapshot', 6),
    ('keyring', 'Keyring', 4),
    ('system', 'System packages', 58),
    ('migrations', 'Migrations', 8),
    ('aur', 'AUR packages', 12),
    ('cleanup', 'Cleanup', 6),
    ('finish', 'Finishing', 4),
]
# Omarchy command -> step. Unknown commands leave the current step in place, so
# a step added by a newer Omarchy still updates correctly, just unlabelled.
COMMAND_STEPS = {
    'omarchy-update-requires-free-space': 'prepare',
    'omarchy-update-pkg-prune': 'snapshot', 'omarchy-snapshot': 'snapshot',
    'omarchy-update-dev': 'keyring', 'omarchy-update-keyring': 'keyring',
    'omarchy-update-system-pkgs': 'system', 'omarchy-update-system-pkgs-when-conflicted': 'system',
    'omarchy-migrate': 'migrations', 'omarchy-hook': 'migrations',
    'omarchy-update-aur-pkgs': 'aur',
    'omarchy-update-mise': 'cleanup', 'omarchy-update-orphan-pkgs': 'cleanup',
    'omarchy-update-analyze-logs': 'cleanup', 'omarchy-update-status': 'cleanup',
    'omarchy-update-restart': 'finish',
}
ANSI = re.compile(r'\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b[()][0-9A-B]|\x1b[=>]|[\x00-\x08\x0b\x0c\x0e-\x1f]')
PACKAGE = re.compile(r'\(\s*(\d+)/(\d+)\)\s+(upgrading|installing|reinstalling|downgrading|removing)\s+(\S+)')
UPDATE_LINE = re.compile(r'^(\S+)\s+(\S+)\s+->\s+(\S+)')


def run(argv, timeout=120):
    try:
        result = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None, ''
    return result.returncode, result.stdout


def atomic_write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix='.velunori-')
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream)
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def read_json(path, fallback=None):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return fallback


# ----------------------------------------------------------------- checking

def parse_updates(text, source):
    rows = []
    for line in text.splitlines():
        match = UPDATE_LINE.match(line.strip())
        if match:
            rows.append({'name': match.group(1), 'old': match.group(2), 'new': match.group(3), 'source': source})
    return rows


def plain(text):
    text = re.sub(r'!\[[^\]]*\]\([^)]*\)', '', text)
    text = re.sub(r'\[([^\]]+)\]\([^)]*\)', r'\1', text)
    text = re.sub(r'<[^>]+>', '', text)
    return re.sub(r'[*_`]{1,3}', '', text).strip()


def parse_notes(body, limit=80):
    """Markdown release notes -> flat blocks the panel can lay out itself."""
    blocks, paragraph = [], []

    def flush():
        if paragraph:
            blocks.append({'type': 'p', 'text': ' '.join(paragraph)})
            paragraph.clear()

    for raw in (body or '').replace('\r', '').split('\n'):
        line = raw.strip()
        heading = re.match(r'^#{1,6}\s+(.*)$', line)
        bullet = re.match(r'^(?:[-*+]|\d+[.)])\s+(.*)$', line)
        if not line:
            flush()
        elif heading:
            flush()
            blocks.append({'type': 'h', 'text': plain(heading.group(1))})
        elif bullet:
            flush()
            blocks.append({'type': 'li', 'text': plain(bullet.group(1))})
        elif plain(line):
            paragraph.append(plain(line))
    flush()
    return [block for block in blocks if block['text']][:limit]


def version_core(version):
    """'1:4.5.0-3' and 'v4.5.0' both name release 4.5.0."""
    return re.sub(r'^(\d+:)?v?', '', str(version or '')).split('-')[0]


def pick_release(releases, wanted):
    stable = [r for r in releases if isinstance(r, dict) and not r.get('draft') and not r.get('prerelease')]
    for release in stable:
        if wanted and version_core(release.get('tag_name')) == wanted:
            return release
    return stable[0] if stable else None


def fetch_release(wanted):
    request = urllib.request.Request(RELEASES, headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'velunori-update'})
    with urllib.request.urlopen(request, timeout=8) as response:
        release = pick_release(json.load(response), wanted)
    if not release:
        return None
    body = release.get('body') or ''
    links = [url.rstrip('.,)') for url in re.findall(r'https://[^\s)>\]]+', body)]
    notes = next((url for url in links if 'omarchy.org' in url), '')
    url = notes or str(release.get('html_url') or '')
    return {'version': version_core(release.get('tag_name')), 'title': plain(release.get('name') or release.get('tag_name') or ''),
            'published': release.get('published_at') or '', 'url': url if url.startswith('https://') else '',
            'blocks': parse_notes(body)}


def last_transaction(text):
    """Time and size of the most recent pacman transaction that upgraded something."""
    stamp, count, best = '', 0, None
    for line in text.splitlines():
        if '[ALPM] transaction started' in line:
            stamp, count = line[1:line.find(']')], 0
        elif '[ALPM] upgraded ' in line or '[ALPM] installed ' in line:
            count += 1
        elif '[ALPM] transaction completed' in line and count:
            best = {'at': stamp, 'count': count}
    return best


def installed_version():
    for package in ('omarchy', 'omarchy-dev'):
        code, out = run(['pacman', '-Q', package], timeout=10)
        if code == 0 and out.split():
            return out.split()[1]
    return ''


def check():
    previous = read_json(CHECK, {}) or {}
    result = {'checkedAt': int(time.time()), 'installed': installed_version(), 'updates': [], 'error': ''}
    if not shutil.which('checkupdates'):
        result['error'] = 'checkupdates is not installed (pacman-contrib).'
    else:
        code, out = run(['checkupdates', '--nocolor'], timeout=180)
        # 2 means nothing to update; anything else unexpected is a failed check.
        if code == 0:
            result['updates'] = parse_updates(out, 'repo')
        elif code != 2:
            result['error'] = 'Could not reach the package servers.'
    if shutil.which('yay') and not result['error']:
        code, out = run(['yay', '-Qua'], timeout=90)
        if code == 0:
            result['updates'] += parse_updates(out, 'aur')
    omarchy = next((row for row in result['updates'] if row['name'] in ('omarchy', 'omarchy-dev')), None)
    result['omarchy'] = omarchy
    wanted = version_core(omarchy['new'] if omarchy else result['installed'])
    try:
        result['release'] = fetch_release(wanted)
    except (OSError, ValueError):
        # Release notes are optional; keep the last ones that matched.
        cached = previous.get('release')
        result['release'] = cached if cached and cached.get('version') == wanted else None
    try:
        with PACMAN_LOG.open('rb') as stream:
            stream.seek(max(0, PACMAN_LOG.stat().st_size - 600_000))
            result['last'] = last_transaction(stream.read().decode('utf-8', 'replace'))
    except OSError:
        result['last'] = None
    atomic_write(CHECK, result)
    return result


# ------------------------------------------------------------------ running

def clean_lines(buffer):
    """Terminal output -> finished plain lines plus the unfinished remainder."""
    lines = []
    parts = buffer.split('\n')
    for part in parts[:-1]:
        # Progress bars redraw one line with carriage returns; keep the last draw.
        drawn = [text for text in (ANSI.sub('', segment) for segment in part.split('\r')) if text.strip()]
        lines.append(drawn[-1].rstrip() if drawn else '')
    return lines, parts[-1]


def process_table():
    table = {}
    for entry in os.scandir('/proc'):
        if not entry.name.isdigit():
            continue
        try:
            stat = Path(entry.path, 'stat').read_text()
            argv = Path(entry.path, 'cmdline').read_bytes().split(b'\0')
        except OSError:
            continue
        # comm may contain spaces and parentheses; the fields follow the last ')'.
        fields = stat[stat.rfind(')') + 2:].split()
        table[int(entry.name)] = (int(fields[1]), [arg.decode('utf-8', 'replace') for arg in argv if arg])
    return table


def descendants(table, root):
    children = {}
    for pid, (parent, _) in table.items():
        children.setdefault(parent, []).append(pid)
    found, queue = [], [root]
    while queue:
        for child in children.get(queue.pop(), []):
            found.append(child)
            queue.append(child)
    return found


def observe(table, root):
    """Which step is running and whether a yes/no question is waiting."""
    step, question = None, None
    order = [name for name, _, _ in STEPS]
    for pid in descendants(table, root):
        argv = table[pid][1]
        names = [os.path.basename(arg) for arg in argv[:3]]
        for name in names:
            candidate = COMMAND_STEPS.get(name)
            if candidate and (step is None or order.index(candidate) > order.index(step)):
                step = candidate
        at = names.index('gum') if 'gum' in names[:2] else -1
        if at >= 0 and argv[at + 1:at + 2] == ['confirm']:
            text = next((arg for arg in argv[at + 2:] if not arg.startswith('-')), 'Continue?')
            question = {'kind': 'confirm', 'question': text, 'pid': pid}
    return step, question


class Runner:
    def __init__(self):
        self.started = int(time.time())
        self.step = 0
        self.fraction = 0.0
        self.detail = ''
        self.prompt = None
        self.tail = []
        self.phase = 'running'
        self.exit_code = None
        self.answered_at = 0.0
        self.answered_pid = None
        self.dirty = True

    def state(self):
        done = sum(weight for _, _, weight in STEPS[:self.step])
        percent = 100 if self.phase == 'done' else min(99, round(done + STEPS[self.step][2] * self.fraction))
        steps = [{'id': name, 'label': label,
                  'state': 'done' if index < self.step or self.phase == 'done' else 'active' if index == self.step and self.phase == 'running' else 'failed' if index == self.step and self.phase == 'failed' else 'pending'}
                 for index, (name, label, _) in enumerate(STEPS)]
        prompt = None
        if self.prompt:
            prompt = {key: value for key, value in self.prompt.items() if key != 'pid'}
        return {'phase': self.phase, 'startedAt': self.started, 'finishedAt': int(time.time()) if self.phase != 'running' else 0,
                'step': self.step, 'steps': steps, 'percent': percent, 'detail': self.detail, 'prompt': prompt,
                'tail': self.tail[-200:], 'exitCode': self.exit_code, 'pid': os.getpid()}

    def enter(self, name):
        index = [step for step, _, _ in STEPS].index(name)
        if index > self.step:
            self.step, self.fraction, self.detail, self.dirty = index, 0.0, '', True

    def feed(self, line):
        if not line.strip():
            return
        self.tail.append(line[:400])
        del self.tail[:-400]
        match = PACKAGE.search(line)
        if match:
            current, total = int(match.group(1)), max(1, int(match.group(2)))
            self.fraction = max(self.fraction, min(1.0, current / total))
            self.detail = f'{current} of {total} · {match.group(4).rstrip(".")}'
        self.dirty = True


def echo_is_off(fd):
    return not termios.tcgetattr(fd)[3] & termios.ECHO


def handle_answer(runner, fd, message):
    prompt = runner.prompt
    if not isinstance(message, dict) or not prompt or message.get('kind') != prompt['kind']:
        return
    if prompt['kind'] == 'password':
        value = message.get('value')
        # Only while sudo is reading with echo off: otherwise the text would be
        # printed into the terminal and end up in the log.
        if isinstance(value, str) and value and '\n' not in value and echo_is_off(fd):
            os.write(fd, value.encode() + b'\n')
            runner.answered_at = time.monotonic()
            runner.prompt = None
    elif prompt['kind'] == 'confirm':
        os.write(fd, b'y' if message.get('value') is True else b'n')
        runner.answered_pid = prompt.get('pid')
        runner.prompt = None
    runner.dirty = True


def open_omarchy_log():
    try:
        return os.open(OMARCHY_LOG, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o644)
    except OSError:
        return None


def update():
    RUNTIME.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(RUNTIME, 0o700)
    lock = os.open(LOCK, os.O_WRONLY | os.O_CREAT, 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return 1
    CONTROL.unlink(missing_ok=True)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(CONTROL))
    os.chmod(CONTROL, 0o600)
    server.listen(4)
    server.setblocking(False)

    command = list(UPDATE_COMMAND)
    env = dict(os.environ, SUDO_PROMPT=SUDO_PROMPT, OMARCHY_UPDATE_LOGGED='1', TERM=os.environ.get('TERM') or 'xterm-256color')
    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.execvpe(command[0], command, env)
        finally:
            os._exit(127)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 120, 0, 0))
    log = open_omarchy_log()
    runner, pending, last_write, last_scan = Runner(), '', 0.0, 0.0
    alive = True
    while alive:
        readable, _, _ = select.select([fd, server], [], [], 0.25)
        if fd in readable:
            try:
                data = os.read(fd, 65536)
            except OSError:
                data = b''
            if not data:
                alive = False
            else:
                if log is not None:
                    with contextlib.suppress(OSError):
                        os.write(log, data)
                pending += data.decode('utf-8', 'replace')
                if SUDO_PROMPT.strip() in ANSI.sub('', pending.split('\n')[-1]):
                    # A prompt again right after an answer means sudo rejected it.
                    runner.prompt = {'kind': 'password', 'retry': time.monotonic() - runner.answered_at < 6}
                    pending = pending[:pending.rfind('\n') + 1]
                    runner.dirty = True
                lines, pending = clean_lines(pending)
                for line in lines:
                    runner.feed(line)
        if server in readable:
            with contextlib.suppress(OSError, ValueError):
                client, _ = server.accept()
                with client:
                    client.settimeout(2)
                    handle_answer(runner, fd, json.loads(client.makefile().readline()))
        now = time.monotonic()
        if now - last_scan > 0.4:
            last_scan = now
            step, question = observe(process_table(), pid)
            if step:
                runner.enter(step)
            waiting = runner.prompt and runner.prompt['kind'] == 'confirm'
            if question and question['pid'] != runner.answered_pid and not waiting:
                runner.prompt, runner.dirty = question, True
            elif not question and waiting:
                runner.prompt, runner.dirty = None, True
            done, status = os.waitpid(pid, os.WNOHANG)
            if done:
                runner.exit_code, alive = os.waitstatus_to_exitcode(status), False
        if runner.dirty and now - last_write > 0.15:
            atomic_write(STATE, runner.state())
            runner.dirty, last_write = False, now
    if runner.exit_code is None:
        _, status = os.waitpid(pid, 0)
        runner.exit_code = os.waitstatus_to_exitcode(status)
    if pending.strip():
        runner.feed(ANSI.sub('', pending))
    runner.prompt = None
    runner.phase = 'done' if runner.exit_code == 0 else 'failed'
    atomic_write(STATE, runner.state())
    CONTROL.unlink(missing_ok=True)
    if log is not None:
        os.close(log)
    return 0


def current_state():
    state = read_json(STATE)
    if not state:
        return {'phase': 'idle'}
    if state.get('phase') == 'running':
        # A runner that died without finishing must not look like progress.
        try:
            os.kill(int(state.get('pid', 0)), 0)
        except (OSError, ValueError):
            state.update(phase='failed', prompt=None, exitCode=None, finishedAt=int(time.time()), interrupted=True)
    return state


def answer():
    message = json.loads(sys.stdin.readline() or '{}')
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(3)
        client.connect(str(CONTROL))
        client.sendall(json.dumps(message).encode() + b'\n')


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ''
    if command == 'check':
        print(json.dumps(check()))
    elif command == 'cached':
        print(json.dumps(read_json(CHECK, {}) or {}))
    elif command == 'state':
        print(json.dumps(current_state()))
    elif command == 'run':
        return update()
    elif command == 'answer':
        answer()
    else:
        print('Usage: backend.py check|cached|state|run|answer', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
