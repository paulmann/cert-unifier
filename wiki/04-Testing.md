# Testing

The suite in `tests/run-tests.sh` is deliberately self-contained: Bash and
OpenSSL, no network, no fixtures checked into the repository.

## What it asserts

The suite generates real RSA and EC key/certificate pairs and then checks
behaviour, not the mere existence of a file:

- CLI: `--version` reports the version declared in the script, `--help` exits 0,
  an unknown option and a missing root exit 1.
- Certbot layout: the bundle exists, starts with the private key, contains a
  certificate, and has mode 0600 where the filesystem supports modes.
- Legacy layout: a bundle is produced; a multi-digit `_le10` generation is
  found and the newest generation wins.
- Refusal: a mismatched key, a missing `.key`, a passphrase-protected key and a
  structurally invalid key each end with exit code 1 and leave no bundle.
- Dry run: exits 0, reports the plan, writes nothing.
- Idempotency: the second run reports "Unchanged" and does not touch mtime.
- JSON: the output parses as JSON, lists every result, and reports `status`
  `success` or `none`; an empty tree exits 2.
- PKCS#12: an RSA and an EC export both open with their password.
- `--output-dir`, `--recursive`, the TLD filter and its hint.
- `LOG_LEVEL=ERROR` silences INFO.
- No temporary files survive a completed run.

A check that examined nothing is a failure, not a pass. That rule exists because
an earlier suite reported green while `--json`, `--pfx` and the key/certificate
check were all broken: every command was wrapped in `|| true`, so nothing could
fail.

## Running locally

```bash
./tests/run-tests.sh
```

On Windows with Git Bash, `chmod 600` is emulated by the filesystem, so the
permission check is skipped rather than reported as a failure. Subject names in
fixtures use the `//CN=` form where MSYS would otherwise rewrite the argument
into a Windows path.

## Continuous integration

`.github/workflows/ci.yml` runs `shellcheck -x cert-unifier.sh
tests/run-tests.sh` and the suite on Ubuntu for every push to `main`, every pull
request and every `v*` tag. The runner ships OpenSSL 3.x, so the PKCS#12 path and
the OpenSSL 3 behaviour are exercised on every run.
