# Engine image manifest (M3)

Template for the pinned-digest manifest the Mac app will fetch at update time.
See `docs/11-packaging-and-updates.md`.

## Local dev

```sh
scripts/build-engine-image.sh       # tags xbot/engine:1 locally
scripts/check-engine-health.sh      # probes /health after start
scripts/generate-engine-manifest.sh # emits manifest JSON from the local image
```

## Ship criterion (not wired yet)

1. CI builds `engine/Dockerfile` and pushes `ghcr.io/<org>/xbot-engine@sha256:…`
2. CI emits a manifest JSON matching `scripts/engine-manifest.template.json`
3. The Mac app verifies digest + signature before first run of a new image

The publish workflow is intentionally deferred until a GHCR org and signing key exist.
