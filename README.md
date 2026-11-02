# Cert Unifier

**Version 3.1.1** — audited PEM and PFX unification for Let's Encrypt, Certbot and legacy layouts.

[English](README.md) · [Deutsch](README.de.md) · [中文](README.zh.md) · [हिन्दी](README.hi.md) · [Español](README.es.md) · [Русский](README.ru.md)

[![CI](https://github.com/paulmann/cert-unifier/actions/workflows/ci.yml/badge.svg)](https://github.com/paulmann/cert-unifier/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Bash 4.0+](https://img.shields.io/badge/bash-4.0%2B-4EAA25)](https://www.gnu.org/software/bash/)
[![OpenSSL 1.1.1+ / 3.x](https://img.shields.io/badge/openssl-1.1.1%2B%20%7C%203.x-721412)](https://www.openssl.org/)

## Contents

- [What it does](#what-it-does)
- [Why a unifier needs to verify](#why-a-unifier-needs-to-verify)
- [Requirements](#requirements)
- [Install](#install)
- [Usage](#usage)
- [Options](#options)
- [Layouts](#layouts)
- [JSON summary](#json-summary)
- [Exit codes](#exit-codes)
- [Safety](#safety)
- [Testing](#testing)
- [Contributing](#contributing)
- [License](#license)
- [Changelog](#changelog)

## What it does

Cert Unifier scans a directory tree of Let's Encrypt material, checks that each
private key really belongs to its leaf certificate, and writes one audited
bundle per domain: the private key followed by the full chain.

- **Public-key matching** for RSA and EC keys (`openssl x509 -pubkey` against
  `openssl pkey -pubout`), not a modulus hash that only works for RSA.
- **Refuses to write what it cannot verify**: a mismatched key, a
  passphrase-protected key, an unreadable key or a missing key stops that entry
  with an error instead of producing a broken bundle.
- **Atomic writes**: content is assembled in the target directory, forced to
  mode 0600, then renamed over the destination.
- **Idempotent**: a byte-identical bundle is left untouched (mtime preserved),
  and a pre-existing 0644 bundle has its mode corrected.
- **Optional PKCS#12** export for IIS/Windows, and optional expiry warnings.
- **Machine-readable** `--json` summary for automation.
- **No network access**: it never requests, renews, revokes or installs
  certificates, and never reloads a service.

## Why a unifier needs to verify

A bundle is only useful if the key inside it matches the certificate. The
common failure modes are silent: Certbot rotates the private key on renewal,
legacy layouts keep `_le1`, `_le2`, `_le10` side by side, and operators copy the
wrong key. A web server that starts with a mismatched key fails the handshake
later, at the worst possible moment. Cert Unifier treats key/certificate
matching as a precondition, not a warning.

## Requirements

| Requirement | Why |
|-------------|-----|
| Bash 4.0 or later | arrays, `shopt`, process substitution |
| `openssl` 1.1.1 or 3.x | public-key comparison, PEM validation, PKCS#12 export |
| `flock` (optional) | keeps two runs from touching the same tree |
| Read access to keys and certificates | the private key is read into the bundle |
| Write access to the output directory | bundles are written next to the sources |

Linux, macOS and WSL are supported. macOS ships Bash 3.2; install a newer
Bash (`brew install bash`) or run the script with `bash` from Homebrew.

## Install

```bash
wget https://raw.githubusercontent.com/paulmann/cert-unifier/main/cert-unifier.sh
chmod +x cert-unifier.sh
./cert-unifier.sh --version
```

System-wide:

```bash
sudo install -m 755 cert-unifier.sh /usr/local/bin/cert-unifier
```

## Usage

```bash
# 1. inspect the tree without writing anything
./cert-unifier.sh --dry-run --verbose /etc/letsencrypt/live

# 2. run it on one domain directory, then on the whole tree
./cert-unifier.sh /etc/letsencrypt/live/example.com
./cert-unifier.sh /etc/letsencrypt/live

# 3. PEM plus PKCS#12 (the password is read from the environment)
PFX_PASSWORD='...' ./cert-unifier.sh --pfx /var/www/certs

# 4. legacy tree with more than one generation per domain
./cert-unifier.sh --no-tld-filter --recursive /opt/certs
```

Each processed entry writes `<domain>.pem` (private key, then leaf, then
intermediates) next to its source files, or into `--output-dir` when given.

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `-h, --help` | Show help and exit | |
| `-V, --version` | Show version and exit | |
| `-d, --dry-run` | Validate and report, write nothing | off |
| `-v, --verbose` | DEBUG logging | off |
| `-t, --tlds LIST` | Allowed TLDs, comma or space separated | `ru com` |
| `-o, --output-dir PATH` | Write bundles here instead of next to sources | same as source |
| `--no-tld-filter` | Process every domain | off |
| `--no-key-validation` | Bundle even when the key cannot be verified | off |
| `--pfx` | Also write a `.pfx` | off |
| `--pfx-password PASS` | PFX password (prefer `PFX_PASSWORD`) | empty |
| `--skip-pfx-on-mismatch` | Skip mismatched entries instead of failing | off |
| `--check-expiry` | Warn about certificates close to expiry | off |
| `--expiry-days N` | Expiry warning threshold in days | `30` |
| `--recursive` | Descend into subdirectories for the legacy layout | off |
| `--json` | Emit a machine-readable summary on stdout | off |

Environment variables: `ALLOWED_TLDS`, `LOG_LEVEL` (`DEBUG`, `INFO`, `WARN`,
`ERROR`), `PFX_PASSWORD`, `CERT_UNIFIER_LOCK`, `NO_KEY_VALIDATION`.

## Layouts

**Certbot**

```text
/etc/letsencrypt/live/example.com/fullchain.pem
/etc/letsencrypt/live/example.com/privkey.pem
→ /etc/letsencrypt/live/example.com/example.com.pem
```

**Legacy**

```text
example.com_le10.crt      leaf certificate
example.com_le10.crtca    chain
example.com_le10.key      private key (or example.com.key)
→ example.com.pem
```

`N` may be any number. When several generations of one domain are present in
the same directory, the highest `N` wins, so an old `_le1` never overwrites a
newer `_le10`.

## JSON summary

```bash
./cert-unifier.sh --json /etc/letsencrypt/live
```

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
    {"domain": "example.com", "status": "updated", "pem": "/etc/letsencrypt/live/example.com/example.com.pem", "fingerprint": "..."}
  ]
}
```

`status` is `success`, `none` (nothing matched) or `error`. Warnings and errors
still go to stderr so stdout stays parseable.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Everything requested was done (in `--dry-run`, everything was planned) |
| 1 | Runtime or validation error; at least one entry was refused |
| 2 | No matching certificates found |
| 130 | Interrupted by INT or TERM |

## Safety

- The private key is always written with mode 0600, under `umask 077`.
- Writes are atomic in the target directory; a failed run leaves the previous
  bundle intact.
- The only file created outside the scanned tree is the lock file
  (`/var/lock/cert-unifier.lock`, override with `CERT_UNIFIER_LOCK`).
- The PFX password is passed to OpenSSL on the command line, so it is visible
  in `ps` for the duration of that call. Prefer a short-lived environment
  variable; an empty password produces an unencrypted PFX.
- The script never deletes source files, never touches the network and never
  reloads a service.

## Testing

```bash
chmod +x tests/run-tests.sh
./tests/run-tests.sh
```

The suite generates real RSA and EC fixtures with OpenSSL and asserts exit
codes, bundle contents, permissions, idempotency, dry-run behaviour, JSON
validity, PKCS#12 export, refusal of mismatched/missing/passphrase-protected
keys, and cleanup. It runs in GitHub Actions on every push.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). Changes
are expected to keep `tests/run-tests.sh` and `shellcheck` clean.

## License

[MIT](LICENSE) © 2026 Mikhail Deynekin.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).
