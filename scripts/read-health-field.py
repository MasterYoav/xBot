#!/usr/bin/env python3
"""Read one field from an engine /health response on stdin, or print nothing.

Its own file for the same reason as build-engine-manifest.py: shell scripts that embed Python
inline end up quoting-sensitive, and this one is downstream of a network call whose output nobody
controls. Printing nothing on any failure is deliberate — the caller's fallback is a sane default,
not an error, because there is usually no engine running to ask.
"""

import json
import sys


def main() -> int:
    field = sys.argv[1] if len(sys.argv) > 1 else "schemaVersion"
    try:
        value = json.load(sys.stdin).get(field, "")
    except Exception:
        value = ""
    print(value if isinstance(value, (str, int)) else "")
    return 0


if __name__ == "__main__":
    sys.exit(main())
