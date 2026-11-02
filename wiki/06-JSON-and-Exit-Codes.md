# JSON summary and exit codes

`--json` produces one JSON document on stdout so automation does not have to
parse log lines. The exit code remains the primary signal: the document explains
what happened, the exit code says whether the run can be trusted.

## What "stdout only" means

- INFO log lines are suppressed; the JSON document is the only thing on stdout.
- WARN and ERROR lines still go to stderr, in their normal log format.
- The "how to use the generated files" block and the final INFO summary are
  suppressed as well.
- The document is written after both scanners finish, before the exit code is
  chosen. It always closes with `]}`. An interrupt (`INT`/`TERM`, exit 130) can
  end the run before the document exists.
- When the run fails before scanning starts — `--help`, `--version`, an unknown
  option or missing option value, a `ROOT_DIRECTORY` that does not exist, an
  output directory that does not exist, or another instance holding the lock —
  **no JSON is written at all**. Treat empty stdout as a hard failure and read
  stderr.

## Schema

```json
{
  "version": "3.1.1",
  "status": "success",
  "processed": 1,
  "skipped": 0,
  "planned": 0,
  "errors": 0,
  "warnings": 0,
  "results": [
    {"domain": "example.com", "status": "updated", "pem": "/etc/letsencrypt/live/example.com/example.com.pem", "fingerprint": "15:98:CF:3C:DC:1B:AC:DF:41:85:CF:E9:08:C5:39:B0:13:E2:11:DF:C5:DD:7D:05:D6:AE:F1:7C:7C:34:48:6B"}
  ]
}
```

| Field | Type | Meaning |
|---|---|---|
| `version` | string | the script version, always `3.1.1` for this release |
| `status` | string | `success`, `none` or `error`; see below |
| `processed` | integer | bundles written in this run |
| `skipped` | integer | bundles whose content was unchanged, plus entries skipped by `--skip-pfx-on-mismatch` |
| `planned` | integer | bundles a `--dry-run` would have written |
| `errors` | integer | number of ERROR log lines, not only refused entries |
| `warnings` | integer | number of WARN log lines, including environment warnings |
| `results` | array | one object per entry the scanners handled |

`errors` and `warnings` are counters over the run's log, so they can be
non-zero without any certificate problem: a host without `flock` logs two
warnings on every run, and a PFX failure adds an error even though the PEM
bundle may already have been written.

## `status`

| `status` | Condition | Typical exit code |
|---|---|---|
| `success` | `errors` is 0 and at least one bundle was processed, skipped or planned | 0 |
| `none` | `errors` is 0 and nothing was processed, skipped or planned | 2 |
| `error` | `errors` is greater than 0, whatever else happened | 1 |

A dry-run that would write something therefore reports `"status": "success"`
with `planned` greater than zero — `success` means "the run did what it was
asked", not "files were written".

## `results` entries

Every entry has `domain`, `status` and `pem`. `fingerprint` is present only for
`updated`, because a fingerprint is read from the bundle that was just written.

| Entry `status` | Meaning | Bundle written |
|---|---|---|
| `updated` | the bundle was (re)written in this run | yes, SHA-256 fingerprint included |
| `unchanged` | byte-identical content was already in place; mtime preserved and mode forced to 0600 | no |
| `dry-run` | `--dry-run` planned this write | no |
| `skipped` | `--skip-pfx-on-mismatch` skipped a mismatched entry | no |
| `error` | the entry was refused: mismatch, passphrase-protected key, no key, missing chain, unusable material, output path is a directory | no |

A refused entry still appears in `results` with the path it would have written,
so the document lists every domain the run considered, including the failures.

## Examples

Successful update (warnings would be 0 on a host with `flock`):

```json
{
  "version": "3.1.1",
  "status": "success",
  "processed": 1,
  "skipped": 0,
  "planned": 0,
  "errors": 0,
  "warnings": 0,
  "results": [
    {"domain": "example.com", "status": "updated", "pem": "/etc/letsencrypt/live/example.com/example.com.pem", "fingerprint": "15:98:CF:3C:DC:1B:AC:DF:41:85:CF:E9:08:C5:39:B0:13:E2:11:DF:C5:DD:7D:05:D6:AE:F1:7C:7C:34:48:6B"}
  ]
}
```

Dry run on a tree that needs a write:

```json
{
  "version": "3.1.1",
  "status": "success",
  "processed": 0,
  "skipped": 0,
  "planned": 1,
  "errors": 0,
  "warnings": 0,
  "results": [
    {"domain": "dry.com", "status": "dry-run", "pem": "/etc/letsencrypt/live/dry.com/dry.com.pem"}
  ]
}
```

One entry written, one refused:

```json
{
  "version": "3.1.1",
  "status": "error",
  "processed": 1,
  "skipped": 0,
  "planned": 0,
  "errors": 1,
  "warnings": 0,
  "results": [
    {"domain": "example.com", "status": "updated", "pem": "/etc/letsencrypt/live/example.com/example.com.pem", "fingerprint": "..."},
    {"domain": "mm.com", "status": "error", "pem": "/etc/letsencrypt/live/mm.com/mm.com.pem"}
  ]
}
```

Nothing matched at all:

```json
{
  "version": "3.1.1",
  "status": "none",
  "processed": 0,
  "skipped": 0,
  "planned": 0,
  "errors": 0,
  "warnings": 0,
  "results": []
}
```

## Exit codes

| Code | Condition |
|---|---|
| 0 | `--help` or `--version`; or the scan finished with no errors and at least one bundle processed, skipped or planned |
| 1 | Usage or runtime error: unknown option, missing option value, missing `ROOT_DIRECTORY`, missing output directory, another instance holding the lock, PFX requested without `openssl`; or the scan finished with `errors` greater than 0, even when other entries succeeded |
| 2 | The scan finished with no errors and nothing matched: no processed, skipped or planned entry |
| 130 | Interrupted by `INT` or `TERM`; a warning `Interrupted` is logged and temporary files are cleaned up |

There is no exit code 3.

Two consequences worth designing around:

- **Exit 1 does not mean nothing was written.** A PFX failure after a successful
  PEM rename logs an error and exits 1, while the PEM is in place. Read
  `results` to see what each entry did.
- **Exit 0 does not mean something was written.** An all-`unchanged` run exits 0
  with `processed` 0 and `skipped` greater than zero.

## Automation snippet

```bash
#!/usr/bin/env bash
set -u

json_file="$(mktemp)"
err_file="$(mktemp)"

if ./cert-unifier.sh --json /etc/letsencrypt/live >"$json_file" 2>"$err_file"; then
    # 0: applied or already correct; report per-domain status
    jq -r '.results[] | "\(.domain)\t\(.status)"' "$json_file"
else
    rc=$?
    case "$rc" in
        1)
            echo "cert-unifier refused work (see stderr and results)" >&2
            [ -s "$json_file" ] && jq -r '.results[] | select(.status=="error") | .domain' "$json_file" >&2
            ;;
        2)
            echo "nothing matched: check ROOT_DIRECTORY, the layout and the TLD filter" >&2
            ;;
        *)
            cat "$err_file" >&2
            ;;
    esac
    cat "$err_file" >&2
    rm -f "$json_file" "$err_file"
    exit "$rc"
fi

# Reload the service only after a successful run; the script never does it.
systemctl reload nginx

rm -f "$json_file" "$err_file"
```

`jq` is convenient, not required: `python3 -m json.tool` validates the document,
and the fields are stable enough to read with `grep` as a last resort.

## See also

- [Command reference](05-Command-Reference) — the options that produce these values.
- [Troubleshooting](08-Troubleshooting) — what each error message means.
