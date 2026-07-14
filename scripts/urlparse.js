#!/usr/bin/env node
//
// @description Break URLs into their parts, as jsonl
// @usage tiss urlparse <url...>
// @example tiss urlparse "https://user@api.example.com:8443/v1/items?limit=5&page=2#top"
// @example pbpaste | tiss urlparse | jq .query
// @needs node
//
// Stop squinting at query strings: every component as a JSON field,
// query params unpacked into an object, one line per URL — jq-ready.
// Args or stdin lines, like every tiss command.
//
"use strict";

function parse(raw) {
  const u = new URL(raw);
  const query = {};
  for (const [k, v] of u.searchParams) {
    query[k] = k in query ? [].concat(query[k], v) : v;
  }
  return {
    href: u.href,
    protocol: u.protocol.replace(/:$/, ""),
    username: u.username || undefined,
    hostname: u.hostname,
    port: u.port ? Number(u.port) : undefined,
    pathname: u.pathname,
    query: Object.keys(query).length ? query : undefined,
    hash: u.hash ? u.hash.slice(1) : undefined,
  };
}

async function inputs() {
  const args = process.argv.slice(2);
  if (args[0] === "-h" || args[0] === "--help" || args[0] === "help") {
    console.error("usage: tiss urlparse <url...>   (or one URL per stdin line)");
    process.exit(0);
  }
  if (args.length) return args;
  const chunks = [];
  for await (const c of process.stdin) chunks.push(c);
  return chunks.join("").split("\n").map((l) => l.trim()).filter(Boolean);
}

(async () => {
  let status = 0;
  for (const raw of await inputs()) {
    try {
      console.log(JSON.stringify(parse(raw)));
    } catch {
      console.error(`urlparse: not a valid URL: ${raw}`);
      status = 1;
    }
  }
  if (status) process.exit(status);
})();
