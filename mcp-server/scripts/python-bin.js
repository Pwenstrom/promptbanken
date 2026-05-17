const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.resolve(__dirname, "..");

function venvPython() {
  const candidates =
    process.platform === "win32"
      ? [path.join(root, ".venv", "Scripts", "python.exe")]
      : [path.join(root, ".venv", "bin", "python")];
  return candidates.find((candidate) => fs.existsSync(candidate));
}

function findPython() {
  const existingVenv = venvPython();
  if (existingVenv) {
    return { command: existingVenv, argsPrefix: [] };
  }

  const candidates =
    process.platform === "win32"
      ? [
          { command: "py", argsPrefix: [] },
          { command: "python", argsPrefix: [] },
        ]
      : [
          { command: "python3", argsPrefix: [] },
          { command: "python", argsPrefix: [] },
        ];

  for (const candidate of candidates) {
    const result = spawnSync(candidate.command, [...candidate.argsPrefix, "--version"], {
      stdio: "ignore",
      shell: false,
    });
    if (result.status === 0) {
      return candidate;
    }
  }

  return null;
}

function runPython(args, options = {}) {
  const python = findPython();
  if (!python) {
    process.stderr.write("Could not find Python. Install Python or create .venv first.\n");
    process.exit(1);
  }

  const result = spawnSync(python.command, [...python.argsPrefix, ...args], {
    cwd: root,
    stdio: options.stdio || "inherit",
    shell: false,
    env: {
      ...process.env,
      PYTHONIOENCODING: "utf-8",
      PYTHONUTF8: "1",
    },
  });

  if (result.error) {
    process.stderr.write(`${result.error.message}\n`);
    process.exit(1);
  }
  process.exit(result.status ?? 1);
}

module.exports = { root, venvPython, findPython, runPython };
