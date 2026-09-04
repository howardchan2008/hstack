#!/usr/bin/env node
// Entry point so the install path does not begin with `git clone`.
//
//   npx github:howardchan2008/hstack --dry-run
//
// npm fetches the repo into a temp dir and runs this. Everything real still
// lives in install.sh and doctor.sh; this only finds them and hands over the
// arguments, so there is one installer and not two that drift.
//
// Node rather than a bash bin entry: npm bin shims on Windows wrap the target
// in a .cmd, which cannot execute a shell script. The spawn below still needs
// bash, so Windows gets a clear refusal instead of a confusing one.

"use strict";

const { spawnSync } = require("node:child_process");
const { existsSync, chmodSync } = require("node:fs");
const { join, dirname } = require("node:path");

const root = dirname(__dirname);
const args = process.argv.slice(2);

const script = args[0] === "doctor" ? "doctor.sh" : "install.sh";
const rest = args[0] === "doctor" ? args.slice(1) : args;
const target = join(root, script);

if (!existsSync(target)) {
  console.error(`hstack: ${script} is missing from ${root}`);
  console.error(
    "The package was published without its payload. Open an issue.",
  );
  process.exit(1);
}

if (process.platform === "win32") {
  console.error(
    "hstack: the hooks are bash scripts, so this installs on macOS and Linux only.",
  );
  console.error("Under WSL it works normally.");
  process.exit(1);
}

// A git archive or an npm tarball can land without the exec bit. Restore it
// rather than failing with EACCES, which reads as a broken package.
try {
  chmodSync(target, 0o755);
} catch (err) {
  if (err.code !== "EPERM" && err.code !== "EACCES") throw err;
}

const run = spawnSync("bash", [target, ...rest], {
  stdio: "inherit",
  cwd: root,
});

if (run.error) {
  console.error(`hstack: could not run ${script}: ${run.error.message}`);
  process.exit(1);
}

process.exit(run.status === null ? 1 : run.status);
