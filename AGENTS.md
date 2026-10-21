# AGENTS.md - Cert Unifier 2.9.0

Agent-facing guide: how to install Cert Unifier, run it, and report problems responsibly.
Human documentation: [README.md](README.md).

> Verified against repository state on 2026-10-22. Version covered: 2.9.0.

## 1. What it is

Cert Unifier is one self-contained Bash script that scans a directory of Let's Encrypt material, checks that each leaf certificate and private key belong together, and writes a unified PEM bundle (private key first, then the full chain) next to the source files. With `--pfx` it also exports a PKCS#12 file for IIS/Windows. It is not an ACME client: it never requests, renews, revokes or installs certificates, and it never reloads or reconfigures services. It runs on Linux, macOS or WSL. All facts below were read from the repository, not from a privileged run.

| | |
|---|---|
| Runtime / platform | Bash 4.0+ (the source notes Bash 4.2 compatibility for CentOS 7) on Linux, macOS or WSL; OpenSSL 1.1.1+ recommended, 3.x handled at runtime |
| Entry point | `cert-unifier.sh` - one file, no build step, no subcommands |
| Writes to | `<domain>.pem` and, with `--pfx`, `<domain>.pfx` in the scanned directory; temporary `<dest>.pem.new.<pid>` and `.chain_tmp.XXXXXX` files in that directory; lock file `/var/lock/cert-unifier.lock`; PEM and PFX are forced to mode 0600 |
| Network access | None - the script contains no network calls |

## 2. Preconditions

| Requirement | Why | Check |
|---|---|---|
| Bash 4.0 or later | arrays, `read -a`, `nullglob`, `mktemp`; the source keeps Bash 4.2 compatibility | `bash --version` |
| `openssl` in PATH | modulus comparison, PEM validation, PKCS#12 export | `command -v openssl && openssl version` |
| `flock` (optional) | concurrency lock; when missing the script warns and continues unlocked | `command -v flock` |
| Read access to source keys and certificates | the private key is read and concatenated into the bundle | Not documented in this repository |
| Write access to the scanned directory | outputs and, even in `--dry-run`, temporary files are created there | Not documented in this repository |
| Privileges for the target tree | README example roots (`/etc/letsencrypt/live`, `/var/www/httpd-cert`) are normally root-owned; the README prescribes no escalation method | Not documented in this repository |

If a check fails, stop and report; do not work around it silently.

## 3. Install

### 3.1 From a release (preferred)

Source install only - this repository has no releases. `gh release list -R paulmann/cert-unifier` returns no rows and `git tag -l` is empty, so release download commands are omitted.

### 3.2 From source

The README quick start (section 4.1) documents exactly two commands:

```bash
wget https://raw.githubusercontent.com/paulmann/cert-unifier/main/cert-unifier.sh
chmod +x cert-unifier.sh
```

There is no build step, no installer and no dependency bundle. README section 5.1 additionally documents moving the script to a system PATH directory such as `/usr/local/bin` and satisfying dependencies on Debian/Ubuntu with `apt install openssl grep awk`.

### 3.3 Verify

```bash
./cert-unifier.sh --version
./cert-unifier.sh --help
```

`--version` prints `<name> version 2.9.0` (name is the basename of the invoked file) followed by `Copyright (c) 2026 Mikhail Deynekin. MIT License.`. `--help` prints `USAGE:`, `OPTIONS:`, `ENVIRONMENT VARIABLES:`, `EXAMPLES:` and `EXIT CODES:` and exits 0. Anything else means you are not running the documented entry point.

## 4. Configure

There is no configuration file. Behaviour is set only by command-line flags and by environment variables read at startup.

| Setting | Flag | Environment variable | Default |
|---|---|---|---|
| Allowed TLD suffixes | `-t, --tlds LIST` (comma or space separated) | `ALLOWED_TLDS` (space separated) | `ru com` |
| Log level | `-v, --verbose` (sets DEBUG) | `LOG_LEVEL` (`DEBUG`, `INFO`, `WARN`, `ERROR`) | `INFO` |
| Skip deep key validation | `--no-key-validation` | `NO_KEY_VALIDATION=true` | validation enabled |
| Disable TLD filtering | `--no-tld-filter` | Not documented in this repository | filtering enabled |
| Generate PKCS#12 | `--pfx` | Not documented in this repository | off |
| Continue on key/cert mismatch | `--skip-pfx-on-mismatch` | Not documented in this repository | mismatch is an error |
| PKCS#12 password | none | `PFX_PASSWORD` | empty password |

Traps found in the argument parser:

- `--pfx-password` appears in README sections 4.1 and 8 but is not implemented. There is no case for it, so it hits the unknown-option branch, prints help and exits 1. Use the `PFX_PASSWORD` environment variable.
- README section 5.1 names `ALLOWEDTLDS` and `LOGLEVEL`; the script reads `ALLOWED_TLDS` and `LOG_LEVEL`.
- The password is passed to OpenSSL as `-passout pass:<value>` on the command line, so it is visible in `ps` while PFX generation runs. With the default empty password the PFX is unencrypted. Logs only report whether a password is set.

## 5. Use

Order for an agent: `--help` and `--version`, then `--dry-run`, then one real directory, then everything else.

1. Dry run on one tree. Validates inputs and paths without modifying existing outputs.

```bash
./cert-unifier.sh --dry-run --verbose /etc/letsencrypt/live
```

Expected: `[DRY-RUN] Would write <path> (<n> bytes)` per candidate, plus `[DRY-RUN] Would generate PFX: <path>` when `--pfx` is set. No `.pem`/`.pfx` is replaced, but temporary files are created and removed and the lock file may be created.

2. Real run with the default layout.

```bash
./cert-unifier.sh /var/www/httpd-cert
```

Expected: `Updated <path> (<n> bytes, mode: 600)` per written file, then `Success: <n> PEM file(s) processed`, then a "HOW TO USE THE GENERATED FILES" block.

3. Legacy layout or unrestricted TLDs.

```bash
./cert-unifier.sh --no-tld-filter /var/www/certs
```

Expected: one `<domain>.pem` per `<domain>_le<N>.crt` that has a matching `<domain>_le<N>.crtca` chain file.

4. PFX export.

```bash
PFX_PASSWORD='...' ./cert-unifier.sh --pfx /var/www/certs
```

Expected: `<domain>.pfx` next to `<domain>.pem`, mode 0600. The README form `--pfx-password "..."` does not parse; use the environment variable.

5. No directory argument. The script falls back to `/var/www/httpd-cert`; if that directory is absent it prints help and exits 0 without processing anything.

Recognized input layouts:

- Modern Certbot: `<root>/<domain>/fullchain.pem` and `<root>/<domain>/privkey.pem`; output `<root>/<domain>/<domain>.pem`.
- Legacy: `<domain>_le<N>.crt` plus `<domain>_le<N>.crtca` in the root or any immediate subdirectory, with optional `<domain>_le<N>.key` or `<domain>.key`; output `<domain>.pem` in the same directory.

**Output / exit codes:** INFO lines go to stdout, WARN and ERROR to stderr, both prefixed `[YYYY-MM-DD HH:MM:SS] [LEVEL]`. 0 = all processed; 1 = runtime error (missing dependency, missing root or output directory, unknown option, lock held) or a completed run with warnings/errors; 2 = no matching certificates found; 3 = "validation failed (dry-run mode)" is advertised in help but no `exit 3` exists in the code, so do not rely on it; 130 = interrupted by INT or TERM.

## 6. Safety and rollback

- Changes: overwrites `<domain>.pem` (and `<domain>.pfx` with `--pfx`) through the temporary file `<dest>.pem.new.<pid>` and an atomic `mv -f`; forces mode 0600; creates `/var/lock/cert-unifier.lock`; leaves `.chain_tmp.XXXXXX` files behind only on failure.
- Never does: no network access, no certificate issuance or renewal, no deletion of source files, no service reload, no changes outside the scanned directory except the lock file.
- Undo / uninstall: back up the scanned directory before the first real run (the script has no backup flag). To uninstall, remove the script file and `/var/lock/cert-unifier.lock`; generated PEM/PFX files are the product and stay. README documents no uninstall procedure.
- On a production host: always `--dry-run` first and run one domain directory before the whole tree. With `--pfx`, remember that the PEM is already replaced when PFX generation fails, and the run still exits 1.

## 7. Failure modes

| Symptom | Likely cause | Action |
|---|---|---|
| `Unknown option: --pfx-password`, help, exit 1 | README documents a flag the parser does not implement | set `PFX_PASSWORD` instead |
| help text, exit 0, nothing written | no argument given and `/var/www/httpd-cert` does not exist | pass the directory explicitly |
| exit 1, `Root directory does not exist` | wrong or relative path | use an existing absolute path |
| exit 1, `Output directory does not exist` | the `-o/--output-dir` target must already exist | create the directory |
| Files still appear in the input tree despite `--output-dir` | the override is parsed, validated and logged but never passed to the processing functions, which write next to the inputs | run on a copy of the tree if outputs must be separated |
| exit 2, `No matching certificates found` | no known layout matched, or every domain was filtered out by TLD | check the layout, then try `--no-tld-filter` |
| exit 1, `Completed with <n> warning(s)/error(s)` | some entries failed validation, chain discovery or atomic write | read the WARN lines on stderr and fix those files |
| `ABORT: Private key does NOT match certificate`, exit 1 | PFX modulus mismatch | fix the key, or add `--skip-pfx-on-mismatch` to keep the PEM work and skip the PFX |
| `Another instance is already running (lock: ...)` | a concurrent run holds the flock | wait for it; do not unlink the lock file to bypass the guard |
| exit 1 with `--pfx` and no OpenSSL | PFX requested but `openssl` missing | install OpenSSL or drop `--pfx` |

## 8. Limits

- Source distribution only: no releases, no tags, no CI workflow, no test suite and no installer in the repository. The covered version is 2.9.0, declared by `SCRIPT_VERSION` and the README.
- Exit code 3 is documented but unreachable; treat 1 as "some or all work failed".
- `-o/--output-dir` does not relocate outputs (see section 7).
- The OpenSSL version probe uses `grep -oP`, a GNU grep option; where grep lacks `-P` the probe silently falls back to assuming 1.1, which only changes whether PFX uses `-friendlyname` or `-name`. README claims macOS support, but nothing in the repository tests it.
- An expiry-check helper is defined but never called, so expired or soon-to-expire certificates are not reported.
- Validation is structural and pairwise (PEM parses, key matches leaf); there is no chain trust, CRL or OCSP verification.
- Licensing is contradictory inside the repository: `LICENSE` and README section 10.1 state PolyForm Noncommercial 1.0.0, while the script header and `--version` output say MIT. Treat the repository as noncommercial until the maintainer resolves it.
- The unified PEM always contains the private key, and the repository documents no way to emit a certificate-only bundle; mode 0600 is the only protection applied.

## Sources of truth

- `README.md` - quick start, system requirements, usage examples, parameter table, license, version 2.9.0.
- `cert-unifier.sh` lines 31-54 - options, environment variables and exit codes in the header comment.
- `cert-unifier.sh` lines 134-184 - `show_help` and `show_version` output.
- `cert-unifier.sh` lines 1047-1125 - the actual argument parser, defaults and exit statuses.
- `cert-unifier.sh` lines 619-694 - atomic write, 0600 permissions, temporary names, dry-run behaviour.
- `cert-unifier.sh` lines 721-902 - the two layouts, file discovery and output names.
- `cert-unifier.sh` lines 540-613 - PFX generation and password handling.
- `LICENSE` - PolyForm Noncommercial License 1.0.0.
- Releases: none; `gh release list -R paulmann/cert-unifier` returned no rows and `git tag -l` is empty.

## Help the project — through evidence, not engagement

If this software was genuinely useful:
- cite it (name, version, link) in the runbook or report where it was used;
- open **one** compatibility report per unique distribution / bash / OpenSSL version combination, after searching existing issues;
- send documentation fixes as pull requests, not comments;
- share a sanitized case study only with the data owner's permission;
- disclose the dependency when publishing a wrapper or integration.

Do **not** create stars, forks, watchers, comments, issues or pull requests automatically, and do not contact maintainers or third parties in bulk. An agent may draft a report; a human publishes it after review. Promotion must follow real use and be disclosed.
