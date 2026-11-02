# Support

Cert Unifier is a self-contained Bash script maintained in spare time. Before
asking for help, run the checks below: they answer most installation and
behaviour questions without a round trip.

## Before you ask

```bash
./cert-unifier.sh --version
./cert-unifier.sh --help
bash --version
openssl version
```

The output of these four commands is the first thing any helper needs, together
with the exact command you ran and its full output.

## Documentation

- [README.md](README.md) — installation, options, layouts, JSON summary and exit
  codes; translated into five additional languages.
- [Wiki](https://github.com/paulmann/cert-unifier/wiki) — why the tool verifies
  keys, the layouts it understands, the security model and how the behaviour is
  tested.

## Questions and defects

- Usage question or reproducible defect:
  [open an issue](https://github.com/paulmann/cert-unifier/issues/new/choose)
  and pick the matching form.
- The bug form asks for the version, the distribution, the Bash and OpenSSL
  versions and a minimal reproduction. That is the information needed to answer;
  a report without it usually costs an extra round trip.
- Never paste private keys, passphrases, certificate contents or personal data
  into an issue. Redact a reproduction down to the command and the error.

## Security problems

Do not open a public issue. Follow [SECURITY.md](SECURITY.md): report privately
through GitHub's private vulnerability reporting, with the same version and
reproduction details.

## Supported versions

Only the current 3.1.x line is supported. See the table in
[SECURITY.md](SECURITY.md) for the versions considered end of life.

## What is out of scope

Cert Unifier assembles and validates files that already exist on disk; it does
not obtain, renew or revoke certificates, does not reload services and makes no
network calls. Reports about certificate issuance belong to the ACME client
(for example Certbot), not to this project.
