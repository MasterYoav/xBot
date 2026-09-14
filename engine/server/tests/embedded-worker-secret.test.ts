import { expect, test } from "bun:test";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// The real bootstrap script, against a temporary directory rather than a container's environment.
test("the embedded worker gets a secret to hand routines to the API with", () => {
  const directory = mkdtempSync(join(tmpdir(), "xbot-worker-secret-"));
  try {
    const environment: Record<string, string | undefined> = { ...process.env };
    delete environment.WORKER_SHARED_SECRET;
    const run = Bun.spawnSync(
      [
        "sh",
        new URL("../../docker/s6/scripts/worker-secret.sh", import.meta.url)
          .pathname,
        directory,
      ],
      { env: environment },
    );
    expect(run.exitCode).toBe(0);
    const secret = join(directory, "WORKER_SHARED_SECRET");
    expect(existsSync(secret)).toBe(true);
    if (existsSync(secret)) {
      expect(readFileSync(secret, "utf8")).toMatch(/^[a-f0-9]{64}$/);
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("a secret somebody set is left alone", () => {
  const directory = mkdtempSync(join(tmpdir(), "xbot-worker-secret-"));
  try {
    const run = Bun.spawnSync(
      [
        "sh",
        new URL("../../docker/s6/scripts/worker-secret.sh", import.meta.url)
          .pathname,
        directory,
      ],
      { env: { ...process.env, WORKER_SHARED_SECRET: "chosen" } },
    );
    expect(run.exitCode).toBe(0);
    expect(existsSync(join(directory, "WORKER_SHARED_SECRET"))).toBe(false);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
