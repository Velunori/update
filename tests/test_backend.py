import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest

BACKEND = Path(__file__).parents[1] / 'backend.py'
spec = importlib.util.spec_from_file_location('update_backend', BACKEND)
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


class CheckParsingTests(unittest.TestCase):
    def test_repo_and_aur_lines(self):
        rows = backend.parse_updates('omarchy 4.0.6-1 -> 4.5.0-3\nbroken line\nlinux 7.2.8.arch1-1 -> 7.2.9.arch1-1\n', 'repo')
        self.assertEqual([row['name'] for row in rows], ['omarchy', 'linux'])
        self.assertEqual(rows[0], {'name': 'omarchy', 'old': '4.0.6-1', 'new': '4.5.0-3', 'source': 'repo'})
        aur = backend.parse_updates('vesktop-bin 1.6.7-5 -> 1.6.9-1 [7d]\n', 'aur')
        self.assertEqual(aur[0]['new'], '1.6.9-1')

    def test_release_is_matched_by_version_and_never_a_prerelease(self):
        releases = [{'tag_name': 'v4.6.0-rc1', 'prerelease': True}, {'tag_name': 'v4.5.0'}, {'tag_name': 'v4.0.6'}, 'junk']
        self.assertEqual(backend.pick_release(releases, backend.version_core('4.0.6-1'))['tag_name'], 'v4.0.6')
        self.assertEqual(backend.pick_release(releases, backend.version_core('1:4.5.0-3'))['tag_name'], 'v4.5.0')
        self.assertEqual(backend.pick_release(releases, '9.9.9')['tag_name'], 'v4.5.0')
        self.assertIsNone(backend.pick_release([{'tag_name': 'v1', 'draft': True}], '1'))

    def test_notes_become_plain_blocks(self):
        blocks = backend.parse_notes('## What changed\n\n- New **switcher** by @a in [#12](https://example.invalid/12)\n* Faster `themes`\n\nTwo lines\nof prose.\n<img src="x">\n')
        self.assertEqual(blocks, [
            {'type': 'h', 'text': 'What changed'},
            {'type': 'li', 'text': 'New switcher by @a in #12'},
            {'type': 'li', 'text': 'Faster themes'},
            {'type': 'p', 'text': 'Two lines of prose.'},
        ])

    def test_last_transaction_ignores_ones_that_upgraded_nothing(self):
        log = textwrap.dedent('''\
            [2026-10-21T10:03:33+0200] [ALPM] transaction started
            [2026-10-21T10:03:40+0200] [ALPM] upgraded mesa (1 -> 2)
            [2026-10-21T10:03:41+0200] [ALPM] installed foo (1)
            [2026-10-21T10:03:57+0200] [ALPM] transaction completed
            [2026-10-30T00:32:57+0100] [ALPM] transaction started
            [2026-10-30T00:32:58+0100] [ALPM] removed bar (1)
            [2026-10-30T00:32:58+0100] [ALPM] transaction completed
            ''')
        self.assertEqual(backend.last_transaction(log), {'at': '2026-10-21T10:03:33+0200', 'count': 2})


class OutputTests(unittest.TestCase):
    def test_progress_redraws_collapse_to_the_last_draw(self):
        lines, rest = backend.clean_lines('\x1b[32mUpdate system packages\x1b[0m\n( 1/3) upgrading foo  [#--]\r( 1/3) upgrading foo  [###]\r\nhalf')
        self.assertEqual(lines, ['Update system packages', '( 1/3) upgrading foo  [###]'])
        self.assertEqual(rest, 'half')

    def test_package_progress_and_steps_only_move_forward(self):
        runner = backend.Runner()
        runner.enter('system')
        runner.feed('(23/37) upgrading hyprland...')
        self.assertEqual(runner.detail, '23 of 37 · hyprland')
        runner.feed('( 2/37) upgrading hooks')
        self.assertAlmostEqual(runner.fraction, 23 / 37)
        runner.enter('keyring')
        state = runner.state()
        self.assertEqual(state['steps'][3]['state'], 'active')
        self.assertTrue(8 < state['percent'] < 60)

    def test_observe_reads_step_and_question_from_the_process_tree(self):
        table = {
            10: (1, ['omarchy-update', '-y']),
            11: (10, ['bash', '/usr/bin/omarchy-update-restart']),
            12: (11, ['gum', 'confirm', 'Linux kernel has been updated. Reboot?']),
            13: (10, ['bash', '/usr/bin/omarchy-update-future-step']),
            99: (1, ['bash', '/usr/bin/omarchy-update-aur-pkgs']),
        }
        step, question = backend.observe(table, 10)
        self.assertEqual(step, 'finish')
        self.assertEqual(question['question'], 'Linux kernel has been updated. Reboot?')
        self.assertEqual(backend.observe({10: (1, ['x']), 13: (10, ['bash', 'omarchy-update-future-step'])}, 10), (None, None))


FAKE_UPDATE = '''#!/bin/bash
here=$(dirname "$0")
[[ $1 == -y && $OMARCHY_UPDATE_LOGGED == 1 ]] || exit 9
for attempt in 1 2; do
  read -rs -p "$SUDO_PROMPT" password; echo
  [[ $password == correct-horse ]] && break
  echo "Sorry, try again."
done
[[ $password == correct-horse ]] || exit 5
"$here/omarchy-update-system-pkgs"
if "$here/gum" confirm "Linux kernel has been updated. Reboot?"; then echo yes > "$here/rebooted"; fi
[[ -e $here/fail ]] && { echo "Something went wrong during the update!"; exit 3; }
echo "All done"
'''
FAKE_PKGS = '''#!/bin/bash
printf '\\033[32m\\nUpdate system packages\\033[0m\\n'
for i in 1 2 3; do printf '(%d/3) upgrading pkg%d  [#--]\\r(%d/3) upgrading pkg%d  [###]\\n' $i $i $i $i; sleep 0.5; done
'''
FAKE_GUM = '''#!/bin/bash
read -rsn1 key
[[ $key == y ]]
'''
DRIVER = '''
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location('update_backend', sys.argv[1])
backend = importlib.util.module_from_spec(spec); spec.loader.exec_module(backend)
backend.UPDATE_COMMAND = [sys.argv[2], '-y']
backend.OMARCHY_LOG = Path(sys.argv[3])
sys.exit(backend.update())
'''


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        for name, body in (('omarchy-update', FAKE_UPDATE), ('omarchy-update-system-pkgs', FAKE_PKGS), ('gum', FAKE_GUM)):
            path = self.root / name
            path.write_text(body)
            path.chmod(path.stat().st_mode | stat.S_IXUSR)
        (self.root / 'driver.py').write_text(DRIVER)
        self.env = dict(os.environ, XDG_RUNTIME_DIR=str(self.root / 'run'), XDG_CACHE_HOME=str(self.root / 'cache'))
        self.log = self.root / 'omarchy-update.log'
        self.process = None

    def tearDown(self):
        if self.process and self.process.poll() is None:
            self.process.kill()
        self.directory.cleanup()

    def start(self):
        self.process = subprocess.Popen([sys.executable, str(self.root / 'driver.py'), str(BACKEND), str(self.root / 'omarchy-update'), str(self.log)],
                                        env=self.env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def state(self):
        out = subprocess.run([sys.executable, str(BACKEND), 'state'], env=self.env, capture_output=True, text=True).stdout
        return json.loads(out)

    def wait(self, condition, message, timeout=10):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            state = self.state()
            if condition(state):
                return state
            time.sleep(0.05)
        self.fail(f'{message}; last state: {self.state()}')

    def answer(self, message):
        subprocess.run([sys.executable, str(BACKEND), 'answer'], env=self.env, input=json.dumps(message) + '\n', text=True, check=True)

    def test_password_progress_question_and_completion(self):
        self.start()
        state = self.wait(lambda s: (s.get('prompt') or {}).get('kind') == 'password', 'password is requested')
        self.assertFalse(state['prompt']['retry'])
        self.answer({'kind': 'confirm', 'value': True})  # wrong kind: ignored
        self.answer({'kind': 'password', 'value': 'wrong-battery'})
        self.wait(lambda s: (s.get('prompt') or {}).get('retry') is True, 'a rejected password is asked for again')
        self.answer({'kind': 'password', 'value': 'correct-horse'})
        state = self.wait(lambda s: s['steps'][3]['state'] == 'active' and 'of 3' in s.get('detail', ''), 'package progress is reported')
        self.assertIsNone(state['prompt'])
        state = self.wait(lambda s: (s.get('prompt') or {}).get('kind') == 'confirm', 'the reboot question is surfaced')
        self.assertEqual(state['prompt']['question'], 'Linux kernel has been updated. Reboot?')
        self.answer({'kind': 'confirm', 'value': False})
        state = self.wait(lambda s: s['phase'] == 'done', 'the update completes')
        self.assertEqual((state['percent'], state['exitCode']), (100, 0))
        self.assertTrue(all(step['state'] == 'done' for step in state['steps']))
        self.assertFalse((self.root / 'rebooted').exists())
        self.assertIn('All done', state['tail'])
        everything = json.dumps(state) + self.log.read_text(errors='replace')
        self.assertNotIn('correct-horse', everything)
        self.assertNotIn('wrong-battery', everything)
        self.assertNotIn(backend.SUDO_PROMPT.strip(), '\n'.join(state['tail']))
        self.assertEqual(self.process.wait(timeout=5), 0)
        self.assertFalse((self.root / 'run/velunori/update/control.sock').exists())

    def test_failure_names_the_step_and_a_second_run_is_refused_while_one_is_active(self):
        (self.root / 'fail').touch()
        self.start()
        self.wait(lambda s: (s.get('prompt') or {}).get('kind') == 'password', 'password is requested')
        second = subprocess.run([sys.executable, str(self.root / 'driver.py'), str(BACKEND), str(self.root / 'omarchy-update'), str(self.log)], env=self.env)
        self.assertEqual(second.returncode, 1)
        self.answer({'kind': 'password', 'value': 'correct-horse'})
        self.wait(lambda s: (s.get('prompt') or {}).get('kind') == 'confirm', 'question')
        self.answer({'kind': 'confirm', 'value': True})
        state = self.wait(lambda s: s['phase'] == 'failed', 'failure is reported')
        self.assertEqual(state['exitCode'], 3)
        self.assertEqual(state['steps'][3]['state'], 'failed')
        self.assertTrue((self.root / 'rebooted').exists())

    def test_a_vanished_runner_is_reported_as_interrupted(self):
        run = self.root / 'run/velunori/update'
        run.mkdir(parents=True)
        (run / 'state.json').write_text(json.dumps({'phase': 'running', 'pid': 2 ** 22 + 1234, 'steps': []}))
        state = self.state()
        self.assertEqual((state['phase'], state['interrupted']), ('failed', True))
        (run / 'state.json').unlink()
        self.assertEqual(self.state(), {'phase': 'idle'})


if __name__ == '__main__':
    unittest.main()
