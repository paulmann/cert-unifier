# Command reference

Every option, environment variable, default and exit condition of
`cert-unifier.sh` 3.1.1, as implemented in the script itself. The reference is
deliberately literal: the help text and this page describe the same option set.

## Synopsis

```text
cert-unifier.sh [OPTIONS] [ROOT_DIRECTORY]
```

- `ROOT_DIRECTORY` is optional and positional. At most one is accepted; a second
  positional argument is a usage error (exit 1).
- Without `ROOT_DIRECTORY`, the script uses `/var/www/httpd-cert` when that
  directory exists, otherwise the current working directory.
- `-h, --help` and `-V, --version` are answered before the rest of the command
  line is parsed, so they win over a broken argument list.

## Options

| Option | Argument | Effect | Default |
|---|---|---|---|
| `-h`, `--help` | — | print USAGE / OPTIONS / ENVIRONMENT / EXIT CODES, exit 0 | off |
| `-V`, `--version` | — | print name, version, copyright and licence, exit 0 | off |
| `-d`, `--dry-run` | — | validate and report the plan, write nothing | off |
| `-v`, `--verbose` | — | DEBUG logging (sets `LOG_LEVEL=DEBUG`) | off |
| `-t`, `--tlds` | LIST | allowed TLD suffixes, comma or space separated | `ru com` |
| `-o`, `--output-dir` | PATH | write bundles into PATH instead of next to the sources | source directory |
| `--no-tld-filter` | — | process every domain regardless of suffix | off |
| `--no-key-validation` | — | bundle even when the key cannot be verified | off |
| `--pfx` | — | also write a `<domain>.pfx` | off |
| `--pfx-password` | PASS | PFX password (prefer `PFX_PASSWORD`) | empty |
| `--skip-pfx-on-mismatch` | — | skip an entry instead of failing on a key/certificate mismatch | off |
| `--check-expiry` | — | warn about expired or soon-expiring bundles | off |
| `--expiry-days` | N | expiry warning threshold in days, non-negative integer | `30` |
| `--recursive` | — | descend into subdirectories for the legacy layout | off |
| `--json` | — | machine-readable summary on stdout | off |

### Notes on individual options

**`-t, --tlds LIST`** — commas become spaces (`-t "ru,com"` is `ru com`).
Matching is suffix-based, so `shop.example.com` passes `com`. The option
replaces the list; it does not add to it.

**`-o, --output-dir PATH`** — `PATH` must already exist and be a directory;
otherwise the run stops with exit 1 before scanning. Every bundle becomes
`PATH/<domain>.pem` for both layouts.

**`--no-tld-filter`** — removes the suffix filter for the whole run, including
the hint printed with exit code 2.

**`--no-key-validation`** — switches off the public-key comparison and the PEM
pre-check of the private key, so unverifiable material is bundled with a
warning. It is the only documented opt-out of the behaviour contract; PFX
generation still verifies the key unless `--skip-pfx-on-mismatch` is also given.

**`--skip-pfx-on-mismatch`** — on a key/certificate mismatch: log a warning,
count the entry as skipped, write no bundle, and let the run exit 0. It affects
the PEM path as well as the PFX path, despite the name.

**`--check-expiry`** — warns when a bundle written in this run is expired or
expires within the threshold. It does not refuse, does not change the exit code,
and does not re-check bundles whose content was unchanged.

**`--expiry-days N`** — must match a non-negative integer; any other value exits
1 with `--expiry-days requires a non-negative integer`. Only meaningful together
with `--check-expiry`.

**`--pfx`** — writes `<domain>.pfx` next to the PEM, mode 0600, with the file
stem as the PKCS#12 friendly name. The password comes from `--pfx-password` or
`PFX_PASSWORD`; an empty password produces an unencrypted PFX.

**`--recursive`** — only the legacy layout uses it. The Certbot scanner always
reads exactly the immediate subdirectories of `ROOT`.

**`--json`** — keeps stdout for the JSON document only: INFO lines are
suppressed, warnings and errors still go to stderr, and the closing `]}` is
always emitted once the scan has run. See
[JSON summary and exit codes](06-JSON-and-Exit-Codes) for the schema and for the
failures that produce no JSON at all.

**`-v, --verbose`** — same as `LOG_LEVEL=DEBUG`. DEBUG lines exist for the scan,
the lock, the key/certificate verdict and the fingerprint.

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `ALLOWED_TLDS` | `ru com` | initial TLD list; `-t/--tlds` overrides it |
| `LOG_LEVEL` | `INFO` | `DEBUG`, `INFO`, `WARN` or `ERROR`; an unrecognised value behaves like `INFO`; `-v` forces `DEBUG` |
| `PFX_PASSWORD` | empty | PFX password; `--pfx-password` overrides it |
| `CERT_UNIFIER_LOCK` | `/var/lock/cert-unifier.lock` | lock file path |
| `NO_KEY_VALIDATION` | unset | same effect as `--no-key-validation`; accepted values are `true`, `TRUE`, `True`, `1` and `yes` |

`NO_KEY_VALIDATION` is read before the options are parsed, so it works as a
default that `--no-key-validation` does not have to repeat. Turning validation
off is not silent: every entry bundled without a key/certificate comparison is
reported as a warning, because an unverified bundle is what the rest of the
tool refuses to write.

## Defaults

| Setting | Value |
|---|---|
| Root directory | `/var/www/httpd-cert` when it exists, else the current directory |
| Allowed TLDs | `ru com` |
| Log level | `INFO` |
| Lock file | `/var/lock/cert-unifier.lock` |
| Expiry warning threshold | 30 days |
| Output location | next to the sources |
| PFX password | empty (unencrypted PFX) |
| PEM mode | 0600, under `umask 077` |
| Minimum assembled bundle size | 200 bytes; a smaller result is rejected with a warning |

## Logging

- Format: `[YYYY-MM-DD HH:MM:SS] [LEVEL] message`. Colours are used only when
  the stream is a terminal.
- INFO goes to stdout, WARN and ERROR to stderr; with `--json`, INFO is
  suppressed entirely.
- `LOG_LEVEL` is a threshold: `WARN` still shows errors, `ERROR` hides
  warnings.
- On a successful non-dry-run run outside JSON mode the script also prints a
  short "how to use the generated files" block: nginx `ssl_certificate`,
  Apache `SSLCertificateFile`, and the note that private key material stays at
  0600.

## Worked examples

Inspect without writing anything:

```bash
./cert-unifier.sh --dry-run --verbose /etc/letsencrypt/live
```

Bundle a Certbot tree (note: the `live/` directory, not one domain directory):

```bash
./cert-unifier.sh /etc/letsencrypt/live
```

Legacy tree, every TLD, nested directories, newest generation per domain:

```bash
./cert-unifier.sh --no-tld-filter --recursive /opt/certs
```

PEM plus PKCS#12, password from the environment rather than the command line:

```bash
PFX_PASSWORD='change-me' ./cert-unifier.sh --pfx /var/www/certs
```

Relocate all bundles into one directory:

```bash
sudo install -d -m 700 /var/www/tls
./cert-unifier.sh -o /var/www/tls /etc/letsencrypt/live
```

Warn about certificates close to expiry:

```bash
./cert-unifier.sh --check-expiry --expiry-days 21 /etc/letsencrypt/live
```

Machine-readable summary for automation:

```bash
./cert-unifier.sh --json /etc/letsencrypt/live
```

Version and help:

```bash
./cert-unifier.sh --version   # cert-unifier.sh 3.1.1 / copyright / License: MIT
./cert-unifier.sh --help
```

## See also

- [Layouts](02-Layouts) — what the two scanners accept and where output lands.
- [JSON summary and exit codes](06-JSON-and-Exit-Codes) — the automation contract.
- [Troubleshooting](08-Troubleshooting) — what each error message means.
