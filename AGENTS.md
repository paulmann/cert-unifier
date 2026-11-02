# AGENTS.md — Cert Unifier 3.1.1

Agent-facing operational guide. Human documentation: [README.md](README.md).

## What it is

One self-contained Bash script that:

1. Scans Certbot `live/` and legacy `_leN` certificate layouts.
2. Verifies that each private key belongs to its leaf certificate, by public key
   (RSA and EC).
3. Writes one atomic PEM bundle per domain — private key, then full chain —
   with mode 0600.
4. Optionally writes a PKCS#12 (`.pfx`) file.

It never requests, renews or revokes certificates, never reloads a service and
never touches the network.

## Behaviour contract

What "audited bundle" means here, in the order the script enforces it:

1. **The key is checked before anything is written.** The public key of the
   private key is compared with the public key of the leaf certificate.
2. **Unverifiable input is refused, not bundled.** These cases fail that entry
   with an error and exit code 1, and leave no bundle behind:
   - the private key does not match the certificate;
   - the private key is passphrase-protected (the script never prompts);
   - the private key or certificate cannot be parsed;
   - no private key was found at all.
   `--no-key-validation` is the explicit opt-out: it bundles unverifiable key
   material and logs a warning.
3. **A legacy directory with several generations uses the newest one.** `N` in
   `_leN` may have several digits; the highest `N` wins, so `_le10` beats
   `_le1`. Nested directories need `--recursive`.
4. **Writes are atomic and private.** The bundle is assembled in the target
   directory, set to mode 0600 under `umask 077`, then renamed over the
   destination. A failed run leaves the previous bundle intact.
5. **Content is idempotent.** A byte-identical bundle is not rewritten (mtime
   preserved); its mode is still forced to 0600.
6. **`--dry-run` reports and exits 0.** It writes no bundle; when it finds work
   it says so and returns 0, and exits 2 only when nothing matched.
7. **The JSON summary is complete and parseable.** `--json` keeps stdout free
   of log lines and always emits a closing `]}`; warnings and errors go to
   stderr.

## Preconditions

| Requirement | Check |
|-------------|-------|
| Bash 4.0 or later | `bash --version` |
| `openssl` 1.1.1+ or 3.x | `command -v openssl && openssl version` |
| `flock` (recommended) | `command -v flock` |
| Read access to the sources | manual |
| Write access to the output directory | manual |

## Install

```bash
wget -O cert-unifier.sh https://raw.githubusercontent.com/paulmann/cert-unifier/main/cert-unifier.sh
chmod +x cert-unifier.sh
# or
sudo install -m 755 cert-unifier.sh /usr/local/bin/cert-unifier
```

## Verify

```bash
cert-unifier.sh --version   # "cert-unifier.sh 3.1.1" + copyright + "License: MIT"
cert-unifier.sh --help      # USAGE / OPTIONS / ENVIRONMENT / EXIT CODES, exits 0
```

## Safe order of operations

1. `--help` and `--version`.
2. `--dry-run --verbose` on the target tree.
3. A real run on one domain directory.
4. A real run on the whole tree, then automation (cron, systemd timer, deploy
   hook).

## Common invocations

```bash
# Inspect without writing
./cert-unifier.sh --dry-run --verbose /etc/letsencrypt/live

# PEM bundles only
./cert-unifier.sh /var/www/httpd-cert

# PEM plus PKCS#12 (prefer the environment variable over the flag)
PFX_PASSWORD='...' ./cert-unifier.sh --pfx /var/www/certs

# Machine-readable summary for automation
./cert-unifier.sh --json /etc/letsencrypt/live

# Legacy tree, every TLD, nested directories, newest generation per domain
./cert-unifier.sh --no-tld-filter --recursive /opt/certs

# Expiry warnings
./cert-unifier.sh --check-expiry --expiry-days 21 /etc/letsencrypt/live
```

## Outputs

- `<domain>.pem` — private key followed by the full chain, mode 0600.
- `<domain>.pfx` — only with `--pfx`, mode 0600.
- Temporary files are removed on exit; on failure they are named
  `.chain.XXXXXX` or `<dest>.XXXXXX` in the target directory.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Everything requested was done (in `--dry-run`: everything was planned) |
| 1 | Runtime or validation error; at least one entry was refused |
| 2 | No matching certificates found |
| 130 | Interrupted by INT or TERM |

There is no exit code 3.

## JSON summary

```json
{"version":"3.1.1","status":"success","processed":1,"skipped":0,"planned":0,
 "errors":0,"warnings":0,
 "results":[{"domain":"example.com","status":"updated","pem":"...","fingerprint":"..."}]}
```

`status` is `success`, `none` or `error`; a `results` entry has `status` of
`updated`, `unchanged`, `dry-run`, `skipped` or `error`.

## Known constraints

- The PFX password is passed to OpenSSL on the command line, so it is visible in
  `ps` for the duration of that call. The environment variable has the same
  property once read.
- The lock file defaults to `/var/lock/cert-unifier.lock` and may need root;
  override it with `CERT_UNIFIER_LOCK`. Without `flock` the script warns and
  continues unlocked.
- Only the target root and its immediate subdirectories are scanned unless
  `--recursive` is given.
- The TLD filter is suffix-based and enabled by default (`ru com`); a tree where
  every domain is filtered out ends with exit code 2 and a hint to retry with
  `--no-tld-filter`.
- macOS ships Bash 3.2; run the script with a Bash 4+ from Homebrew.

## Testing

```bash
chmod +x tests/run-tests.sh
./tests/run-tests.sh
```

The suite generates real RSA and EC fixtures and asserts exit codes, bundle
contents, permissions, idempotency, dry-run behaviour, JSON validity, PKCS#12
export, refusal of mismatched/missing/passphrase-protected keys, and cleanup.
It must stay green before any change is considered complete.

## CI

`.github/workflows/ci.yml` runs `shellcheck` and the test suite on Ubuntu for
every push and pull request, and for `v*` tags.

## Reporting problems

Report a defect only with a version, an OS/Bash/OpenSSL triple, the exact
command and the output. Do not open issues or pull requests automatically: draft
them, and let a human publish.
