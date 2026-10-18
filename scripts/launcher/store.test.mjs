import { test } from "node:test";
import assert from "node:assert/strict";

import { ConflictError, memoryStore, r2Store, strongEtag } from "./store.mjs";

test("memoryStore honours If-Match and If-None-Match", async () => {
  const s = memoryStore();
  await s.put("k", "a", { ifNoneMatch: "*" });
  await assert.rejects(s.put("k", "b", { ifNoneMatch: "*" }), ConflictError);
  const { etag } = await s.head("k");
  await assert.rejects(s.put("k", "b", { ifMatch: '"nope"' }), ConflictError);
  await s.put("k", "b", { ifMatch: etag });
  assert.equal((await s.get("k")).body.toString(), "b");
});

test("memoryStore lists by prefix and deletes", async () => {
  const s = memoryStore();
  await s.put("blobs/1", "x");
  await s.put("packs/P/1.json", "y");
  assert.deepEqual((await s.list("blobs/")).map((o) => o.key), ["blobs/1"]);
  await s.delete("blobs/1");
  assert.equal(await s.head("blobs/1"), null);
});

test("r2Store names every missing variable", () => {
  assert.throws(() => r2Store({ R2_BUCKET: "b" }), /R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY/);
});

test("strongEtag drops the weak prefix R2 puts on compressed JSON", () => {
  assert.equal(strongEtag('W/"abc"'), '"abc"');
  assert.equal(strongEtag('"abc"'), '"abc"');
  assert.equal(strongEtag(null), null);
});
