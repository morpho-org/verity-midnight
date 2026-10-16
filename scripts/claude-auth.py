#!/usr/bin/env python3
"""Validate/copy a Claude subscription login without displaying credentials.

  claude-auth.py FILE                       validate the login cache
  claude-auth.py --min-lifetime SECS FILE   also exit 3 if the access token
                                            expires within SECS seconds
  claude-auth.py FILE DIR...                copy the login into agent homes
"""
import json
from pathlib import Path
import sys
import time


def main():
    args = sys.argv[1:]
    min_lifetime = None
    if args[:1] == ['--min-lifetime']:
        min_lifetime = int(args[1])
        args = args[2:]
    try:
        auth_bytes = Path(args[0]).read_bytes()
        auth = json.loads(auth_bytes)
    except (OSError, ValueError):
        sys.exit('Cannot read Claude login cache. Run bash scripts/claude-login.sh first, '
                 'or set CLAUDE_AUTH_FILE.')
    oauth = auth.get('claudeAiOauth') if isinstance(auth, dict) else None
    if not isinstance(oauth, dict) or not oauth.get('accessToken') or not oauth.get('refreshToken'):
        sys.exit('Not a refreshable Claude subscription login. Run bash scripts/claude-login.sh.')
    if min_lifetime is not None:
        remaining = int(oauth.get('expiresAt', 0) / 1000 - time.time())
        if remaining < min_lifetime:
            print(f'Claude access token expires in {max(remaining, 0) // 60} min; '
                  f'the run needs {min_lifetime // 60} min')
            sys.exit(3)
        print(f'Claude access token valid for {remaining // 60} min')
        return
    for destination in args[1:]:
        directory = Path(destination)
        directory.mkdir(parents=True, exist_ok=True)
        target = directory / '.credentials.json'
        with target.open('wb') as output:
            target.chmod(0o600)
            output.write(auth_bytes)
    print('Claude login cache validated' if len(args) == 1
          else 'Claude login installed in isolated agent homes')


if __name__ == '__main__':
    main()
