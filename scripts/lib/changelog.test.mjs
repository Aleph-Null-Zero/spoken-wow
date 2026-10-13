import { test } from "node:test";
import assert from "node:assert/strict";

import { section } from "./changelog.mjs";

const CHANGELOG = [
  "# Changelog — Spoken",
  "",
  "## Unreleased",
  "",
  "- **Something new.** *([Nucabe](https://github.com/Nucabe))*",
  "",
  "## 3.4.0 — 2026-10-12",
  "",
  "- **A change.** *([Nucabe](https://github.com/Nucabe))*",
  "",
  "## 3.3.1 — 2026-10-11",
  "",
  "- **An older one.**",
  "",
].join("\n");

test("a version's section runs from its heading to the next", () => {
  assert.equal(
    section(CHANGELOG, "3.4.0"),
    "## 3.4.0 — 2026-10-12\n\n- **A change.** *([Nucabe](https://github.com/Nucabe))*",
  );
});

test("a version is matched whole, so 3.4 is not 3.4.0", () => {
  assert.throws(() => section(CHANGELOG, "3.4"), /no "## 3.4" section/);
});

test("a release whose notes are still under Unreleased has no section", () => {
  assert.throws(() => section(CHANGELOG, "3.5.0"), /no "## 3.5.0" section/);
});

test("two sections for one version are refused", () => {
  assert.throws(() => section(`${CHANGELOG}## 3.4.0 — again\n`, "3.4.0"), /two "## 3.4.0" sections/);
});

test("a changelog checked out with CRLF reads the same", () => {
  assert.equal(section(CHANGELOG.replace(/\n/g, "\r\n"), "3.3.1"), "## 3.3.1 — 2026-10-11\n\n- **An older one.**");
});
