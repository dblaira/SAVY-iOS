// SAVY Neo4j graph schema (AuraDB / self-hosted Neo4j 5.x)
// Import nodes/edges from Aurora projection views (savy.neo4j_node_properties, savy.neo4j_edges)
// or hydrate directly from the Vercel/AWS API graph endpoints.

// ---------------------------------------------------------------------------
// Constraints and indexes
// ---------------------------------------------------------------------------
CREATE CONSTRAINT user_id IF NOT EXISTS
FOR (u:User) REQUIRE u.id IS UNIQUE;

CREATE CONSTRAINT belief_id IF NOT EXISTS
FOR (b:Belief) REQUIRE b.id IS UNIQUE;

CREATE CONSTRAINT category_name IF NOT EXISTS
FOR (c:Category) REQUIRE c.name IS UNIQUE;

CREATE CONSTRAINT reminder_id IF NOT EXISTS
FOR (r:Reminder) REQUIRE r.id IS UNIQUE;

CREATE CONSTRAINT tag_name IF NOT EXISTS
FOR (t:Tag) REQUIRE t.name IS UNIQUE;

CREATE CONSTRAINT subtask_id IF NOT EXISTS
FOR (s:Subtask) REQUIRE s.id IS UNIQUE;

CREATE INDEX belief_connection_type IF NOT EXISTS
FOR (b:Belief) ON (b.connection_type);

CREATE INDEX reminder_status IF NOT EXISTS
FOR (r:Reminder) ON (r.status);

CREATE INDEX correlates_coefficient IF NOT EXISTS
FOR ()-[c:CORRELATES_WITH]-() ON (c.coefficient);

// ---------------------------------------------------------------------------
// Seed ontology categories (13-category Adam ontology spine)
// ---------------------------------------------------------------------------
UNWIND [
  'Exercise', 'Nutrition', 'Sleep', 'Mood', 'Focus',
  'Learning', 'Relationships', 'Finance', 'Creativity',
  'Environment', 'Recovery', 'Attention', 'Leverage'
] AS categoryName
MERGE (c:Category {name: categoryName})
ON CREATE SET c.created_at = datetime();

// ---------------------------------------------------------------------------
// Node upsert templates (used by CDC / batch import from Aurora)
// ---------------------------------------------------------------------------

// User
// MERGE (u:User {id: $user_id})
// ON CREATE SET u.email = $email, u.created_at = datetime()
// ON MATCH SET u.email = coalesce($email, u.email);

// Belief
// MERGE (b:Belief {id: $id})
// SET b.headline = $headline,
//     b.connection_type = $connection_type,
//     b.pinned_at = $pinned_at;
// MATCH (u:User {id: $user_id})
// MERGE (u)-[:OWNS]->(b);

// Reminder
// MERGE (r:Reminder {id: $id})
// SET r.title = $title, r.status = $status;
// MATCH (u:User {id: $user_id})
// MERGE (u)-[:OWNS]->(r);

// Tag edge
// MATCH (r:Reminder {id: $reminder_id})
// MERGE (t:Tag {name: $tag})
// MERGE (r)-[:TAGGED]->(t);

// Subtask edge
// MATCH (r:Reminder {id: $reminder_id})
// MERGE (s:Subtask {id: $subtask_id})
// SET s.title = $title, s.done = $done, s.position = $position
// MERGE (r)-[:HAS_SUBTASK]->(s);

// ---------------------------------------------------------------------------
// Correlation edges (from latest ontology analysis)
// ---------------------------------------------------------------------------
// MATCH (a:Category {name: $category_a}), (b:Category {name: $category_b})
// MERGE (a)-[c:CORRELATES_WITH]->(b)
// SET c.coefficient = $coefficient,
//     c.type = $type,
//     c.lag = $lag,
//     c.updated_at = datetime();

// ---------------------------------------------------------------------------
// Read queries used by AWSGraphClient ontology enrichment
// ---------------------------------------------------------------------------

// Top correlations for leverage reader
// MATCH (a:Category)-[c:CORRELATES_WITH]->(b:Category)
// RETURN a.name AS category_a, b.name AS category_b,
//        c.coefficient AS coefficient, c.type AS type, c.lag AS lag
// ORDER BY abs(c.coefficient) DESC
// LIMIT 8;

// Belief neighborhood (graph intelligence, future)
// MATCH (u:User {id: $user_id})-[:OWNS]->(b:Belief)
// OPTIONAL MATCH (b)-[:REINFORCES]->(c:Category)
// RETURN b, collect(c.name) AS reinforced_categories
// ORDER BY b.pinned_at DESC NULLS LAST, b.created_at DESC
// LIMIT 24;
