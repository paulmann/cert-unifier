# Testing

The suite in `tests/run-tests.sh` is deliberately self-contained: Bash and
OpenSSL, no network, no fixtures checked into the repository. It generates real
RSA and EC key/certificate pairs with OpenSSL in a temporary directory and then
asserts observable behaviour — exit codes, file contents, permissions, mtime,
log lines and JSON fields — instead of checking that a file merely appeared.

## Running locally

```bash
chmod +x tests/run-tests.sh
./tests/run-tests.sh
```

Requirements and portability:

| Requirement | Used for | If missing |
|---|---|---|
| Bash 4.0+ | everything | the suite cannot run |
| `openssl` 1.1.1+/3.x | fixtures, PFX checks, fingerprints | the suite cannot run |
| `timeout` or `gtimeout` | caps every script invocation at 30 s | runs without a limit |
| `python3` or `python` | parses the `--json` output | the JSON validity checks are skipped |
| real `chmod` semantics | asserts mode 0600 | the permission check is skipped (Git Bash emulates modes) |

The suite is portable to Linux, macOS with Bash 4+ and Git Bash on Windows. It
probes whether OpenSSL accepts `/CN=` or needs the `//CN=` form that MSYS
rewrites, and generates fixtures accordingly.

A green run ends with a summary line:

```text
Results: 56 passed, 0 failed, 1 skipped
```

Those are the numbers measured on a Git Bash checkout, where the one skip is the
mode check that emulated `chmod` cannot satisfy. The exact split depends on the
facilities available — a Linux runner checks the permission too; the exit code
does not depend on it. The suite exits `0` only when it reports zero failures
and exits `1` otherwise.

## What it asserts

| Area | Checks |
|---|---|
| CLI surface | `--version` exits 0 and reports the version declared in the script; `--help` exits 0; an unknown option exits 1; a missing root directory exits 1 |
| Certbot layout | the bundle exists, starts with `PRIVATE KEY`, carries a certificate, and has mode 0600 where modes are real |
| Legacy layout | a bundle is produced; a multi-digit `_le10` generation is found and the newest generation wins (compared by SHA-256 fingerprint) |
| Refusals | a mismatched key, a missing `.key`, a passphrase-protected key and a structurally invalid key each exit 1 and leave no bundle; the passphrase run is bounded in wall-clock time so it cannot hang |
| `--skip-pfx-on-mismatch` | the run exits 0 and still writes nothing |
| Dry run | exits 0, logs `DRY-RUN`, writes no bundle |
| Idempotency | the second run logs `Unchanged` and does not change the mtime |
| JSON | the output parses, lists every result, reports `status` `success` or `none`; an empty tree exits 2 |
| PKCS#12 | an RSA and an EC export both open with their password |
| Scope and filtering | `--output-dir` moves output and leaves the source alone; a nested legacy tree needs `--recursive`; a filtered TLD ends with exit 2 and the `--no-tld-filter` hint |
| Logging | `LOG_LEVEL=ERROR` silences `[INFO]` lines |
| Cleanup | no `.chain.*` or `.XXXXXX` temporary files survive a completed run |

## Design rules of the suite

- **No `set -e`.** The suite must keep running after a failing expectation and
  report the whole picture; one red check does not hide the next one.
- **A check that examined nothing is a failure, not a pass.** Skips are reserved
  for facilities the machine genuinely lacks (mode emulation, Python).
- **Every check names an observable.** Exit code, file, mode, mtime, log line or
  JSON field — never "it seems to work".
- This rule exists because a previous suite reported green while `--json`,
  `--pfx` and the key/certificate check were all broken: every command was
  wrapped in `|| true`, so nothing could fail.

## Continuous integration

`.github/workflows/ci.yml` runs on Ubuntu for every push to `main`, every pull
request against `main` and every push of a `v*` tag. The job:

1. installs `openssl` and `shellcheck`;
2. prints `bash --version`, `openssl version` and `shellcheck --version` into the
   log, so a failure can be attributed to a toolchain;
3. runs `shellcheck -x cert-unifier.sh tests/run-tests.sh`;
4. makes both scripts executable and runs `./tests/run-tests.sh`.

The runner ships OpenSSL 3.x, so the PKCS#12 path and the OpenSSL 3 behaviour
are exercised on every run, not only on the maintainer's machine.

## Before shipping a change

Run both locally and keep both clean:

```bash
shellcheck -x cert-unifier.sh tests/run-tests.sh
./tests/run-tests.sh
```

New behaviour needs a new assertion; a defect fixed without a regression check
can come back. Review rules live in
[CONTRIBUTING.md](https://github.com/paulmann/cert-unifier/blob/main/CONTRIBUTING.md).

Next: [Architecture](09-Architecture) — what the suite is protecting.
