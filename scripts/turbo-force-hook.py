#!/usr/bin/env python3
import json
import os
import re
import sys


command = json.load(sys.stdin).get('tool_input', {}).get('command', '')
if (
    re.search(r'\blake(\s+-\S+)*\s+(build|env\s+(lean|repl))\b', command)
    or re.search(r'\blake\s+-d\s+\S+\s+(build|env\s+(lean|repl))\b', command)
    or re.search(r'\bleanrun\s+\S+\.lean\b', command)
):
    print(
        'Blocked in this trial: lake build / lake env lean / leanrun <File.lean> are disabled. '
        'Check one declaration with turbo-lean check <File.lean> --decl <name> --project-dir . '
        'or rebuild an imported module with turbo-lean build <Module> --project-dir . ; '
        './check/check_proof.sh is allowed.',
        file=sys.stderr,
    )
    sys.exit(2)

if os.environ.get('TURBO_LEAN') == 'hard':
    # First word of each pipeline segment, after shell wrappers (assignments,
    # env/sudo/time/timeout, sh -c). turbo-lean and paths like .lake or
    # Proof.lean don't match.
    WRAPPERS = {'env', 'sudo', 'doas', 'time', 'nice', 'command', 'exec',
                'stdbuf', 'sh', 'bash', 'zsh', 'dash'}

    def head(segment):
        toks = segment.split()
        i = 0
        while i < len(toks):
            t = toks[i]
            if t == 'timeout':
                i += 2
            elif (t in WRAPPERS or t.startswith('-')
                  or re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*=\S+', t)
                  or re.fullmatch(r'\d+\S*', t)):
                i += 1
            else:
                break
        return toks[i].strip('"\'()') if i < len(toks) else ''

    if (
        any(os.path.basename(head(seg)) in ('lake', 'lean', 'leanrun', 'elan')
            for seg in re.split(r'[;|&`]|\$\(', command))
        or re.search(r'check/check_proof\.sh|check_frozen', command)
    ):
        print(
            'Blocked in this trial: no MCP and no shell Lean — lake, lean, leanrun, '
            'elan and the check/ scripts are disabled. Get errors with '
            'turbo-lean check <File.lean> --decl <name> --project-dir . and rebuild '
            'imported modules with turbo-lean build <Module> --project-dir . ; '
            'the host runs the full checker after you stop.',
            file=sys.stderr,
        )
        sys.exit(2)
sys.exit(0)
