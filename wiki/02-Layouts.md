# Layouts

Cert Unifier recognises two input layouts by file name. Everything else is
reported as "No matching certificates found" (exit code 2) and left alone: the
script never guesses at a third convention.

Both scanners run over the same `ROOT_DIRECTORY` on every invocation; a tree
that contains both shapes is processed by both.

## Certbot / `live`

```text
<root>/
├─ example.com/
│  ├─ fullchain.pem    leaf certificate + intermediates
│  └─ privkey.pem      private key
└─ example.net/
   ├─ fullchain.pem
   └─ privkey.pem
```

| Input | Required |
|---|---|
| `<root>/<domain>/fullchain.pem` | yes |
| `<root>/<domain>/privkey.pem` | yes |

- The domain name is the directory name; nothing inside the certificate is used
  to derive it.
- Output: `<root>/<domain>/<domain>.pem`, or `<output-dir>/<domain>.pem` with
  `-o, --output-dir`.
- The bundle is `privkey.pem` followed by `fullchain.pem`, unchanged.
- A directory that has only one of the two files is skipped without an error and
  without a result entry — a half-populated directory is treated as "not this
  layout", not as a failure.

The scanner reads the immediate subdirectories of `ROOT` only, and
`--recursive` does not change that. Point `ROOT` at the `live/` directory, not
at a single `live/<domain>/` directory: a domain directory on its own matches
nothing, because Certbot material is expected one level below `ROOT`.
Measured: `cert-unifier.sh --json .../live/example.com` answers
`"status": "none"` and exits 2.

## Legacy `_leN`

```text
<root>/
├─ example.ru_le10.crt     leaf certificate
├─ example.ru_le10.crtca   chain
├─ example.ru_le10.key     private key (preferred)
├─ example.ru_le1.crt      older generation, ignored
├─ example.ru_le1.crtca
├─ example.ru_le1.key
└─ example.ru.pem          output
```

| Role | File name |
|---|---|
| Leaf certificate | `<domain>_le<N>.crt` |
| Chain | `<domain>_le<N>.crtca` |
| Private key, first choice | `<domain>_le<N>.key` with the same `N` as the chosen leaf |
| Private key, fallback | `<domain>.key` |

Rules that matter in practice:

- **`N` is one or more digits and is compared numerically.** Several
  generations of one domain may sit in one directory; the highest `N` wins, so
  `_le10` beats `_le1` and an old generation never overwrites a newer one.
  The digits are parsed as decimal, so `_le08` is generation 8.
- **Only the newest generation is consumed.** If `_le2.crt` exists but
  `_le2.crtca` does not, the entry fails with
  `Missing chain file for <domain>: ..._le2.crtca` — the complete `_le1`
  generation is not used as a fallback.
- **The private key is optional only in the sense that it is looked up in two
  places.** If neither `<domain>_le<N>.key` nor `<domain>.key` exists, the entry
  is refused with `No private key found for <domain>` and no bundle is written.
- **Output**: `<dir>/<domain>.pem` beside the sources, or
  `<output-dir>/<domain>.pem` with `-o`. The bundle is the private key, then the
  leaf, then the `.crtca` chain.
- A file that matches the shell glob but not the `_le<digits>.crt` pattern is
  reported as `Unexpected certificate name` and ignored.

Each directory is scanned independently: two directories may produce two
bundles for the same domain name, which is one of the ways an output collision
happens (see below).

## Scanning depth

| Layout | `ROOT` itself | Immediate subdirectories | Deeper levels |
|---|---|---|---|
| Certbot / `live` | no | yes | never, `--recursive` has no effect |
| Legacy `_leN` | yes | yes | only with `--recursive` |

This is the single most common reason for an unexpected exit code 2: the tree
is deeper than the default scan, or `ROOT` points one level too low or too high.
See [Troubleshooting](08-Troubleshooting).

## Output directory

`-o, --output-dir PATH` moves every bundle to `PATH/<domain>.pem` for both
layouts. `PATH` must already exist and be a directory; otherwise the run stops
with exit code 1 before scanning.

Two sources can resolve to the same file — for example a Certbot entry and a
legacy entry for the same domain under `-o`, or the same domain in two legacy
directories. The script then logs
`Output collision: <path> is produced by more than one source — the later one wins`
and does not pretend the collision did not happen. Keep domains unique per
output directory if that warning appears.

## TLD filter

Only names that end in an allowed suffix are processed. The default list is
`ru com`; change it with `-t, --tlds LIST`, the `ALLOWED_TLDS` environment
variable, or switch it off entirely with `--no-tld-filter`.

| Name | Default filter (`ru com`) |
|---|---|
| `example.com` | passes (ends in `.com`) |
| `shop.example.ru` | passes (ends in `.ru`) |
| `example.org` | filtered out |
| `example.com-0001` | filtered out — the name ends in `-0001`, not `.com` |

Matching is suffix-based, so a subdomain of an allowed TLD passes. A tree that
is entirely filtered out ends with exit code 2 and a warning that names
`--no-tld-filter`; that warning is the hint, not evidence that the tree is
empty.

Next: [Command reference](05-Command-Reference) — every option and default.
