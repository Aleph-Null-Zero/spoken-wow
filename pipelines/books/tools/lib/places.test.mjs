import assert from "node:assert/strict";
import { test } from "node:test";

import { isTemplateCopy } from "./places.mjs";

test("a difficulty or test copy of a creature is not a source", () => {
  assert.equal(isTemplateCopy("Alliance Sentinel (1)"), true);
  assert.equal(isTemplateCopy("Frostwolf Bowman (3)"), true);
  assert.equal(isTemplateCopy("Commander Dardosh <old> (1)"), true);
  assert.equal(isTemplateCopy("Lieutenant Murp <old>"), true);
});

test("a creature's own template is a source", () => {
  assert.equal(isTemplateCopy("Alliance Sentinel"), false);
  assert.equal(isTemplateCopy("Defias Messenger"), false);
  assert.equal(isTemplateCopy(undefined), false);
});
