#!/usr/bin/env node
//
// @description Decode a JWT's header and payload (NO signature verification)
// @usage tiss jwt <token>
// @example tiss jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJtYXR0In0.sig | jq .payload
// @example pbpaste | tiss jwt | jq -r .payload.exp
// @needs node
//
// TypeScript leaf, run natively by node's type stripping (node >= 23.6).
// Decodes the two JSON sections of a JWT for inspection — it does NOT
// verify the signature; never treat the output as authenticated.
// Expiry timestamps pair well with `tiss dt parse`.
//
interface DecodedJwt {
  header: unknown;
  payload: unknown;
  signature_present: boolean;
}

function b64urlJson(part: string): unknown {
  return JSON.parse(Buffer.from(part, "base64url").toString("utf8"));
}

function decode(token: string): DecodedJwt {
  const parts = token.trim().split(".");
  if (parts.length < 2) throw new Error("not a JWT (expected header.payload[.signature])");
  return {
    header: b64urlJson(parts[0]),
    payload: b64urlJson(parts[1]),
    signature_present: parts.length > 2 && parts[2].length > 0,
  };
}

async function inputs(): Promise<string[]> {
  const args = process.argv.slice(2);
  if (args[0] === "-h" || args[0] === "--help" || args[0] === "help") {
    console.error("usage: tiss jwt <token>   (or one token per stdin line)");
    process.exit(0);
  }
  if (args.length) return args;
  const chunks: Buffer[] = [];
  for await (const c of process.stdin) chunks.push(c as Buffer);
  return Buffer.concat(chunks).toString("utf8").split("\n").map((l) => l.trim()).filter(Boolean);
}

(async () => {
  let status = 0;
  for (const token of await inputs()) {
    try {
      console.log(JSON.stringify(decode(token)));
    } catch (e) {
      console.error(`jwt: ${(e as Error).message}`);
      status = 1;
    }
  }
  if (status) process.exit(status);
})();
