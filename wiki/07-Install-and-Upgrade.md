# Install and upgrade

## Requirements

| Requirement | Check | Why |
|---|---|---|
| Bash 4.0 or later | `bash --version` | arrays, `shopt`, process substitution |
| `openssl` 1.1.1 or 3.x | `command -v openssl && openssl version` | public-key comparison, PEM validation, PKCS#12 export |
| `flock` (optional) | `command -v flock` | keeps two runs from touching the same tree |
| Read access to keys and certificates | manual | the private key is copied into the bundle |
| Write access to the output directory | manual | bundles are written next to the sources by default |

Supported platforms are Linux, macOS and WSL. macOS ships Bash 3.2, so the
`#!/usr/bin/env bash` interpreter is too old; install a newer Bash
(`brew install bash`) and run the script with that interpreter explicitly.

Git Bash on Windows runs the script and the test suite, with differences that
matter: `chmod 600` is emulated, `flock` is usually absent and `/var/lock` may
not be a usable path, so the mode and lock guarantees degrade to warnings.

## Download and verify

```bash
wget -O cert-unifier.sh https://raw.githubusercontent.com/paulmann/cert-unifier/main/cert-unifier.sh
chmod +x cert-unifier.sh
./cert-unifier.sh --version
./cert-unifier.sh --help
```

`--version` prints exactly three lines:

```text
cert-unifier.sh 3.1.1
Copyright (c) 2026 Mikhail Deynekin
License: MIT
```

`--help` prints USAGE, OPTIONS, ENVIRONMENT and EXIT CODES and exits 0. If either
output differs, stop: the file is not the 3.1.1 script and the behaviour in this
wiki may not apply. `curl -fsSLO <the same URL>` is equivalent to the `wget`
line.

For a copy that does not move with `main`, pin the release tag — the repository
is tagged `v3.1.1`:

```bash
wget -O cert-unifier.sh https://raw.githubusercontent.com/paulmann/cert-unifier/v3.1.1/cert-unifier.sh
```

## Persistent install

```bash
sudo install -m 755 cert-unifier.sh /usr/local/bin/cert-unifier
cert-unifier --version
```

The script uses its invoked name in messages, so after this install the version
line reads `cert-unifier 3.1.1`. There is no package, no configuration file and
no state directory to create: the file is the whole installation.

## First run

Work up to a full run instead of starting with one:

```bash
# 1. what is on the machine
cert-unifier.sh --version
bash --version
openssl version

# 2. what the script would do — writes nothing
cert-unifier.sh --dry-run --verbose /etc/letsencrypt/live

# 3. a real run, then read the exit code and the JSON
cert-unifier.sh --json /etc/letsencrypt/live
```

Scope is controlled by the root directory and the file-name filters, not by a
"one domain" switch: the Certbot scanner always reads the immediate
subdirectories of the root, so a first run over a large `live/` tree is narrowed
with `--dry-run` (read the planned list first), `-t` (TLD filter) or a copy of the
tree. `--output-dir` lets a first real run write somewhere other than the source
tree. See [Layouts](02-Layouts) for the scan depth of each layout.

Exit codes to expect: `0` the run did what it was asked, `1` at least one entry
was refused, `2` nothing matched, `130` interrupted. The full contract is in
[JSON summary and exit codes](06-JSON-and-Exit-Codes).

## Scheduling

The script is idempotent, so running it more often than certificates change is
cheap: unchanged bundles keep their mtime. It never reloads a service, so a
reload belongs in the wrapper that runs after a successful exit.

A cron entry that keeps a JSON record per run and reloads only on success:

```bash
17 3 * * * /usr/local/bin/cert-unifier --json /etc/letsencrypt/live >/var/log/cert-unifier.json 2>>/var/log/cert-unifier.err || echo "cert-unifier exit $?" >&2
```

Prefer a small wrapper script when the reload matters, because `cron` itself
does not chain the exit code; the automation pattern is in
[JSON summary and exit codes](06-JSON-and-Exit-Codes). A systemd timer is the
other common choice:

```ini
# /etc/systemd/system/cert-unifier.service
[Service]
Type=oneshot
ExecStart=/usr/local/bin/cert-unifier --json /etc/letsencrypt/live
User=root
```

```ini
# /etc/systemd/system/cert-unifier.timer
[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

The reload stays a separate unit step or a wrapper; the unifier never touches a
service.

## Upgrade

Upgrades are a file replacement — there is no installer, no database and no
migration. To upgrade from any earlier version:

```bash
sudo install -m 755 ./cert-unifier.sh /usr/local/bin/cert-unifier
cert-unifier --version
cert-unifier --dry-run --verbose /etc/letsencrypt/live
```

Then run for real. Because writes are idempotent, a bundle whose content is
already correct is reported `unchanged` and keeps its mtime; the mode is forced
to 0600 on that path, which repairs bundles left at 0644 by older releases.

What changed in the current line, from
[CHANGELOG.md](https://github.com/paulmann/cert-unifier/blob/main/CHANGELOG.md):

- 3.1.1 is the first published release of the 3.x line; 3.0.0 and 3.1.0 were
  prepared but never released.
- Key/certificate matching now compares public keys, so EC keys are covered;
  a mismatch, a missing key, a passphrase-protected key and unusable key material
  are refused instead of bundled.
- Writes are atomic and bundles are always 0600, including on the idempotent
  path.
- `--json`, `--recursive`, `--check-expiry`, `--expiry-days` and
  `--no-key-validation` are part of the 3.x option set.
- `--pfx` works on OpenSSL 3.x.

Keep the previous script file until the new one has run cleanly once; rolling
back is copying the old file back and re-running, and bundles are regenerated
from the source material either way. The source keys and certificates are never
modified.

## Uninstall

```bash
sudo rm -f /usr/local/bin/cert-unifier
```

- Generated bundles and PFX files stay where they were written; remove them if
  they are no longer needed.
- The lock file (`/var/lock/cert-unifier.lock` or the `CERT_UNIFIER_LOCK` path)
  may remain; it contains no data.
- Nothing else is installed, so nothing else needs removing.

## Verify an installation

- `cert-unifier --version` prints `3.1.1`, the copyright line and `License: MIT`.
- `cert-unifier --help` exits 0 and lists all fifteen options.
- `cert-unifier --json --dry-run <root>` exits 0 with a JSON document, or 2 when
  nothing matched.
- `tests/run-tests.sh` (from a repository checkout) is green; the suite needs
  Bash, OpenSSL and, for the JSON checks, Python. See [Testing](04-Testing).

Next: [Troubleshooting](08-Troubleshooting) — when one of those checks fails.
