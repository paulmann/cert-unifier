# Troubleshooting

Every message below is printed by the script itself. Find the symptom, then the
cause and the fix. Exit codes: `0` done, `1` refused or failed, `2` nothing
matched, `130` interrupted — see
[JSON summary and exit codes](06-JSON-and-Exit-Codes).

## Quick table

| Symptom | Likely cause | Fix |
|---|---|---|
| Exit 2, `No matching certificates found in <root>` | wrong root, wrong scan depth, unsupported layout or wrong file names | point `ROOT` at the `live/` directory or the directory that holds the `_leN` files; add `--recursive` for nested legacy trees |
| Exit 2 with the `TLD filter is active` hint | domains do not end in an allowed suffix (`ru com` by default) | pass `-t`, set `ALLOWED_TLDS`, or use `--no-tld-filter` |
| Exit 2 when pointing at one `live/<domain>/` directory | the Certbot scanner reads the immediate subdirectories of `ROOT` | point at `live/` instead |
| Exit 1, `Private key does NOT match certificate for <domain>` | the key belongs to another certificate or another generation | check the source pair, and for legacy trees the highest `_leN` generation |
| Exit 1, `Private key is passphrase-protected: <file>` | the key is encrypted and cannot be verified non-interactively | decrypt the key for the bundle, or use `--no-key-validation` deliberately |
| Exit 1, `No private key found for <domain>` | legacy directory has `.crt`/`.crtca` but no `.key` | add `<domain>_le<N>.key` or `<domain>.key` |
| Exit 1, `Missing chain file for <domain>: ..._le<N>.crtca` | the newest generation has no chain file | provide the `.crtca` for that generation; older generations are not used as a fallback |
| Exit 1, `Another instance is running (lock: ...)` | a previous run still holds the lock | wait for it to finish, or point `CERT_UNIFIER_LOCK` at a separate lock file |
| Warning `flock not available — running without lock` | `flock` is not installed | install `util-linux`, or accept unlocked runs on a tree only one job touches |
| Warning `Cannot create lock file ... — continuing unlocked` | the lock path is not writable | set `CERT_UNIFIER_LOCK` to a writable path |
| Exit 1, `Output directory does not exist: <path>` | `-o` points at a missing directory | `install -d` it first |
| Exit 1, `Output path is a directory: <path>` | a directory is named `<domain>.pem` | remove or rename it |
| Exit 1, `--expiry-days requires a non-negative integer` | the value is not a number | pass digits only |
| Exit 1, `Unknown option: <arg>` | typo, or an option from a newer release | run `--help` and use a supported option |
| Warning `Assembled PEM too small (N bytes) — skipping` | the chain file is empty or truncated | inspect the source files; the entry is not written |
| Warning `OpenSSL could not fully validate <file>` | the PEM has a header but does not parse | re-create the source material; the entry is normally refused at the match check |
| Exit 1 but the bundle was updated | a PFX export failed after the PEM rename | read `results` in `--json`, check the PFX error on stderr |
| `--json` output does not parse | stderr was mixed into stdout, or the run failed before scanning and stdout is empty | capture `2>` separately and treat empty stdout as failure |
| No expiry warnings appear | `--check-expiry` only checks bundles written in this run | inspect the existing bundle with `openssl x509 -enddate`, or run after renewal |
| Bundle is still 0644 | the filesystem does not implement modes (FAT, some network mounts, Git Bash emulation) | fix the mount or move the target to a POSIX filesystem |
| Script fails with syntax or `shopt` errors on macOS | it is running under the system Bash 3.2 | run it with a Bash 4+ interpreter, e.g. Homebrew's |

## Exit 2: nothing matched

The scan found no entry it could process. In order of frequency:

1. **Wrong root.** The Certbot layout expects `<root>/<domain>/fullchain.pem`
   and `privkey.pem`, so `ROOT` is the `live/` directory. A single
   `live/<domain>/` directory contains no subdirectories with that pair and
   matches nothing.
2. **Wrong depth.** The legacy layout scans `ROOT` and its immediate
   subdirectories; deeper trees need `--recursive`. `--recursive` does not make
   the Certbot scanner descend.
3. **The TLD filter.** Names that do not end in an allowed suffix are skipped.
   When the filter is the cause, the run also prints
   `TLD filter is active (ALLOWED_TLDS='ru com'); retry with --no-tld-filter`.
4. **File names.** A legacy entry needs all three roles: `<domain>_le<N>.crt`,
   `<domain>_le<N>.crtca`, and `<domain>_le<N>.key` or `<domain>.key`. A pile of
   `.cer`/`ca.cer` files from another ACME client is a different layout and is
   not detected at all.

Start with `--dry-run --verbose`, which logs which directories were scanned and
which were skipped by the TLD filter.

## Exit 1: entries refused

The script writes nothing for a refused entry — that is the point of the
behaviour contract. Each refusal names its reason:

- **Mismatch.** The private key does not belong to the leaf certificate.
  Certbot rotates keys on renewal and legacy trees keep generations side by
  side, so verify which files are current. `--skip-pfx-on-mismatch` turns the
  refusal into a skip (warning, exit 0, still no bundle).
- **Passphrase-protected key.** The script never prompts. Decrypt the key it
  must bundle, or accept unverified material explicitly with
  `--no-key-validation` and a warning.
- **No private key.** Legacy layouts look for `<domain>_le<N>.key` first and
  `<domain>.key` second; neither existing is an error, not a warning.
- **Missing chain.** The chain is required for the generation that wins the
  newest-wins rule, for example `<domain>_le10.crtca`. A complete older
  generation does not rescue the entry.
- **Unusable material.** A structurally invalid key or certificate fails the
  public-key comparison, which ends the entry with exit 1.

`--json` lists every refused domain in `results` with `"status": "error"`, so a
single exit code does not hide which entries failed.

## Locking

The run takes an exclusive lock with `flock -n` before scanning. Behaviour:

- Lock held → `Another instance is running` and exit 1. No bundle is touched.
- `flock` missing → two warnings and the run continues unlocked. Fine for a
  single scheduled job; risky when two jobs can overlap on the same tree.
- Lock file not creatable → a warning and an unlocked run. Relocate it with
  `CERT_UNIFIER_LOCK=/run/cert-unifier.lock` (or any writable path).
- The lock file itself is not state: it is safe to leave in place and safe to
  delete when no run is active.

## PFX-specific failures

| Message | Meaning |
|---|---|
| `openssl missing — cannot generate PFX` | `--pfx` was requested without OpenSSL |
| `Skipping PFX <file> (passphrase-protected key)` | warning only; the PEM path already refused the entry |
| `Skipping PFX <file> (key/cert mismatch)` | `--skip-pfx-on-mismatch` is set; no PFX is written |
| `Key does not match certificate — aborting PFX for <file>` | mismatch without the skip flag; the run exits 1 |
| `PFX generation failed for <file>: <openssl error>` | OpenSSL rejected the export; the PEM may already be written |

An empty PFX password is accepted and produces an unencrypted `.pfx`. The
password is visible in the process list for the duration of the OpenSSL call;
prefer `PFX_PASSWORD` over `--pfx-password` and keep it short-lived.

## Interrupted runs and leftover files

`INT` and `TERM` log `Interrupted`, clean the tracked temporary files and exit
130. A `SIGKILL` or a hard crash cannot run the trap, so look for leftovers in
the target directories:

- `<dest>.XXXXXX` — a partially assembled bundle;
- `.chain.XXXXXX` — the assembled legacy chain.

Both are created under `umask 077`, but they can contain private key material.
Delete them after an aborted run; the next successful run recreates the bundle.

## Expiry warnings

`--check-expiry` inspects the bundle written in the current run and warns when it
is expired or expires within `--expiry-days` (default 30). Consequences:

- An all-`unchanged` run reports no expiry warning, because nothing was written.
  To check an existing bundle, read it directly:
  `openssl x509 -in <domain>.pem -noout -enddate`.
- The day count is computed from `notAfter` with GNU `date -d`, falling back to
  the BSD `date -j -f` form. A platform where neither works falls back to an
  epoch of 0 and reports the bundle as `EXPIRED`; verify the date by hand before
  treating that as a real problem.
- Expiry warnings never change the exit code, and an expired certificate is
  still bundled.

## Platform notes

- **macOS.** The system Bash is 3.2; run the script with a 4+ interpreter
  (`brew install bash`). The expiry fallback handles BSD `date`.
- **WSL.** Linux paths and `flock` behave normally; use the Linux path
  (`/etc/letsencrypt/live`), not the Windows mount.
- **Git Bash on Windows.** The script runs, but `chmod` is emulated and
  `/var/lock` may not be usable: expect the mode correction to have no effect and
  the lock warnings to appear. The test suite accounts for this and skips the
  permission assertion.

Next: [FAQ](10-FAQ) — short answers, including whether the tool checks
certificate names, trust and expiry.
