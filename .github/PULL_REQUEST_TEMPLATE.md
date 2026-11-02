## Summary

What changes, and why? One logical change per pull request.

## Type of change

- [ ] Bug fix
- [ ] Feature
- [ ] Documentation (README, AGENTS.md, wiki)
- [ ] CI / build / release
- [ ] Security

## Verification

- [ ] `shellcheck -x cert-unifier.sh tests/run-tests.sh` is clean
- [ ] `./tests/run-tests.sh` reports the same result as on `main` (or a better
      one, with the new case explained)
- [ ] New or updated tests cover the change; a behaviour fix has a case that
      fails before and passes after it
- [ ] `CHANGELOG.md` has an entry under `## [Unreleased]` or under the version
      being prepared
- [ ] An English `README.md` change is mirrored in `README.de.md`, `README.ru.md`,
      `README.zh.md`, `README.hi.md` and `README.es.md`
- [ ] Wiki sources in `wiki/` and `wiki/wiki.json` are consistent with the change

## Safety

- [ ] No private keys, passphrases, tokens, personal data or absolute local paths
      in the diff, in fixtures, or in test output
- [ ] Line endings and encoding are unchanged unintentionally (UTF-8 without BOM,
      LF; `.bat`/`.cmd` stay CRLF)
- [ ] `cert-unifier.sh` still runs under `set -euo pipefail` with Bash 4.0+

## Release impact

- [ ] No release needed
- [ ] Patch release (behaviour fix)
- [ ] Minor release (new flag or option)
- [ ] Major release (breaking change, migration notes written)
