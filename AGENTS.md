# AGENTS.md — Cert Unifier 3.1.1

Operational contract for AI agents: what the tool is, how to run it without a
human, and what must never be pasted into a report. Human documentation is
[README.md](README.md); the longer guides are in the [wiki](wiki/Home.md).

## What it is

One self-contained Bash script that scans Certbot `live/` and legacy `_leN`
layouts, verifies that each private key belongs to its leaf certificate by
public key (RSA and EC), and writes one atomic PEM bundle per domain: private
key, then full chain, mode 0600. It never requests, renews or revokes
certificates, never reloads a service and never touches the network.

## Preconditions

| Requirement | Check |
|---|---|
| Bash 4.0 or later | `bash --version` |
| OpenSSL 1.1.1 or 3.x | `command -v openssl && openssl version` |
| `flock` (recommended) | `command -v flock` |
| Read access to keys, write access to the target | manual |

## Install

```bash
wget -O cert-unifier.sh https://raw.githubusercontent.com/paulmann/cert-unifier/main/cert-unifier.sh
chmod +x cert-unifier.sh
sudo install -m 755 cert-unifier.sh /usr/local/bin/cert-unifier   # persistent
```

## Verify

Compare the output literally; stop if it differs:

```bash
./cert-unifier.sh --version   # "cert-unifier.sh 3.1.1" + copyright + "License: MIT"
./cert-unifier.sh --help      # USAGE / OPTIONS / ENVIRONMENT / EXIT CODES, exits 0
```

Then `--dry-run --verbose` on the target, then one domain directory, then the
whole tree. Exit code 2 means nothing matched — retry with `--no-tld-filter`.

## Use non-interactively

| Rule | Why |
|---|---|
| Never write without `--dry-run` first | a write replaces the previous bundle |
| Secrets from the environment only (`PFX_PASSWORD`) | a flag value appears in `ps` |
| Always pass an explicit path | the default is the current directory |
| Read exit codes, not prose | 0 done, 1 refused, 2 nothing, 130 interrupted |
| Treat `--json` stdout alone as machine-readable | logs and warnings go to stderr |

## Behaviour contract

1. The key is verified before anything is written: the key's public key must
   equal the leaf certificate's public key.
2. Unverifiable input is refused with exit code 1 and no bundle: a mismatched,
   passphrase-protected or unparsable key, or no key at all.
   `--no-key-validation` is the explicit opt-out and logs a warning.
3. The legacy layout uses the highest `_leN` generation (`_le10` beats `_le1`);
   nested directories need `--recursive`.
4. Writes are atomic and private: assembled in the target directory under
   `umask 077`, set to 0600, renamed over the destination. A byte-identical
   bundle keeps its mtime, but its mode is still forced to 0600.
5. `--dry-run` writes nothing: exit 0 when it planned work, 2 when nothing
   matched. `--json` keeps stdout parseable and always emits a closing `]}`.

## Outputs and exit codes

`<domain>.pem` (key then chain, 0600) and, with `--pfx`, `<domain>.pfx`. The JSON
summary carries `version`, `status`, `processed`, `skipped`, `planned`,
`errors`, `warnings` and `results`. There is no exit code 3.

| Code | Meaning |
|---|---|
| 0 | Everything requested was done |
| 1 | Runtime or validation error; at least one entry was refused |
| 2 | No matching certificates found |
| 130 | Interrupted by INT or TERM |

## Traps and constraints

- The PFX password is passed to OpenSSL as an argument and is visible in `ps`
  for that call; an empty password produces an unencrypted `.pfx`.
- The lock defaults to `/var/lock/cert-unifier.lock` and may need root; override
  it with `CERT_UNIFIER_LOCK`. Without `flock` it warns and continues unlocked.
- Only the target root and its immediate subdirectories are scanned unless
  `--recursive` is given; the TLD filter is suffix-based and on by default.
- macOS ships Bash 3.2: run the script with a Bash 4+ from Homebrew. WSL works.
- Do not run the script as root over `/etc/letsencrypt` before a dry run, and do
  not paste real keys, passphrases or certificate contents into any issue,
  ticket, log or chat.

## Testing

```bash
chmod +x tests/run-tests.sh
./tests/run-tests.sh   # expected: "56 passed, 0 failed, 1 skipped"
shellcheck -x cert-unifier.sh tests/run-tests.sh
```

The suite generates real RSA and EC fixtures and asserts exit codes, bundle
contents, permissions, idempotency and refusals. A change is complete only when
the suite is green and shellcheck is clean; CI runs both on every push.

## Report bugs

Draft the report; do not publish it — a human files the issue at
https://github.com/paulmann/cert-unifier/issues/new/choose. Include the
`--version` output, the OS and distribution, `bash --version`,
`openssl version`, the exact command and the full output. Remove private keys,
passphrases, tokens and personal data first. Security problems go through
[SECURITY.md](SECURITY.md), never a public issue or pull request.

## Where the detail lives

- [README.md](README.md) — installation, options, layouts, JSON summary, exit codes.
- [wiki/Home.md](wiki/Home.md) — why verification matters, layouts, security model, testing.
- [CONTRIBUTING.md](CONTRIBUTING.md) — style and review rules; [CHANGELOG.md](CHANGELOG.md) — history.
