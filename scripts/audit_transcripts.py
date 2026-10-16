#!/usr/bin/env python3
"""Look for signs that the prover fetched the answer instead of proving it.

Scans the prover transcripts and the egress proxy log, writes a Markdown
report, and exits 1 when the run should not count:

- the prover used a web search or web fetch tool (these run on the model
  provider's side, so the egress proxy cannot stop them), or
- egress filtering was off and the prover ran a network command.

Everything else is listed for review but does not fail the run. Refused proxy
requests in particular are expected: the agent CLIs contact GitHub on their
own (Codex checks its releases), and a refused request returned nothing.
"""

import argparse
import json
import re
import sys
from pathlib import Path

WEB_TOOL = re.compile(
    r'"type"\s*:\s*"web_search"|web_search_call|\bWebSearch\b|\bWebFetch\b|\bweb_fetch\b'
)
NETWORK_COMMAND = re.compile(
    r'\b(?:curl|wget)\b[^\n"]{0,200}?https?://'
    r'|\bgit\s+(?:clone|fetch|pull|ls-remote)\b'
    r'|\bgh\s+(?:api|repo|search|pr|browse)\b'
)
# Verity's own docs name this repository, so a mention alone is not a leak.
ANSWER_SOURCE = re.compile(r'lfglabs-dev/morpho-midnight-verity|proof-sandbox|ticklib-monotonicity')
REFUSED = re.compile(r'refused on filtered domain "([^"]+)"')


def transcript_files(backend, prover_home):
    home = Path(prover_home)
    if backend in ('codex', 'claude'):
        files = [home / 'prover-events.jsonl']
    else:
        files = [p for p in (home / 'projects').rglob('*') if p.is_file()]
    return [p for p in files if p.is_file()]


def scan(files, pattern):
    hits = []
    for path in files:
        try:
            text = path.read_text(errors='replace')
        except OSError:
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            for m in pattern.finditer(line):
                start = max(m.start() - 80, 0)
                hits.append(f'{path.name}:{lineno}: …{line[start:m.end() + 80]}…')
    return hits


def claude_web_tools(files):
    """Inspect calls, not the tools advertised in Claude's init event or prose."""
    hits = []

    def calls(value):
        if isinstance(value, dict):
            if value.get('type') == 'tool_use':
                yield value.get('name', '')
            for child in value.values():
                yield from calls(child)
        elif isinstance(value, list):
            for child in value:
                yield from calls(child)

    for path in files:
        for lineno, line in enumerate(path.read_text(errors='replace').splitlines(), 1):
            try:
                event = json.loads(line)
            except ValueError:
                continue
            for name in calls(event):
                if name in ('WebSearch', 'WebFetch', 'web_search', 'web_fetch'):
                    hits.append(f'{path.name}:{lineno}: {name}')
    return hits


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--backend', required=True, choices=['cursor', 'codex', 'claude'])
    ap.add_argument('--prover-home', required=True)
    ap.add_argument('--proxy-log', help='tinyproxy log; omit when egress filtering is off')
    ap.add_argument('--out', required=True, help='Markdown report path')
    args = ap.parse_args()

    files = transcript_files(args.backend, args.prover_home)
    egress = args.proxy_log is not None
    web_tool = claude_web_tools(files) if args.backend == 'claude' else scan(files, WEB_TOOL)
    network = scan(files, NETWORK_COMMAND)
    sources = scan(files, ANSWER_SOURCE)
    refused = []
    if egress and Path(args.proxy_log).is_file():
        refused = sorted(set(REFUSED.findall(Path(args.proxy_log).read_text(errors='replace'))))

    failures = []
    if web_tool:
        failures.append('web search or web fetch tool used')
    if network and not egress:
        failures.append('network command run without egress filtering')

    def section(title, items):
        body = '\n'.join(f'- `{i}`' for i in items[:50]) or '- none'
        more = f'\n- … and {len(items) - 50} more' if len(items) > 50 else ''
        return f'## {title}\n\n{body}{more}\n'

    report = [
        '# Prover transcript audit\n',
        f'Verdict: **{"FLAGGED: " + "; ".join(failures) if failures else "clean"}**\n',
        f'Transcripts scanned: {len(files)}. Egress filtering: {"on" if egress else "off"}.\n',
        section('Web search / fetch tool use (fails the run)', web_tool),
        section('Network commands' + ('' if egress else ' (fail the run: egress was off)'), network),
        section('Mentions of the published proofs (review)', sources),
        section('Hosts refused by the egress proxy (expected; review)', refused),
    ]
    if not files:
        report.insert(2, 'Warning: no prover transcripts found; nothing was audited.\n')
    Path(args.out).write_text('\n'.join(report))
    print('\n'.join(report))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
