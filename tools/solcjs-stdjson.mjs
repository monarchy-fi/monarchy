import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const solc = require("solc");
let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (c) => (input += c));
process.stdin.on("end", () => process.stdout.write(solc.compile(input)));
