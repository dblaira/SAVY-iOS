import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { syncAllAxiomRdf } from "../lib/rdf-axiom-sync.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const envPath = join(__dirname, "../.env.local");

function loadEnv(path: string) {
  try {
    const raw = readFileSync(path, "utf8");
    for (const line of raw.split("\n")) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const idx = trimmed.indexOf("=");
      if (idx === -1) continue;
      const key = trimmed.slice(0, idx).trim();
      const value = trimmed.slice(idx + 1).trim();
      if (!process.env[key]) process.env[key] = value;
    }
  } catch {
    // optional
  }
}

loadEnv(envPath);

async function main() {
  const result = await syncAllAxiomRdf();
  console.log(
    `Synced ${result.axiomCount} personal axioms (${result.inserted} triple rows inserted). savy.rdf_triples now has ${result.totalRdfRows} rows in graph scope.`
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
