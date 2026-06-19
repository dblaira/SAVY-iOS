#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(join(dirname(fileURLToPath(import.meta.url)), "../gateway/package.json"));
const neo4j = require("neo4j-driver");

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");
const envPath = join(root, "gateway/.env.local");

function loadEnv(path) {
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
    console.warn(`No env file at ${path}`);
  }
}

loadEnv(envPath);

const uri = process.env.NEO4J_URI;
const user = process.env.NEO4J_USER ?? "neo4j";
const password = process.env.NEO4J_PASSWORD;

if (!uri || !password) {
  console.error("NEO4J_URI and NEO4J_PASSWORD required in gateway/.env.local");
  process.exit(1);
}

const raw = readFileSync(join(root, "docs/schema/neo4j.cypher"), "utf8");
const statements = raw
  .split(";")
  .map((chunk) =>
    chunk
      .split("\n")
      .filter((line) => !line.trim().startsWith("//"))
      .join("\n")
      .trim()
  )
  .filter((statement) => /^(CREATE CONSTRAINT|CREATE INDEX)/i.test(statement));

const driver = neo4j.driver(uri, neo4j.auth.basic(user, password));
const database = process.env.NEO4J_DATABASE ?? process.env.NEO4J_USER ?? "neo4j";
const session = driver.session({ database });

try {
  for (const statement of statements) {
    await session.run(statement);
  }

  await session.run(
    `UNWIND $categories AS categoryName
     MERGE (c:Category {name: categoryName})
     ON CREATE SET c.created_at = datetime()`,
    {
      categories: [
        "Exercise", "Nutrition", "Sleep", "Mood", "Focus",
        "Learning", "Relationships", "Finance", "Creativity",
        "Environment", "Recovery", "Attention", "Leverage",
      ],
    }
  );

  console.log(`Neo4j schema applied (${statements.length} constraints/indexes).`);
} finally {
  await session.close();
  await driver.close();
}
