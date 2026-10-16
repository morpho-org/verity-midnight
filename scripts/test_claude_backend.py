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
        result = subprocess.run(['bash', '-euc',
            'source scripts/claude-common.sh; '
            'claude() { python3 -c "import json, sys; print(json.dumps(sys.argv[1:]))" "$@"; }; '
            'run_claude --mcp-config /opt/midnight/claude-prover.json --model opus "test prompt"'],
            cwd=ROOT, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(result.stdout)
        self.assertEqual(args[-1], 'test prompt')
        self.assertNotIn('--bare', args)
        self.assertNotIn('--dangerously-skip-permissions', args)
        self.assertEqual(args[args.index('--permission-mode') + 1], 'dontAsk')
        self.assertIn('mcp__lean-lsp__*', args[args.index('--allowedTools') + 1])
        self.assertEqual(args[args.index('--disallowedTools') + 1], 'WebSearch,WebFetch')
        self.assertIn('--strict-mcp-config', args)


if __name__ == '__main__':
    unittest.main()
