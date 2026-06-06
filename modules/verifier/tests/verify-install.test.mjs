import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, realpath, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  REQUIRED_FILES,
  installVerifierConfig,
  resolveSourceRoot,
} from "../bin/verify";

async function tempDir(name) {
  return mkdtemp(path.join(os.tmpdir(), `${name}-`));
}

async function writeFixtureSource(root) {
  for (const file of REQUIRED_FILES) {
    await mkdir(path.dirname(path.join(root, file.source)), { recursive: true });
    await writeFile(path.join(root, file.source), `source:${file.source}`, {
      encoding: "utf8",
      mode: 0o644,
    });
  }
}

test("resolveSourceRoot follows a PATH symlink back to the owning repo", async () => {
  const sourceRoot = await tempDir("verify-source");
  const binDir = path.join(sourceRoot, "bin");
  await writeFile(path.join(sourceRoot, "marker"), "repo", "utf8");
  await mkdir(binDir);
  const realExecutable = path.join(binDir, "verify");
  await writeFile(realExecutable, "#!/usr/bin/env node\n", "utf8");

  const pathDir = await tempDir("verify-path");
  const linkedExecutable = path.join(pathDir, "verify");
  await symlink(realExecutable, linkedExecutable);

  const expectedSourceRoot = await realpath(sourceRoot);
  assert.equal(await resolveSourceRoot(linkedExecutable), expectedSourceRoot);
});

test("installVerifierConfig copies verifier persona and prompts into the target cwd", async () => {
  const sourceRoot = await tempDir("verify-source");
  const targetRoot = await tempDir("verify-target");
  await writeFixtureSource(sourceRoot);

  const result = await installVerifierConfig({ sourceRoot, targetRoot });

  assert.deepEqual(
    result.copied.map((entry) => entry.destination).sort(),
    REQUIRED_FILES.map((entry) => entry.destination).sort(),
  );
  assert.deepEqual(result.blocked, []);

  for (const file of REQUIRED_FILES) {
    const installed = await readFile(path.join(targetRoot, file.destination), "utf8");
    assert.equal(installed, `source:${file.source}`);
  }
});

test("installVerifierConfig refuses differing existing verifier files without force", async () => {
  const sourceRoot = await tempDir("verify-source");
  const targetRoot = await tempDir("verify-target");
  await writeFixtureSource(sourceRoot);

  const conflict = ".mouthpeace/verifier/agents/verifier.md";
  await mkdir(path.dirname(path.join(targetRoot, conflict)), { recursive: true });
  await writeFile(path.join(targetRoot, conflict), "target-specific persona", {
    encoding: "utf8",
    mode: 0o644,
  });

  const result = await installVerifierConfig({ sourceRoot, targetRoot });

  assert.deepEqual(result.copied, []);
  assert.deepEqual(result.blocked.map((entry) => entry.destination), [conflict]);
  assert.equal(await readFile(path.join(targetRoot, conflict), "utf8"), "target-specific persona");
  await assert.rejects(
    readFile(path.join(targetRoot, ".mouthpeace/verifier/prompts/verify_on_stop.md"), "utf8"),
    { code: "ENOENT" },
  );
});

test("installVerifierConfig preserves an existing .mouthpeace/settings.json", async () => {
  const sourceRoot = await tempDir("verify-source");
  const targetRoot = await tempDir("verify-target");
  await writeFixtureSource(sourceRoot);

  await mkdir(path.join(targetRoot, ".mouthpeace"), { recursive: true });
  await writeFile(path.join(targetRoot, ".mouthpeace/settings.json"), "{\"skills\":[]}", {
    encoding: "utf8",
    mode: 0o644,
  });

  const result = await installVerifierConfig({ sourceRoot, targetRoot });

  assert.equal(await readFile(path.join(targetRoot, ".mouthpeace/settings.json"), "utf8"), "{\"skills\":[]}");
  assert.equal(
    result.skipped.some((entry) => entry.destination === ".mouthpeace/settings.json" && entry.reason === "preserved"),
    true,
  );
});


test("Ghostty launcher passes tmux attach as argv, not one shell string", async () => {
  const launcherSource = await readFile(
    path.resolve("apps/verifier/_shared/launcher.ts"),
    "utf8",
  );

  assert.match(
    launcherSource,
    /execFileP\("ghostty", \["-e", "tmux", "attach", "-t", tmuxSession\]\)/,
  );
  assert.doesNotMatch(
    launcherSource,
    /execFileP\("ghostty", \["-e", attachCmd\]\)/,
  );
});