import { syncAllAxiomRdf } from "../lib/rdf-axiom-sync.js";
import { syncAllBeliefEntryRdf } from "../lib/rdf-entry-sync.js";

async function main() {
  const beliefs = await syncAllBeliefEntryRdf();
  const axioms = await syncAllAxiomRdf();
  console.log(
    JSON.stringify(
      {
        mode: "adam-beliefs-graph-sync",
        beliefs,
        axioms,
      },
      null,
      2
    )
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
