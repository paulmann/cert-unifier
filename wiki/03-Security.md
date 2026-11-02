# Security model

Cert Unifier is a file assembler. Its security job is narrow, and it is
important not to overstate it.

## What it does

- No network access of any kind.
- `umask 077` for the whole process.
- Bundles are assembled in a temporary file in the target directory, forced to
  mode 0600, then renamed into place.
- The private key is compared with the leaf certificate before anything is
  written; a mismatch, a passphrase-protected key, an unreadable key or a
  missing key is refused.
- Passphrase-protected keys are detected by content, never handed to OpenSSL for
  an interactive prompt.
- The `--json` summary and all log lines contain paths and fingerprints only —
  never key material.
- A lock file keeps concurrent runs from touching the same tree.

## What it does not do

- It does not verify chain trust, CRL or OCSP status. A bundle can be well
  formed and still lead to a client-side validation failure.
- It does not protect a key from someone who can already read the source file or
  write to the target directory.
- It does not delete, rotate or install anything.
- It writes the private key into the bundle. Mode 0600 is the only protection
  applied, and the script cannot emit a certificate-only bundle.

## Known exposure

- The PKCS#12 password is passed to OpenSSL as an argument, so it is visible in
  the process list for the duration of that call. The environment variable has
  the same property once read.
- An empty PFX password produces an unencrypted `.pfx`.
- The lock file defaults to `/var/lock/cert-unifier.lock`, which usually needs
  root; `CERT_UNIFIER_LOCK` relocates it.

## Reporting

See the [security policy](https://github.com/paulmann/cert-unifier/blob/main/SECURITY.md).
Do not open a public issue for a vulnerability.
