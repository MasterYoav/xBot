#!/usr/bin/env python3
"""Build the engine manifest JSON from values passed in the environment.

Its own file rather than a heredoc inside the shell script. A heredoc that interpolates shell
variables into Python source turns every value into code: CI failed with `"schemaVersion": "0` and
an unterminated string literal, because a value read from `curl` carried a newline. Reading from
`os.environ` means a value is data whatever is in it.
"""

import json
import os
import re
import sys
from pathlib import Path


def schema_version(tag: str) -> int:
    """The migration sequence as an integer, from the engine's migration tag.

    The engine reports `0025_backfill_existing_users_have_onboarded`; docs/11-packaging-and-updates.md
    specifies an integer, because rollback compares this against `backwardCompatibleWith`. The
    leading number in the tag is that sequence. Parsed here rather than stored as prose, so two
    versions of the app do not have to agree on how to compare migration names.

    Zero when there is nothing to read — no engine was running to ask, which is the normal case in
    CI. Zero is honest: it compares as "older than everything" rather than asserting a version.
    """
    match = re.match(r"\s*(\d+)", tag)
    return int(match.group(1)) if match else 0


def refuse_placeholder(image: str) -> None:
    """Stop a template manifest from being published as a real one.

    The template's all-zero digest was copied into `manifests/engine-stable.json` and into the
    app's bundled fallback, and nothing objected. The app then resolved an image that cannot
    exist, so the engine could not start at all. A placeholder is easy to produce by accident —
    it is what you get from the template when a digest is not passed in — so the refusal belongs
    here, where the manifest is written, rather than in whatever reads it later.
    """
    digest = image.rsplit("@sha256:", 1)[-1] if "@sha256:" in image else ""
    if digest and set(digest) == {"0"}:
        raise SystemExit(
            "refusing to write a manifest with the template's placeholder digest — "
            "pass the pushed image reference, e.g. ghcr.io/owner/xbot-engine@sha256:<digest>"
        )


def main() -> int:
    refuse_placeholder(os.environ["IMAGE_REF"])

    template = json.loads(Path(os.environ["TEMPLATE_PATH"]).read_text())
    template.update(
        {
            "channel": os.environ["CHANNEL"],
            "version": os.environ["VERSION"],
            "image": os.environ["IMAGE_REF"],
            "size": int(os.environ.get("IMAGE_SIZE") or 0),
            "minimumAppVersion": os.environ["MIN_APP"],
            "migration": {
                "schemaVersion": schema_version(os.environ.get("SCHEMA_TAG", "")),
                # Additive-only until the rollback decision in docs/11 is made and implemented.
                # Claiming a backward-compatible range nobody has tested would make rollback
                # confidently wrong, which is worse than refusing to roll back at all.
                "backwardCompatibleWith": 0,
            },
        }
    )
    print(json.dumps(template, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
