import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  entryDisplayLabel,
  firstDisplaySentence,
  isTruncatedHeadline,
} from "../lib/rdf-entry-export.js";

describe("entryDisplayLabel", () => {
  it("keeps a complete headline", () => {
    assert.equal(
      entryDisplayLabel("Focus on What's in Your Control", "Work on what I can."),
      "Focus on What's in Your Control"
    );
  });

  it("uses the first full sentence when the headline is truncated", () => {
    const headline = "The 10 minutes exporting your judgment builds a system th...";
    const content =
      "The 10 minutes exporting your judgment builds a system that compounds. The 10 minutes just doing the task is gone forever.";

    assert.equal(
      entryDisplayLabel(headline, content),
      "The 10 minutes exporting your judgment builds a system that compounds."
    );
  });
});

describe("isTruncatedHeadline", () => {
  it("detects ellipsis truncation", () => {
    assert.equal(isTruncatedHeadline("Short th...", "Short thing"), true);
  });
});

describe("firstDisplaySentence", () => {
  it("returns one sentence without adding a second ellipsis when it already fits", () => {
    assert.equal(
      firstDisplaySentence(
        "The 10 minutes exporting your judgment builds a system that compounds. The rest."
      ),
      "The 10 minutes exporting your judgment builds a system that compounds."
    );
  });
});
