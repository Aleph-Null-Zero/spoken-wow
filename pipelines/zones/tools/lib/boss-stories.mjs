// Data/Stories.lua, as every boss story tool writes it.

import { luaString } from "./wiki.mjs";

/** The Lua file: `stories` is { map: { key: story } }, `entry` a story as Lua. */
export function renderStories(stories, entry = luaString) {
  const blocks = Object.keys(stories)
    .map(Number)
    .sort((a, b) => a - b)
    .map((map) => {
      const lines = Object.keys(stories[map])
        .sort()
        .map((key) => `\t\t[${luaString(key)}] = ${entry(stories[map][key])},`);
      return `\t[${map}] = {\n${lines.join("\n")}\n\t},`;
    });
  return `-- The bosses' stories, by instance map and the boss's key (Data/Bosses.lua):
--   SpokenBossStories[map][key] = "The words of its story."
-- Written from the Adventure Guide's text and from warcraft.wiki.gg (CC BY-SA 4.0), rewritten in one
-- voice and kept to Classic (THIRD_PARTY.md). A boss with no entry shows that its story is not written yet.
-- Built by pipelines/zones/tools/assemble-boss-stories.mjs and apply-boss-stories.mjs.

SpokenBossStories = SpokenBossStories or {}
for map, stories in pairs({
${blocks.join("\n")}
}) do
\tSpokenBossStories[map] = stories
end
`;
}
