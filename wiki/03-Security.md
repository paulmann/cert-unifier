# Security model

Cert Unifier is a file assembler. Its security job is narrow, and it is
important not to overstate it.

## Scope

The script reads private keys and certificates that already exist on disk,
concatenates them into one bundle, writes that bundle with mode 0600 through a
temporary file and an atomic rename, and can export a PKCS#12 file. It does not
request, renew or revoke certificates, does not modify the source files, does
not reload a service and makes no network calls. The only files it deletes are
its own temporary files.

## What it does

- No network access of any kind.
- `umask 077` for the whole process; bundles and PFX files are 0600.
- Bundles are assembled in a temporary file in the target directory, set to
  mode 0600, then renamed over the destination.
- The public key of the private key is compared with the public key of the leaf
  certificate before anything is written, for RSA and EC keys.
- A mismatched key, a passphrase-protected key, an unparsable key or no key at
  all is refused with exit code 1 and no bundle.
- Passphrase-protected keys are detected by content and never handed to OpenSSL
  for an interactive prompt, so the run cannot hang waiting for a passphrase.
- `--json` and every log line contain paths, statuses and fingerprints only —
  never key material.
- A lock file (`flock -n`) keeps two concurrent runs from touching the same
  tree, and the second run exits 1 instead of writing.

## What it does not do

- It does not verify chain trust, CRL or OCSP status. A bundle can be perfectly
  formed and still fail a client-side validation.
- It does not check the certificate subject or SAN against the domain in the
  file or directory name. Only key-to-certificate matching is enforced, so a
  name is a label, not a verified identity.
- It does not refuse an expired certificate; `--check-expiry` warns about
  expiry (and about an already expired certificate) but leaves the exit code
  alone.
- It does not protect against anyone who can already read the source private
  keys or write to the target directory.
- It writes the private key into every bundle; mode 0600 is the only protection,
  and there is no certificate-only mode.
- It never deletes, rotates or installs anything, and it never reloads a
  service.

## Operational exposure

| Exposure | Detail | What to do |
|---|---|---|
| PFX password in the process list | It is passed to OpenSSL as `-passout pass:...` and is visible in `ps` for the duration of that call. The `PFX_PASSWORD` environment variable has the same property once read. | Prefer `PFX_PASSWORD` over `--pfx-password`, keep the secret short-lived, do not run `--pfx` on a shared host with untrusted local users. |
| Empty PFX password | An empty password produces an unencrypted `.pfx`. | Set a password or do not use `--pfx`. |
| Lock file permissions | The default `/var/lock/cert-unifier.lock` usually needs root; without a writable lock file the run continues unlocked with a warning. | Set `CERT_UNIFIER_LOCK` to a path the operator can write, and make sure the tree is owned consistently. |
| Running as root | Root-owned bundles may be unreadable by the service that needs them; root also multiplies the consequence of a mistake. | Run `--dry-run` first, and run as the user that must read the bundle when the tree allows it. |
| `--no-key-validation` | Bundles material whose key cannot be verified. | Use it only for material that genuinely cannot be checked, and record why. |
| Source permissions | The script cannot repair the exposure of the files it reads. | Keep private keys at 0600 at the source; the bundle is only as private as the target directory. |

The threat model is also stated, in shorter form, in
[SECURITY.md](https://github.com/paulmann/cert-unifier/blob/main/SECURITY.md).

## Reporting

Do not open a public issue for a vulnerability. The primary channel is GitHub's
private vulnerability reporting for the repository:
[Report a vulnerability privately](https://github.com/paulmann/cert-unifier/security/advisories/new).
Include the version (`cert-unifier.sh --version`), Bash and OpenSSL versions,
the exact command, the output and a minimal fixture made of synthetic
certificates. Never paste a real private key, a passphrase or customer data.

Next: [Architecture](09-Architecture) — where these guarantees are implemented.
