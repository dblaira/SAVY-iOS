export const PERSONAL_GRAPH_IRI = "https://understood.app/graph/personal";
export const RDF_TYPE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type";
export const UNDERSTOOD_NS = "https://understood.app/ontology#";
export const CONNECTION_CLASS = `${UNDERSTOOD_NS}Connection`;
export const LIFE_DOMAIN_CLASS = `${UNDERSTOOD_NS}LifeDomain`;
export const LABEL_PREDICATE = `${UNDERSTOOD_NS}label`;
export const CONNECTION_TYPE_PREDICATE = `${UNDERSTOOD_NS}connectionType`;
export const ENTRY_TYPE_PREDICATE = `${UNDERSTOOD_NS}entryType`;
export const IN_LIFE_DOMAIN_PREDICATE = `${UNDERSTOOD_NS}inLifeDomain`;

export const AUTHORITATIVE_SOURCE_APPS = ["understood", "recall"] as const;
export type AuthoritativeSourceApp = (typeof AUTHORITATIVE_SOURCE_APPS)[number];

export function isAuthoritativeSourceApp(sourceApp: string): sourceApp is AuthoritativeSourceApp {
  return (AUTHORITATIVE_SOURCE_APPS as readonly string[]).includes(sourceApp);
}

export function unvalidatedRdfSyncAllowed(): boolean {
  return process.env.ALLOW_UNVALIDATED_RDF_SYNC === "true";
}

export function entryIdFromIri(iri: string): string | null {
  const prefix = "https://understood.app/entry/";
  if (!iri.startsWith(prefix)) return null;
  const id = decodeURIComponent(iri.slice(prefix.length)).trim();
  return id || null;
}

export function beliefIdFromSubjectIri(iri: string): string {
  const entryId = entryIdFromIri(iri);
  if (entryId) return entryId;

  const connectionPrefix = "https://understood.app/ontology/connection/";
  if (iri.startsWith(connectionPrefix)) {
    const id = decodeURIComponent(iri.slice(connectionPrefix.length)).trim();
    if (id) return id;
  }

  const parts = iri.split("/").filter(Boolean);
  return decodeURIComponent(parts[parts.length - 1] ?? iri);
}

export function domainIdFromIri(iri: string): string {
  const prefix = "https://understood.app/ontology/domain/";
  if (iri.startsWith(prefix)) {
    const id = decodeURIComponent(iri.slice(prefix.length)).trim();
    if (id) return id;
  }
  return beliefIdFromSubjectIri(iri);
}

export function beliefSubjectIriCandidates(beliefId: string): string[] {
  const trimmed = beliefId.trim();
  if (!trimmed) return [];

  if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
    return [trimmed];
  }

  return [
    `https://understood.app/entry/${encodeURIComponent(trimmed)}`,
    `https://understood.app/ontology/connection/${trimmed}`,
  ];
}
