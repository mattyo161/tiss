# Cookbook: wrapping tools

The heart of tiss: take a tool you already use, keep its full surface
available, and layer on better defaults, caching, security, and
teachability. This walkthrough builds `tiss ssm get` — a real command
in the core — and names the patterns as it goes.

## The itch

Fetching SSM parameters is three different aws subcommands with
JSON-envelope output and a flag you always forget:

```sh
aws ssm get-parameter --name /develop/db/password --with-decryption
aws ssm get-parameters --names /a /b --with-decryption
aws ssm get-parameters-by-path --path /develop --with-decryption
```

And it's slow, and you call it constantly. What you *want*:

```sh
tiss ssm get --name /develop/db/password
tiss ssm get --names /a,/b
tiss ssm get --path /develop | jq -r '.Name + " = " + .Value'
```

One verb. jsonl out. Cached for an hour, encrypted at rest. That's
`scripts/ssm/get.sh` — read it alongside this page.

## Pattern 1: one verb, many subcommands

Map *your* mental model onto the tool's API. The `case "$mode"` block
picks the aws subcommand and the matching jq unwrap:

```bash
case "$mode" in
  name)  aws_args+=(get-parameter --name "$value");        filter='.Parameter' ;;
  names) aws_args+=(get-parameters --names ...);           filter='.Parameters[]' ;;
  path)  aws_args+=(get-parameters-by-path --path "$value"); filter='.Parameters[]' ;;
esac
```

The jq filter turns each envelope into **jsonl** — one parameter per
line, ready for the next pipe. That's the "everything speaks jsonl"
principle doing real work.

## Pattern 2: bake in the flag you always forget

`--with-decryption` is on by default; `--no-decryption` turns it off
(the `--no-` convention). Good defaults are the whole point of a
wrapper — and the `--no-` escape hatch means you never *lose* the
native behavior.

## Pattern 3: front it with cacheExec

```bash
cacheExec --encrypt --duration 1h aws ssm get-parameters-by-path ...
```

- Repeat calls inside the hour return instantly from the store.
- `--encrypt` because parameters are secrets: the cache is encrypted
  with your tiss identity, never plaintext on disk.
- The cache key includes `AWS_PROFILE` / `AWS_REGION` automatically —
  `AWS_PROFILE=prod tiss ssm get ...` and dev never cross-contaminate.
- Failures are never cached. Cache control comes in three uniform
  flags, scavenged from anywhere in the args (so `tiss ssm
  describe-parameters --recache` works without the wrapper doing
  anything): `--refresh` (rerun, replace on success), `--recache`
  (invalidate first — gone even if the rerun fails), `--no-cache`
  (bypass entirely; cascades to nested cacheExec calls). A literal
  `--` protects tools with their own such flags:
  `cacheExec -- docker build --no-cache .`

Cache the **raw** tool output and run the jq unwrap on every read —
that keeps one cache entry serving any downstream filter.

## Pattern 4: pass the rest through

Unrecognized args go straight to aws (`extra+=("$1")`), so
`--max-results 5` or `--recursive` just work. Wrap the 90% case,
never wall off the other 10%.

## Pattern 5: a `_self` handler for everything else

`scripts/ssm/` only defines `get` — so what happens to
`tiss ssm describe-parameters`? The namespace's `_self.sh` handler
catches every subcommand no dedicated script owns, and it's smart
about intent:

```bash
case "${1:-}" in
  get-* | describe-* | list-*)   # read-only: cache it, encrypted
    cacheExec --duration "$TISS_SSM_CACHE_DURATION" --encrypt aws ssm "$@" ;;
  *)                             # may mutate: NEVER cache, narrate it
    learnExec aws ssm "$@" ;;
esac
```

That last case is the important lesson: a blanket
`cacheExec aws ssm "$@"` would cache `put-parameter` — a repeated write
would silently *not run*. Route by intent: **reads get cached, writes
get narrated, writes never get cached.** The wrapper adds; it never
subtracts. (For dumb name mapping without logic, `tissCommandAlias`
still exists: `tf` → `terraform`.)

## Pattern 6: grow it in your overlay first

Company-specific defaults don't belong in the core. Same mechanics,
your tree:

```sh
mkdir -p ~/work/acme/scripts/ssm
$EDITOR ~/work/acme/scripts/ssm/get.sh   # e.g. force --path prefix /acme
chmod +x ~/work/acme/scripts/ssm/get.sh  # ← do not forget this
tiss pile add ~/work/acme
```

Your version now shadows the core's (`tiss pile list` shows it),
and `etc/config.sh` in your tree can carry the account IDs and region
defaults it needs — overridable by environment variables, always.

## The takeaway shape

Every good wrapper is the same sandwich:

```
parse args (any order, help triad, --no- negation, extras collected)
  → map your verb onto the tool's real command
    → front with cacheExec / narrate with learnExec as appropriate
      → emit jsonl
        → pass everything else through
```

Steal `scripts/ssm/get.sh` as the template; `scripts/db/query.sh` and
`scripts/tf/apply.sh` show the same shape with different fillings
(encrypted creds; hard plan-file discipline).
