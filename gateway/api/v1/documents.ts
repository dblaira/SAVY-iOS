import type { VercelRequest, VercelResponse } from "@vercel/node";
import { requireVerifiedBearerUser } from "../../lib/cognito-verify.js";
import { DocumentValidationError, isDocumentKey, parseEntries } from "../../lib/document-merge.js";
import {
  documentStoreAvailable,
  fetchUserDocuments,
  isMissingDocumentTable,
  mergeUserDocument,
} from "../../lib/document-store.js";
import { cors, requireApiKey } from "../../lib/http.js";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (cors(req, res)) return;
  if (!requireApiKey(req, res)) return;

  const userId = await requireVerifiedBearerUser(req, res);
  if (!userId) return;

  if (!documentStoreAvailable()) {
    res.status(503).json({ error: "Document sync requires Aurora" });
    return;
  }

  try {
    if (req.method === "GET") {
      res.status(200).json({ documents: await fetchUserDocuments(userId) });
      return;
    }

    if (req.method === "POST") {
      const body = (req.body ?? {}) as { key?: unknown; entries?: unknown; email?: unknown };
      if (!isDocumentKey(body.key)) {
        res.status(400).json({ error: "Unknown document key" });
        return;
      }
      const entries = parseEntries(body.entries);
      const email = typeof body.email === "string" ? body.email : null;
      res.status(200).json({ document: await mergeUserDocument(userId, body.key, entries, email) });
      return;
    }

    res.status(405).json({ error: "Method not allowed" });
  } catch (error) {
    if (error instanceof DocumentValidationError) {
      res.status(400).json({ error: error.message });
      return;
    }
    if (isMissingDocumentTable(error)) {
      res.status(503).json({ error: "Document sync is not set up on this database yet" });
      return;
    }
    console.error(`v1/documents ${req.method}`, error);
    res.status(500).json({ error: "Document sync failed" });
  }
}
