// A release's notes, read out of a changelog: the `## <version> ...` heading and the lines under
// it, up to the next `## ` heading. The store uploads and the GitHub release quote this, so the
// notes players read and the ones in the repository are the same text.
//
//   node scripts/lib/changelog.mjs section docs/spoken/CHANGELOG.md 3.4.0

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

function linesOf(text) {
  return text.replace(/\r\n/g, "\n").split("\n");
}

function isHeadingFor(line, version) {
  return `${line} `.startsWith(`## ${version} `);
}

/**
 * The section for `version`. Throws when there is none, which is a release whose notes are
 * still under `## Unreleased`, or when there are two.
 */
export function section(text, version) {
  const lines = linesOf(text);
  const starts = lines.flatMap((line, i) => (isHeadingFor(line, version) ? [i] : []));
  if (starts.length === 0) throw new Error(`no "## ${version}" section`);
  if (starts.length > 1) throw new Error(`two "## ${version}" sections`);
  let end = lines.length;
  for (let i = starts[0] + 1; i < lines.length; i++) {
    if (lines[i].startsWith("## ")) {
      end = i;
      break;
    }
  }
  return lines.slice(starts[0], end).join("\n").trim();
}

function main([command, ...args]) {
  if (command === "section") {
    const [file, version] = args;
    process.stdout.write(section(readFileSync(file, "utf8"), version) + "\n");
  } else {
    throw new Error("usage: changelog.mjs section <file> <version>");
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    console.error(`error: ${error.message}`);
    process.exit(1);
  }
}
