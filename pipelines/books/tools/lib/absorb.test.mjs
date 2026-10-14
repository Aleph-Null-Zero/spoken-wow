import { test } from "node:test";
import assert from "node:assert/strict";

import { findAbsorptions } from "./absorb.mjs";

test("a minted page whose words one extracted page has in the same language is that page", () => {
  const minted = [{ lineId: "b:nA", texts: { esES: "Trotamundos de los elfos:" } }];
  const extracted = [
    { lineId: "b:900", texts: { esES: "Trotamundos de los elfos:", enUS: "Elf travellers:" } },
    { lineId: "b:901", texts: { esES: "Otra cosa" } },
  ];
  assert.deepEqual(findAbsorptions(minted, extracted), [{ from: "b:nA", to: "b:900" }]);
});

test("two extracted candidates, or two minted claimants, absorb nothing", () => {
  const extracted = [{ lineId: "b:1", texts: { esES: "X" } }, { lineId: "b:2", texts: { esES: "X" } }];
  assert.deepEqual(findAbsorptions([{ lineId: "b:nA", texts: { esES: "X" } }], extracted), []);
  assert.deepEqual(findAbsorptions(
    [{ lineId: "b:nA", texts: { esES: "Y" } }, { lineId: "b:nB", texts: { esES: "Y" } }],
    [{ lineId: "b:3", texts: { esES: "Y" } }],
  ), []);
});
