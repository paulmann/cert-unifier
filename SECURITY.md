# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 3.1.x | Yes |
| 3.0.x, 3.1.0 | No — never released; 3.1.0 failed review |
| 2.9.x | No (superseded) |

## Scope

Cert Unifier assembles and validates files that already exist on disk. It does
not obtain, renew or revoke certificates, does not modify source material, and
makes no network calls. Its security-relevant work is:

- reading private keys and concatenating them into a bundle;
- writing that bundle with mode 0600 through a temporary file and an atomic
  rename;
- optionally exporting a PKCS#12 file.

The tool does not protect against an attacker who can already read the source
private keys or write to the target directory. It does not verify chain trust,
CRL or OCSP status; it verifies that key and leaf certificate match.

## Known exposure

- The PKCS#12 password is passed to OpenSSL as an argument and is visible in the
  process list for the duration of that call. An empty password produces an
  unencrypted `.pfx`.
- A bundle always contains the private key, protected only by mode 0600.

## Reporting a Vulnerability

Please do **not** open a public GitHub issue for security problems.

The primary channel is GitHub's private vulnerability reporting for this
repository:
[Report a vulnerability privately](https://github.com/paulmann/cert-unifier/security/advisories/new).
It keeps the report, the discussion and the fix private until an advisory is
published.

If private reporting is unavailable, write to
<paulmann@users.noreply.github.com> and say in the subject that the message is a
security report. Do not include a private key, a passphrase or customer data in
the first message; describe the issue and, if a fixture is essential, replace
real material with synthetic certificates.

Include:

- a description of the issue;
- steps to reproduce, or a minimal fixture;
- the affected version (`cert-unifier.sh --version`);
- Bash and OpenSSL versions (`bash --version`, `openssl version`);
- potential impact.

We aim to respond within 7 days, and to publish a fixed release within 30 days
of confirming an issue in a supported version.
