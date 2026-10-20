#!/usr/bin/env node
// The Discord forum #bugs-and-ideas and the GitHub issues: each post there becomes an issue, and
// when the issue is closed the post is told.
//
//   node scripts/lib/forum-issues.mjs file              file an issue for every post that has none
//   node scripts/lib/forum-issues.mjs closed <number>   reply in the post of a closed issue, and tag it
//
// Discord tells nobody when a post is made, so `file` runs on a schedule. Which posts have an
// issue is read off the issues themselves, whose footer links their post, and off the bot's
// reply in the post. Nothing is kept between runs, and a run that dies after filing but before
// replying files nothing twice.
//
// Environment:
//   DISCORD_BOT_TOKEN   a bot in the server that can read the forum, post in its threads and
//                       manage its threads (to set the Fixed and Not planned tags)
//   GITHUB_TOKEN        creates the issues
//   GITHUB_REPOSITORY   owner/repo
import { fileURLToPath } from "node:url";

import { discord, findChannel } from "./language-post.mjs";

export const FORUM = "bugs-and-ideas";
export const LABEL = "from-discord";
const FILED = "Logged on GitHub as";
const STATE_TAGS = ["Fixed", "Not planned"];
const GUILD_FORUM = 15;

// Forum tag -> repository label. A tag with no label here files no label.
export const TAG_LABELS = {
  Bug: "bug",
  Idea: "feature request",
  Quests: "Addon / Spoken Quests",
  Gossip: "Addon / Spoken Quests",
  Places: "Addon / Spoken Zones",
  Readables: "Addon / Spoken Books",
  Settings: "Addon / Spoken Player",
};

// The footer's link only: a link inside the quoted post must not stand for the post.
const FOOTER_LINK = new RegExp(`in \\[#${FORUM}\\]\\(https://discord\\.com/channels/(\\d+)/(\\d+)\\) on Discord`);

/** The forum thread an issue's footer links, or null. */
export function threadOf(body) {
  const m = (body ?? "").match(FOOTER_LINK);
  return m ? { guild: m[1], thread: m[2] } : null;
}

// A post's @name and #123 would ping a GitHub user and link an unrelated issue.
function inert(text) {
  return text.replace(/@/g, "@​").replace(/#(\d)/g, "#​$1");
}

export function labelsFor(tagNames) {
  return [...new Set([LABEL, ...tagNames.map((t) => TAG_LABELS[t]).filter(Boolean)])];
}

/** The issue for a post: its title, the post's words quoted, and a footer linking back to it. */
export function issueFor({ guild, thread, starter, tagNames }) {
  const text = inert((starter?.content ?? "").trim());
  const quoted = text ? text.split("\n").map((line) => `> ${line}`.trimEnd()).join("\n") : "> (no text)";
  const files = starter?.attachments?.length ?? 0;
  const author = starter ? starter.author.global_name ?? starter.author.username : "someone";
  const when = new Date(thread.thread_metadata?.create_timestamp ?? starter?.timestamp ?? Date.now()).toISOString();
  return {
    title: inert(thread.name),
    body: [
      "**Original report**",
      quoted,
      ...(files ? ["", `${files} attachment${files === 1 ? "" : "s"} in the Discord post.`] : []),
      "",
      "---",
      `Posted by **${author}** in [#${FORUM}](https://discord.com/channels/${guild}/${thread.id}) on Discord · ${when}`,
    ].join("\n"),
    labels: labelsFor(tagNames),
  };
}

/** What the post is told when its issue closes, and the tag it gets. */
export function closedReply(issue) {
  if (issue.state_reason === "not_planned") {
    return { tag: "Not planned", content: `This one won't be done, I'm afraid. The issue says why: ${issue.html_url}` };
  }
  if (issue.state_reason === "duplicate") {
    return { tag: null, content: `This one is already tracked in another issue: ${issue.html_url}` };
  }
  return { tag: "Fixed", content: `Good news: this one is fixed! ${issue.html_url}\nIt comes with the next Spoken release.` };
}

function github(token, repo) {
  return async (method, path, body) => {
    const res = await fetch(`https://api.github.com/repos/${repo}${path}`, {
      method,
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${token}`,
        ...(body ? { "Content-Type": "application/json" } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (!res.ok) throw new Error(`GitHub ${method} ${path}: ${res.status} ${await res.text()}`);
    return res.json();
  };
}

async function filedThreads(gh) {
  const ids = new Set();
  for (let page = 1; ; page++) {
    const batch = await gh("GET", `/issues?labels=${encodeURIComponent(LABEL)}&state=all&per_page=100&page=${page}`);
    for (const issue of batch) {
      const link = threadOf(issue.body);
      if (link) ids.add(link.thread);
    }
    if (batch.length < 100) return ids;
  }
}

async function file(api, gh) {
  const forum = await findChannel(api, FORUM);
  if (forum?.type !== GUILD_FORUM) {
    console.log(`skipped: no #${FORUM} forum`);
    return;
  }
  const tagName = Object.fromEntries((forum.available_tags ?? []).map((t) => [t.id, t.name]));
  const { threads } = await api("GET", `/guilds/${forum.guild_id}/threads/active`);
  const filed = await filedThreads(gh);
  for (const thread of threads.filter((t) => t.parent_id === forum.id && !filed.has(t.id))) {
    // A forum post's first message has the thread's id. It is gone if its author deleted it.
    const starter = await api("GET", `/channels/${thread.id}/messages/${thread.id}`).catch(() => null);
    if (starter?.author.bot) continue;
    // An issue that lost its label, or was moved or deleted, is not in `filed`; the post's
    // reply still says it was filed.
    const replies = await api("GET", `/channels/${thread.id}/messages?limit=50`);
    if (replies.some((m) => m.author.bot && m.content.startsWith(FILED))) continue;
    const tagNames = (thread.applied_tags ?? []).map((id) => tagName[id]).filter(Boolean);
    const issue = await gh("POST", "/issues", issueFor({ guild: forum.guild_id, thread, starter, tagNames }));
    await api("POST", `/channels/${thread.id}/messages`, {
      content: `${FILED} #${issue.number}: ${issue.html_url}\nI'll post here when it's fixed.`,
      allowed_mentions: { parse: [] },
      flags: 4, // SUPPRESS_EMBEDS
    });
    console.log(`#${FORUM} "${thread.name}" -> issue #${issue.number}`);
  }
}

async function closed(api, gh, number) {
  const issue = await gh("GET", `/issues/${number}`);
  // A run that waited in the queue while the issue was reopened has nothing to say.
  if (issue.state !== "closed") {
    console.log(`skipped: issue #${number} is open again`);
    return;
  }
  const link = threadOf(issue.body);
  if (!link) {
    console.log(`skipped: issue #${number} links no forum post`);
    return;
  }
  const thread = await api("GET", `/channels/${link.thread}`).catch(() => null);
  const forum = thread && await api("GET", `/channels/${thread.parent_id}`);
  if (!forum || forum.name !== FORUM) {
    console.log(`skipped: issue #${number}'s link is not a #${FORUM} post`);
    return;
  }
  const reply = closedReply(issue);
  const states = (forum.available_tags ?? []).filter((t) => STATE_TAGS.includes(t.name));
  const tag = states.find((t) => t.name === reply.tag);
  // A reopened and closed again issue changes the state; a post holds at most five tags.
  const kept = (thread.applied_tags ?? []).filter((id) => !states.some((t) => t.id === id));
  const tags = [...kept.slice(0, tag ? 4 : 5), ...(tag ? [tag.id] : [])];
  // Posting reopens an archived post by itself; the tags need it open first.
  await api("PATCH", `/channels/${thread.id}`, { archived: false, applied_tags: tags });
  await api("POST", `/channels/${thread.id}/messages`, {
    content: reply.content,
    allowed_mentions: { parse: [] },
    flags: 4, // SUPPRESS_EMBEDS
  });
  console.log(`issue #${number} closed: told "${thread.name}"${tag ? `, tagged ${reply.tag}` : ""}`);
}

async function main() {
  const [mode, number] = process.argv.slice(2);
  const token = process.env.DISCORD_BOT_TOKEN;
  const repo = process.env.GITHUB_REPOSITORY;
  if (!token) throw new Error("DISCORD_BOT_TOKEN is not set");
  if (!process.env.GITHUB_TOKEN || !repo) throw new Error("GITHUB_TOKEN and GITHUB_REPOSITORY must be set");
  const api = discord(token);
  const gh = github(process.env.GITHUB_TOKEN, repo);
  if (mode === "file") return file(api, gh);
  if (mode === "closed" && number) return closed(api, gh, number);
  throw new Error("usage: forum-issues.mjs file | closed <number>");
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main().catch((error) => {
    console.error(`error: ${error.message}`);
    process.exit(1);
  });
}
