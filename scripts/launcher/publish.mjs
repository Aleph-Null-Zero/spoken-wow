// One publish of the launcher channel: what dist/ holds now, against what the bucket says is live.
// Blobs, then manifests, then the index; the index write is the only one players see, and it is
// conditional, so two publishes racing cannot both win. Spec:
// docs/superpowers/specs/2026-10-18-launcher-delta-packs-design.md
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

import { buildManifest, diffFiles, hashFolder, revOf } from "./manifest.mjs";
import { openJson, publicKeyOf, sealJson, sha256Text } from "./sign.mjs";

export const IMMUTABLE = "public, max-age=31536000, immutable";
export const INDEX_CACHE = "public, max-age=60";

export function compareVersions(a, b) {
  const x = a.split(".").map(Number);
  const y = b.split(".").map(Number);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const d = (x[i] ?? 0) - (y[i] ?? 0);
    if (d !== 0) return Math.sign(d);
  }
  return 0;
}

// Runs fn over items, `limit` at a time; the first failure stops new work and is thrown.
export async function eachLimit(items, limit, fn) {
  let next = 0;
  let failed = false;
  const worker = async () => {
    while (!failed && next < items.length) {
      const item = items[next++];
      try {
        await fn(item);
      } catch (err) {
        failed = true;
        throw err;
      }
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
}

export async function latestSpokenRelease(fetchImpl = fetch, token = process.env.GITHUB_TOKEN) {
  const res = await fetchImpl("https://api.github.com/repos/rusty-key/spoken-wow/releases?per_page=100", {
    headers: { accept: "application/vnd.github+json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
  });
  if (!res.ok) throw new Error(`GitHub releases: HTTP ${res.status}`);
  const versions = (await res.json())
    .filter((r) => !r.draft && !r.prerelease)
    .map((r) => /^spoken\/v(\d+\.\d+\.\d+)$/.exec(r.tag_name)?.[1])
    .filter(Boolean);
  if (versions.length === 0) throw new Error("no published Spoken release");
  return versions.sort(compareVersions).at(-1);
}

async function readSigned(store, key, publicKey) {
  const o = await store.get(key);
  if (!o) return null;
  return { ...openJson(o.body.toString("utf8"), publicKey), etag: o.etag };
}

export async function publish({ store, packs, distDir, signingKey, minSpoken, latestSpoken, cache, now = new Date(), dryRun = false, log = console.log }) {
  const publicKey = publicKeyOf(signingKey);

  // Every folder and every requirement is checked before anything is read from or sent to R2.
  for (const { folder, section } of packs) {
    if (!existsSync(join(distDir, folder))) throw new Error(`dist/${folder} is missing: build it first (make ${section}-package-audio)`);
    if (compareVersions(minSpoken[section], latestSpoken) > 0) {
      throw new Error(`${folder} needs Spoken ${minSpoken[section]}, but the latest release is ${latestSpoken}`);
    }
  }

  const current = await readSigned(store, "index.json", publicKey);
  const live = current?.value.packs ?? {};
  const known = new Set();
  const changes = [];
  for (const { folder, section } of packs) {
    log(`${folder}: hashing`);
    const files = await hashFolder(join(distDir, folder), cache);
    const requires = { Spoken: `>=${minSpoken[section]}` };
    let before = [];
    const entry = live[folder];
    if (entry) {
      const m = await readSigned(store, `packs/${folder}/${entry.rev}.json`, publicKey);
      if (!m || sha256Text(m.signed) !== entry.manifestSha256) throw new Error(`packs/${folder}/${entry.rev}.json does not match the index`);
      before = m.value.files;
      for (const f of before) known.add(f.sha256);
    }
    const diff = diffFiles(before, files);
    if (diff.same && entry?.requires.Spoken === requires.Spoken) {
      log(`${folder}: unchanged`);
      continue;
    }
    log(`${folder}: +${diff.added} ~${diff.changed} -${diff.removed}`);
    changes.push({ folder, files, requires });
  }

  const blobs = new Map();
  for (const c of changes) {
    for (const f of c.files) {
      if (!known.has(f.sha256) && !blobs.has(f.sha256)) blobs.set(f.sha256, { abs: join(distDir, c.folder, ...f.path.split("/")), size: f.size });
    }
  }
  const bytes = [...blobs.values()].reduce((n, b) => n + b.size, 0);
  log(`${blobs.size} new blobs, ${bytes} bytes${dryRun ? " (dry run: nothing sent)" : ""}`);
  const result = { changed: changes.map((c) => c.folder), blobs: blobs.size, bytes, rev: null };
  if (dryRun || changes.length === 0) return result;

  let done = 0;
  await eachLimit([...blobs], 16, async ([sha, b]) => {
    if (!(await store.head(`blobs/${sha}`))) {
      await store.put(`blobs/${sha}`, await readFile(b.abs), { contentType: "application/octet-stream", cacheControl: IMMUTABLE });
    }
    if (++done % 1000 === 0) log(`  ${done}/${blobs.size} blobs`);
  });

  const rev = revOf(now);
  const nextPacks = { ...live };
  for (const c of changes) {
    const manifest = buildManifest({ packId: c.folder, rev, requires: c.requires, files: c.files });
    const sealed = sealJson(manifest, signingKey);
    // If-None-Match: a manifest is immutable and cached for a year, so a second publish within the
    // same second must fail rather than replace it.
    await store.put(`packs/${c.folder}/${rev}.json`, sealed.text, { contentType: "application/json", cacheControl: IMMUTABLE, ifNoneMatch: "*" });
    nextPacks[c.folder] = { rev, manifestSha256: sha256Text(sealed.signed), fileCount: manifest.fileCount, totalSize: manifest.totalSize, requires: c.requires };
  }
  const sealedIndex = sealJson({ generatedAt: now.toISOString(), packs: nextPacks }, signingKey);
  await store.put("index.json", sealedIndex.text, {
    contentType: "application/json", cacheControl: INDEX_CACHE,
    ...(current ? { ifMatch: current.etag } : { ifNoneMatch: "*" }),
  });
  log(`index.json now at ${rev} for ${result.changed.join(", ")}`);
  return { ...result, rev };
}
