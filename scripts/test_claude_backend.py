#!/usr/bin/env python3
"""Credential-free checks: python3 scripts/test_claude_backend.py."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('audit', ROOT / 'scripts/audit_transcripts.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class ClaudeBackendTests(unittest.TestCase):
    def backend(self, **settings):
        env = {k: v for k, v in os.environ.items()
               if not k.startswith(('AGENT_', 'MONITOR_', 'CLAUDE_'))}
        env.update(AGENT_BACKEND='claude', **settings)
        return subprocess.run(
            ['bash', '-uc', 'source scripts/agent-backend.sh; '
             'printf "%s\\n" "$AGENT_KEY_ENV" "$AGENT_AUTH_ARGS" "$AGENT_MODEL" '
             '"$AGENT_REASONING_EFFORT" "$MONITOR_REASONING_EFFORT"'],
            cwd=ROOT, env=env, text=True, capture_output=True)

    def test_auth_modes(self):
        api = self.backend()
        self.assertEqual(api.returncode, 0, api.stderr)
        self.assertEqual(api.stdout.splitlines(),
                         ['ANTHROPIC_API_KEY', '-e ANTHROPIC_API_KEY', 'opus', 'high', 'high'])
        oauth = self.backend(CLAUDE_AUTH='oauth', AGENT_MODEL='sonnet')
        self.assertEqual(oauth.returncode, 0, oauth.stderr)
        self.assertEqual(oauth.stdout.splitlines()[:3],
                         ['CLAUDE_CODE_OAUTH_TOKEN', '-e CLAUDE_CODE_OAUTH_TOKEN', 'sonnet'])
        login = self.backend(CLAUDE_AUTH='login')
        self.assertEqual(login.returncode, 0, login.stderr)
        self.assertEqual(login.stdout.splitlines()[1], '')

    def test_login_cache_copy_and_errors(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'credentials.json'
            destination = Path(tmp) / 'agent-home'
            source.write_text(json.dumps({'claudeAiOauth': {
                'accessToken': 'test-access', 'refreshToken': 'test-refresh'}}))
            args = ['python3', str(ROOT / 'scripts/claude-auth.py'), str(source), str(destination)]
            result = subprocess.run(args, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            target = destination / '.credentials.json'
            self.assertEqual(target.read_bytes(), source.read_bytes())
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            self.assertNotIn('test-access', result.stdout + result.stderr)
            for invalid in ('{', '[]', '{}', '{"claudeAiOauth":{"accessToken":"test-access"}}'):
                source.write_text(invalid)
                result = subprocess.run(args, text=True, capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('test-access', result.stdout + result.stderr)

    def test_invalid_configuration(self):
        for settings in ({'CLAUDE_AUTH': 'invalid'}, {'AGENT_REASONING_EFFORT': 'minimal'},
                         {'MONITOR_REASONING_EFFORT': 'invalid'}):
            with self.subTest(settings=settings):
                self.assertEqual(self.backend(**settings).returncode, 2)

    def test_force_requires_claude_backend(self):
        for setting in ('force', 'hard'):
            with self.subTest(TURBO_LEAN=setting):
                env = os.environ.copy()
                env.update(AGENT_BACKEND='codex', CODEX_AUTH='api-key', TURBO_LEAN=setting)
                result = subprocess.run(
                    ['bash', 'run-experiment.sh'], cwd=ROOT, env=env, text=True,
                    capture_output=True)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(
                    result.stderr.strip(),
                    f'TURBO_LEAN={setting} requires AGENT_BACKEND=claude')

    def test_web_audit_checks_calls_instead_of_advertisements(self):
        with tempfile.TemporaryDirectory() as tmp:
            events = Path(tmp) / 'prover-events.jsonl'
            events.write_text(json.dumps({'type': 'system', 'tools': ['WebSearch', 'WebFetch']})
                              + '\n' + json.dumps({'type': 'assistant', 'message': {
                                  'content': [{'type': 'text', 'text': 'Do not use WebFetch'}]}}))
            self.assertEqual(audit.transcript_files('claude', tmp), [events])
            self.assertEqual(audit.claude_web_tools([events]), [])
            for tool in ('WebSearch', 'WebFetch'):
                with events.open('a') as out:
                    out.write('\n' + json.dumps({'type': 'assistant', 'message': {'content': [
                        {'type': 'tool_use', 'name': tool, 'input': {}}]}}))
            self.assertEqual(len(audit.claude_web_tools([events])), 2)

    def test_wrapper_keeps_oauth_and_approves_lean_tools(self):
        # A shell function captures the exact CLI argv without invoking a model.
        command = ['bash', '-euc',
            'source scripts/claude-common.sh; '
            'claude() { python3 -c "import json, sys; print(json.dumps(sys.argv[1:]))" "$@"; }; '
            'run_claude --mcp-config /opt/midnight/claude-prover.json --model opus "test prompt"']
        env = os.environ.copy()
        env['CLAUDE_AUTH'] = 'oauth'
        env['TURBO_LEAN'] = '0'
        result = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(result.stdout)
        self.assertEqual(args[-1], 'test prompt')
        self.assertNotIn('--bare', args)
        self.assertNotIn('--dangerously-skip-permissions', args)
        self.assertEqual(args[args.index('--permission-mode') + 1], 'dontAsk')
        self.assertIn('mcp__lean-lsp__*', args[args.index('--allowedTools') + 1])
        self.assertNotIn('Bash(turbo-lean *)', args[args.index('--allowedTools') + 1])
        self.assertNotIn('--settings', args)
        self.assertEqual(args[args.index('--disallowedTools') + 1], 'WebSearch,WebFetch')
        self.assertEqual(args[args.index('--setting-sources') + 1], '')
        self.assertIn('--strict-mcp-config', args)

        env['TURBO_LEAN'] = '1'
        result = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(result.stdout)
        self.assertIn('Bash(turbo-lean *)', args[args.index('--allowedTools') + 1])
        self.assertNotIn('--settings', args)
        self.assertEqual(args[args.index('--setting-sources') + 1], '')

        env['TURBO_LEAN'] = 'force'
        result = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(result.stdout)
        self.assertIn('Bash(turbo-lean *)', args[args.index('--allowedTools') + 1])
        self.assertEqual(
            json.loads(args[args.index('--settings') + 1]),
            {'hooks': {'PreToolUse': [{
                'matcher': 'Bash',
                'hooks': [{
                    'type': 'command',
                    'command': 'python3 /opt/midnight/turbo-force-hook.py',
                }],
            }]}},
        )
        self.assertEqual(args[args.index('--setting-sources') + 1], '')

        env['TURBO_LEAN'] = 'hard'
        result = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(result.stdout)
        allowed = args[args.index('--allowedTools') + 1]
        self.assertIn('Bash(turbo-lean *)', allowed)
        self.assertNotIn('mcp__lean-lsp__', allowed)
        self.assertIn('--settings', args)

    def test_run_prover_turbo_prompt_is_opt_in(self):
        script = (ROOT / 'scripts/run-prover.sh').read_text()
        script = script.replace(
            'source /opt/midnight/claude-common.sh',
            f'source {ROOT / "scripts/claude-common.sh"}')
        command = ['bash', '-euc',
                   'claude() { python3 -c "import json, sys; print(json.dumps(sys.argv[1:]))" "$@"; }; '
                   'tee() { cat; }; source /dev/stdin']

        for setting in (None, '0', '1', 'force', 'hard'):
            with self.subTest(TURBO_LEAN=setting):
                env = os.environ.copy()
                env.update(AGENT_BACKEND='claude', AGENT_MODEL='opus', CLAUDE_AUTH='oauth')
                env.pop('TURBO_LEAN', None)
                if setting is not None:
                    env['TURBO_LEAN'] = setting
                result = subprocess.run(
                    command, cwd=ROOT, env=env, input=script, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                args = json.loads(result.stdout)
                prompt = args[-1]
                self.assertEqual('turbo-lean check' in prompt, setting in ('1', 'force', 'hard'))
                self.assertEqual('are blocked for you' in prompt, setting in ('force', 'hard'))
                if setting in ('force', 'hard'):
                    self.assertIn('turbo-lean build <Module> --project-dir .', prompt)
                    self.assertNotIn('run `turbo-lean build --project-dir .`', prompt)
                if setting == 'hard':
                    self.assertIn('no MCP on purpose', prompt)
                    self.assertNotIn('lean-lsp MCP is required', prompt)
                    self.assertIn('{"mcpServers":{}}',
                                  args[args.index('--mcp-config') + 1])
                else:
                    self.assertEqual('/opt/midnight/claude-prover.json',
                                     args[args.index('--mcp-config') + 1])

    def test_turbo_force_hook_blocks_lake_commands(self):
        hook = ROOT / 'scripts/turbo-force-hook.py'
        message = (
            'Blocked in this trial: lake build / lake env lean / leanrun <File.lean> are disabled. '
            'Check one declaration with turbo-lean check <File.lean> --decl <name> --project-dir . '
            'or rebuild an imported module with turbo-lean build <Module> --project-dir . ; '
            './check/check_proof.sh is allowed.'
        )
        blocked = (
            'lake build Midnight.Proof',
            'cd /work && leanrun lake build Midnight.Lemmas.X 2>&1 | tail',
            'timeout 60 lake env lean Midnight/Proof.lean',
            'lake -d . build',
            'leanrun Midnight/Proof.lean',
            'cd /work && leanrun Midnight/Lemmas/Foo.lean 2>&1 | tail',
        )
        allowed = (
            './check/check_proof.sh',
            'leanrun ./check/check_proof.sh 2>&1 | tail -20',
            'turbo-lean check Midnight/Proof.lean --decl Midnight.wExpIsMonotonic --project-dir .',
            'turbo-lean build Midnight.Lemmas.Foo --project-dir .',
            'cat check/check_proof.sh',
        )
        for command in blocked:
            with self.subTest(command=command):
                result = subprocess.run(
                    [sys.executable, str(hook)],
                    input=json.dumps({'tool_input': {'command': command}}),
                    text=True, capture_output=True)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stderr, message + '\n')
                self.assertEqual(result.stdout, '')
        for command in allowed:
            with self.subTest(command=command):
                result = subprocess.run(
                    [sys.executable, str(hook)],
                    input=json.dumps({'tool_input': {'command': command}}),
                    text=True, capture_output=True)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(result.stderr, '')

    def test_turbo_hard_hook_blocks_all_lean(self):
        hook = ROOT / 'scripts/turbo-force-hook.py'
        env = dict(os.environ, TURBO_LEAN='hard')

        def run(command):
            return subprocess.run(
                [sys.executable, str(hook)], env=env,
                input=json.dumps({'tool_input': {'command': command}}),
                text=True, capture_output=True)

        blocked = (
            'lake build Midnight.Proof',
            'lean Midnight/Proof.lean',
            'cd /work && leanrun Midnight/Lemmas/Foo.lean 2>&1 | tail',
            'leanrun ./check/check_proof.sh',
            'elan default leanprover/lean4:v4.31.0',
            'LEAN_MEMORY_MB=0 lake env lean Midnight/Proof.lean',
            'env LEAN_MEMORY_MB=0 lean Midnight/Proof.lean',
            'timeout 60 lake build Midnight',
            'bash -c "lake build"',
            'sh -c "lean Foo.lean" | tail',
            './check/check_proof.sh',
            'bash check/check_proof.sh',
            'python3 check/check_frozen.py --start',
            '/root/.elan/bin/lean Foo.lean',
        )
        allowed = (
            'turbo-lean check Midnight/Proof.lean --decl Midnight.wExpIsMonotonic --project-dir .',
            'turbo-lean build Midnight.Lemmas.Foo --project-dir .',
            'cat check/Goal.lean',
            'grep -rn "lakefile" README.md',
            'grep -rn lean Midnight/',
            'cd /work && python3 - <<\'EOF\'\nprint("lean")\nEOF',
            'ls .lake/packages',
        )
        for command in blocked:
            with self.subTest(command=command):
                result = run(command)
                self.assertEqual(result.returncode, 2)
                self.assertIn('turbo-lean check', result.stderr)
        for command in allowed:
            with self.subTest(command=command):
                result = run(command)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(result.stderr, '')

    def test_turbo_lean_check_is_not_a_network_or_answer_lookup_command(self):
        command = 'turbo-lean check ProofKit/Smoke.lean --decl ProofKit.smoke --project-dir .'
        self.assertIsNone(audit.NETWORK_COMMAND.search(command))
        self.assertIsNone(audit.ANSWER_SOURCE.search(command))


if __name__ == '__main__':
    unittest.main()
