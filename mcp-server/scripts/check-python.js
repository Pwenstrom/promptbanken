const { runPython } = require("./python-bin");

runPython(["-m", "compileall", "server"]);
