const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { root, venvPython, findPython } = require("./python-bin");

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: root,
    stdio: "inherit",
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
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

const venvDir = path.join(root, ".venv");
let pythonPath = venvPython();

if (!pythonPath) {
  const python = findPython();
  if (!python) {
    process.stderr.write("Could not find Python. Install Python before running setup.\n");
    process.exit(1);
  }
  fs.mkdirSync(path.dirname(venvDir), { recursive: true });
  run(python.command, [...python.argsPrefix, "-m", "venv", venvDir]);
  pythonPath = venvPython();
}

if (!pythonPath) {
  process.stderr.write("Could not find Python inside backend/.venv after creating it.\n");
  process.exit(1);
}

run(pythonPath, ["-m", "pip", "install", "-r", "requirements.txt"]);
