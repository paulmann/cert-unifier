# Contributing

Thank you for considering a contribution.

## Development

```bash
git clone https://github.com/paulmann/cert-unifier.git
cd cert-unifier
chmod +x cert-unifier.sh tests/run-tests.sh
./tests/run-tests.sh
```

## Style

- Bash 4.0+ compatible; the script runs under `set -euo pipefail`.
- Prefer pure Bash where reasonable; keep new dependencies optional.
- Never let a private key reach the log, the JSON output or a command line.
- `shellcheck -x cert-unifier.sh tests/run-tests.sh` must be clean before
  submitting.

## Tests

All changes must keep `tests/run-tests.sh` green, and a bug fix should come with
a case that fails before it and passes after it. The suite asserts exit codes
and behaviour, not just "a file appeared", so a green run is meaningful.

Run it on the versions the project supports: OpenSSL 1.1.1 and 3.x, with Bash 4
or newer.

## Documentation

- `README.md` is the human entry point; `AGENTS.md` is the agent-facing
  contract.
- The README exists in six languages. A change to the English README must be
  reflected in `README.de.md`, `README.ru.md`, `README.zh.md`, `README.hi.md`
  and `README.es.md` in the same pull request, keeping structure and anchors
  identical.
- `CHANGELOG.md` follows Keep a Changelog: add your entry under an
  `## [x.y.z] - YYYY-MM-DD` heading with `Added` / `Changed` / `Fixed` /
  `Security` subsections.
- Wiki sources live in `wiki/`; `wiki/wiki.json` lists every page, and a page
  that exists but is not listed is an error.

## Versioning

Semantic versioning. A defect fix that changes behaviour is a patch release
(`3.1.2`), a new flag is a minor release (`3.2.0`). Never reuse a version number
for different content.

## Licensing

The project is released under the [MIT licence](LICENSE). By submitting a
contribution you agree that it may be distributed under that licence.
