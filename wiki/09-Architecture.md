# Architecture

Cert Unifier is one Bash script, about nine hundred lines, with no runtime
dependencies beyond Bash 4+, OpenSSL and (optionally) `flock`. That shape is a
design decision, not an accident: the tool must be copyable to a server as a
single file and must not need a package manager, a runtime or a config file.

## Run pipeline

```text
argv
  │
  ├─ help/version pre-scan ─────────────────────────────► exit 0
  │
  ├─ option parsing ────────────────────────────────────► usage error, exit 1
  │
  ├─ root / output-directory validation ────────────────► error, exit 1
  │
  ├─ acquire_lock (flock -n) ───────────────────────────► lock held, exit 1
  │
  ├─ environment_check (version, bash, openssl, flock)
  │
  ├─ process_certbot_layout(root)     <root>/<domain>/{fullchain,privkey}.pem
  │     └─ per entry: TLD filter → validate_pem → atomic_write_pem
  │
  ├─ process_legacy_layout(root)      <dir>/<domain>_le<N>.{crt,crtca,key}
  │     └─ per entry: newest N → chain + key lookup → atomic_write_pem
  │
  ├─ emit_json (only with --json, after both scanners)
  │
  └─ exit decision from counters (0 / 1 / 2), 130 on INT/TERM
```

Both scanners always run over the same root. A tree can satisfy one layout, the
other, or both in different subdirectories.

## Per-entry flow

```text
entry found
  │
  ├─ is_allowed_tld?  ── no ──► skipped silently (debug log)
  │
  ├─ key/certificate match (verify_key_matches_cert)
  │     ├─ match ─────────────► continue
  │     ├─ mismatch ──────────► error, no bundle (or skip with --skip-pfx-on-mismatch)
  │     ├─ passphrase key ────► error, no bundle
  │     └─ unreadable ────────► error, no bundle
  │
  ├─ destination = <source dir or --output-dir>/<domain>.pem
  │
  ├─ atomic_write_pem
  │     ├─ collision check against WRITTEN_TARGETS (warn, later source wins)
  │     ├─ temp file in the destination directory
  │     ├─ assemble key, then chain (newline after every block)
  │     ├─ size floor (200 bytes) and PEM validation
  │     ├─ identical to existing? ──► chmod 0600, count unchanged, no rename
  │     ├─ --dry-run? ──────────────► count planned, no rename
  │     ├─ chmod 0600, mv -f over the destination
  │     └─ record result + fingerprint
  │
  ├─ --pfx?  ──► generate_pfx (verify again, OpenSSL -name, chmod 0600)
  └─ --check-expiry? ──► check_expiry (after a real write)
```

## Components

| Function | Responsibility |
|---|---|
| `main` | help/version pre-scan, option parsing, root and output validation, lock, environment report, calls the scanners, emits JSON, chooses the exit code |
| `show_help`, `show_version` | the two early-exit surfaces; both exit 0 |
| `is_allowed_tld` | suffix filter against `ALLOWED_TLDS` |
| `abspath` | `realpath -m`, then `readlink -f`, then a `cd`/`pwd` fallback |
| `get_pubkey_hash` | SHA-256 of the public key; exit 1 unreadable, 2 passphrase-protected |
| `verify_key_matches_cert` | 0 match, 1 mismatch, 2 passphrase-protected, 3 certificate unreadable, 4 key unreadable |
| `validate_pem` | file exists, non-empty, has a `BEGIN` header, OpenSSL parses it; warns instead of failing on a half-parsable header |
| `cat_with_newline`, `files_identical` | newline discipline and byte-identical comparison |
| `json_escape`, `add_result` | JSON string escaping and the `results` array |
| `atomic_write_pem` | the whole write contract: verify, assemble, size floor, validate, idempotency, dry-run, chmod, rename, count, PFX, expiry |
| `generate_pfx` | OpenSSL PKCS#12 export with `-name`; verifies the pair again |
| `check_expiry` | warns on expired or soon-expiring bundles; never changes the exit code |
| `acquire_lock` | non-blocking `flock`; warns and continues when locking is impossible |
| `process_certbot_layout` | scans `ROOT/*/` for the `fullchain.pem` + `privkey.pem` pair |
| `process_legacy_layout` | scans legacy directories for `_leN` generations, picks the newest, assembles the chain |
| `emit_json` | writes the summary document; status derived from counters |
| `cleanup` | `EXIT` trap; removes tracked temporary files |

## Design decisions

**Public-key comparison, not modulus hashing.** Modulus comparison is RSA-only
and silently meaningless for EC keys. The script hashes the output of
`openssl x509 -pubkey` and `openssl pkey -pubout`, so both key types use one
code path.

**Fail closed at the write boundary.** The match is verified inside
`atomic_write_pem`, immediately before assembly, not only in the PFX path. A
wrong key therefore cannot reach a bundle through a code path that forgot the
check — the 3.1.1 release exists because that assumption was previously wrong
when `--pfx` was not used.

**Atomic rename inside the destination directory.** The temporary file is
created in the target directory, so the final `mv -f` is a same-filesystem
rename: readers see either the old bundle or the new one, never a half-written
file.

**Idempotency by byte comparison.** A byte-identical bundle is not rewritten, so
mtime-triggered reloads do not fire on every cron run. The mode is still forced
to 0600, which repairs bundles written by older releases.

**Newest generation wins, numerically.** `N` is parsed with an explicit base 10,
so `_le10` beats `_le1` and `_le08` is generation 8 rather than an octal parse
error. Renewal counters only grow, so the highest generation is the newest.

**Counters instead of early exits.** A refused entry increments a counter and the
run continues, so one broken domain does not hide the other domains. The exit
code is chosen once, at the end, from the counters.

**JSON is assembled by hand.** There is no `jq` dependency: `json_escape` and the
results array build the document, which keeps a successful run's stdout
parseable on a minimal server. The 3.1.1 fix for a truncated document came from
`set -e` interacting with a bare `((i++))`; incrementing with `|| true` is the
established idiom.

**No network, no service management.** The script never requests, renews or
revokes a certificate, never reloads nginx or Apache, and never installs
anything. Certificate lifecycle and service reload belong to other tools; this
one only makes the files on disk consistent and auditable.

## Failure policy

| Failure | Log level | Counter | Entry result | Exit effect |
|---|---|---|---|---|
| Unknown option, bad value, bad root, bad output directory | ERROR | `errors` | no run | 1, no JSON |
| Another instance holds the lock | ERROR | — | no run | 1, no JSON |
| Key/certificate mismatch | ERROR | `errors` | `error`, no bundle | 1 |
| Key/certificate mismatch with `--skip-pfx-on-mismatch` | WARN | `warnings`, `skipped` | `skipped`, no bundle | 0 if nothing else failed |
| Passphrase-protected key | ERROR | `errors` | `error`, no bundle | 1 |
| No private key | ERROR | `errors` | `error`, no bundle | 1 |
| Missing chain for the newest legacy generation | ERROR | `errors` | `error`, no bundle | 1 |
| Output path is a directory | ERROR | `errors` | `error`, no bundle | 1 |
| Assembled PEM below 200 bytes | WARN | `warnings` | no result entry | 2 when nothing else matched |
| PFX export failure | ERROR | `errors` | PEM may already be written | 1 |
| Expired or soon-expiring certificate | WARN | `warnings` | bundle written | no effect |
| Missing `flock`, unusable lock path | WARN | `warnings` | normal run | no effect |

## Invariants

- A bundle is always key first, chain second; no bundle is written without a
  private key.
- A bundle is always 0600 where the filesystem implements modes.
- The only files created outside the target directories are the lock file and,
  as a fallback, a temporary file in `/tmp`.
- With `--json`, stdout carries only the JSON document.
- Temporary files are removed on exit, including on `INT`/`TERM`.
- The exit code is derived from the counters, never from prose.

## Extending

A third input layout is a new `process_<layout>_layout` function called from
`main` between the existing scanners. It must: filter by TLD, verify the
key/certificate pair (directly or through `atomic_write_pem`), call
`add_result` for every entry including refusals, and never write outside the
destination rules above. Every new behaviour needs an assertion in
[tests/run-tests.sh](https://github.com/paulmann/cert-unifier/blob/main/tests/run-tests.sh)
— the review rules are in [Testing](04-Testing).

Next: [Security model](03-Security) — the threat model behind these decisions.
