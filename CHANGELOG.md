# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Documentation: added a banner and a social preview to the README header.
- Documentation: added the community and repository-health files
  (`CODE_OF_CONDUCT.md`, `SUPPORT.md`, `CITATION.cff`, `.github/CODEOWNERS`,
  `.github/dependabot.yml`, a pull-request template and issue forms) plus
  `.gitattributes` and `.editorconfig`.
- Documentation: expanded the wiki sources and condensed `AGENTS.md` into a
  contract under the 120-line agent-documentation limit, linking the README and
  wiki for detail.
- Documentation: changed the security contact to GitHub private vulnerability
  reporting, with a role address as the fallback; no personal address remains in
  the tree.
- Documentation: corrected the Certbot usage examples in the six READMEs and
  `AGENTS.md`; the argument is the tree root, not a single domain directory,
  which matches nothing and exits 2.

### Fixed

- `NO_KEY_VALIDATION` is honoured as an environment variable, as `--help` and
  the READMEs always documented. Previously the internal flag ignored the
  environment and only `--no-key-validation` had an effect.
- The `--no-key-validation` opt-out now reports a warning per bundled entry, as
  `AGENTS.md` and the wiki stated; it used to log at DEBUG level only.

## [3.1.1] - 2026-11-02

The first published release of the 3.x line. Version 3.1.0 was prepared and
reviewed but never released: it failed review with the blocking defects listed
under "Fixed" below. Version 3.0.0 was likewise never released, and its changes
are folded into this entry.

### Added

- `--json`: machine-readable run summary on stdout (`version`, `status`,
  `processed`, `skipped`, `planned`, `errors`, `warnings`, `results`).
- `--recursive`: scan nested subdirectories for the legacy `_leN` layout.
- `--check-expiry` and `--expiry-days N`: warn about certificates that are
  expired or close to expiry.
- Detection of passphrase-protected private keys, with a clear error instead of
  an interactive OpenSSL prompt.
- `--no-key-validation` as an explicit opt-out for keys that cannot be verified.
- A regression test suite (`tests/run-tests.sh`) that asserts exit codes and
  behaviour instead of only checking that files appear.
- GitHub Actions CI (test suite plus `shellcheck`), `SECURITY.md`,
  `CONTRIBUTING.md` and wiki sources.

### Changed

- Key/certificate matching uses public-key comparison for RSA **and** EC keys
  instead of RSA-only modulus hashing.
- Writes are atomic: the bundle is assembled in the target directory, set to
  mode 0600, then renamed over the destination.
- Log thresholds are honoured: `LOG_LEVEL=ERROR` no longer prints INFO lines.
- Option parsing continues after the positional `ROOT_DIRECTORY`, and a second
  positional argument is rejected instead of ignored.
- A `--dry-run` that finds work now exits 0 and reports what it would write,
  instead of exiting 2 as if nothing matched.
- The legacy layout processes the highest `_leN` generation per directory, so
  `_le10` is preferred over `_le1`.
- The bundled Changelog, README and AGENTS guide agree on one version number.
- The project is MIT-licensed throughout: the repository previously contradicted
  itself, with a script header saying MIT and `LICENSE` saying PolyForm
  Noncommercial 1.0.0. `--version` now reports MIT.

### Fixed

- `--pfx` failed on every OpenSSL 3.x release with `pkcs12: Extra (unknown)
  options: "friendlyname"`; the export now uses `-name`, which exists in both
  OpenSSL 1.1.1 and 3.x.
- `--json` truncated its output and exited 1 on any successful run: a bare
  `((i++))` aborted the script under `set -e`.
- A private key that did not match the certificate was written into the bundle
  silently when `--pfx` was not used; the match is now verified before every
  write.
- A legacy certificate with no `.key` file produced a key-less "unified" PEM
  and exit code 0; a missing private key is now an error.
- A passphrase-protected key made the run hang on the OpenSSL prompt.
- A structurally invalid key under a `BEGIN` header was accepted with a warning
  and written; validation is now fail-closed.
- `--expiry-days` accepted non-numeric values and later crashed with an unbound
  variable.
- An output path that was a directory caused a false "Updated" message and left
  a temporary file behind.
- An existing 0644 bundle was left at 0644 by the idempotent path; the mode is
  now enforced even when the content is unchanged.
- Two sources resolving to the same output file (`-o` with certbot and legacy
  layouts) no longer overwrite each other silently.

### Security

- Bundles are always written with mode 0600, including on the idempotent path.
- Unverifiable key material is refused rather than bundled.

## [2.9.0] - 2026-10-22

### Added

- Initial public release: Certbot and legacy layouts, modulus-based key/cert
  checks, PEM and optional PFX output, dry-run, TLD filter and a concurrency
  lock.

[Unreleased]: https://github.com/paulmann/cert-unifier/compare/v3.1.1...HEAD
[3.1.1]: https://github.com/paulmann/cert-unifier/releases/tag/v3.1.1
[2.9.0]: https://github.com/paulmann/cert-unifier/releases/tag/v2.9.0
