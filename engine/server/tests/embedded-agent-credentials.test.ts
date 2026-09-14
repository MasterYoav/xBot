import { expect, test } from "bun:test";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Execute the actual bootstrap script without touching a machine's container environment.
test("the embedded agent can authenticate tool callbacks", () => {
  const directory = mkdtempSync(join(tmpdir(), "xbot-agent-token-"));
  try {
    const environment: Record<string, string | undefined> = {
      ...process.env,
      MANAGED_AGENT_TOKEN: "already-configured",
    };
    delete environment.AGENT_TOOL_TOKEN;
    const run = Bun.spawnSync(
      [
        "sh",
        new URL("../../docker/s6/scripts/agent-token.sh", import.meta.url)
          .pathname,
        directory,
      ],
      { env: environment },
    );
    expect(run.exitCode).toBe(0);
    const callback = join(directory, "AGENT_TOOL_TOKEN");
    expect(existsSync(callback)).toBe(true);
    if (existsSync(callback))
      expect(readFileSync(callback, "utf8")).toMatch(/^[a-f0-9]{64}$/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
