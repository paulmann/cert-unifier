# Why unify certificates

Assembling a usable TLS bundle from the files that Certbot, acme.sh or custom
scripts leave on disk looks trivial. In practice it is a frequent source of
outages, mismatched keys and security incidents — which is why Cert Unifier
treats the assembly step as an audited operation rather than a `cat`.

## 1. Key / certificate mismatch

The single most common failure mode.

- Certbot rotates the private key on renewal.
- Legacy layouts keep `_le1`, `_le2`, `_le10` side by side.
- Operators copy the wrong key, or a script writes a new key without updating
  the certificate next to it.
- A server that starts with a mismatched key fails the handshake later, at the
  worst possible moment.

**What Cert Unifier does**: the public key of the private key is compared with
the public key of the leaf certificate (`openssl x509 -pubkey` against
`openssl pkey -pubout`) before every write, for RSA and EC keys. Modulus hashing
works only for RSA, which is why it is not used. A mismatch ends that entry with
exit code 1 and leaves no bundle behind. `--skip-pfx-on-mismatch` downgrades the
refusal to a skip: a warning is logged, the entry is counted as skipped, and
still nothing is written.

## 2. PEM order and newline discipline

A bundle has to be the private key first, then the full chain with the leaf
before the intermediates. Concatenating files with `cat` without a terminating
newline produces a PEM that OpenSSL accepts but a strict web server rejects.

**What Cert Unifier does**: key first, then the chain; every copied block gets a
guaranteed newline, and the assembled file is validated before it is renamed
into place.

## 3. Race conditions on renewal

Certbot renews in place. A web server that reads the bundle while it is being
overwritten can see a truncated file.

**What Cert Unifier does**: the bundle is assembled in a temporary file in the
target directory (same filesystem), set to mode 0600, then renamed over the
destination with `mv -f`. A failed run leaves the previous bundle intact.

## 4. Permissions

Private keys must be mode 0600 or tighter. Deployment scripts often leave 0644,
and a `.pfx` contains the private key too.

**What Cert Unifier does**: `umask 077` for the whole run, an explicit
`chmod 600` on the temporary file before the rename, and a mode correction when
the content is unchanged.

## 5. Layout fragmentation

| Input shape | Supported |
|---|---|
| `<root>/<domain>/fullchain.pem` + `<root>/<domain>/privkey.pem` (Certbot and similar `live/` trees) | yes |
| `<dir>/<domain>_le<N>.crt` + `.crtca` + a `.key` (legacy ISP layout) | yes |
| `<domain>.cer` + `<domain>.key` + `ca.cer` (acme.sh) | no |
| one `.pfx` per domain | output only, never an input |

No single convention exists. The script detects the two supported file-name
patterns and otherwise reports that nothing matched (exit code 2) instead of
guessing. The details are in [Layouts](02-Layouts).

## 6. Intermediate chain completeness

- `fullchain.pem` already contains the leaf and the intermediates.
- Legacy layouts usually store the leaf and the chain in separate files.
- A missing intermediate breaks clients that do not have it cached.

**What Cert Unifier does**: for the Certbot layout it copies `fullchain.pem` as
it is; for the legacy layout it concatenates the newest generation's leaf and
its `.crtca` chain into a temporary file, and refuses the entry when that chain
file is missing.

## 7. PFX specifics

- A command-line password is visible in the process list; the environment
  variable has the same property once the script reads it.
- The friendly name is set with `-name`; the `pkcs12` command has no
  `-friendlyname` option on OpenSSL 1.1.1 or 3.x. Using a nonexistent option
  made `--pfx` fail on every OpenSSL 3.x release before 3.1.1.
- An empty password is legal and produces an unencrypted `.pfx`.

## 8. Operational hazards

- Running as root versus a dedicated user.
- Lock files in `/var/lock`, which tmpfiles cleanup may remove.
- Logging that accidentally includes private key material — never do this.
- Idempotency: rewriting an identical file changes mtime and can trigger
  unnecessary reloads.

## 9. What "audited" means here

An audited bundle guarantees:

1. The private key cryptographically matches the leaf certificate.
2. The PEM is well formed and every block ends with a newline.
3. Permissions are 0600.
4. The write was atomic.
5. A byte-identical bundle is not rewritten (mtime preserved, mode enforced).
6. `--check-expiry` reports expiry warnings for the bundles written in that run.
7. `--json` reports a SHA-256 fingerprint for every updated bundle.

Point 1 is enforced before anything is written; it is also the only point that
`--no-key-validation` can switch off, and that opt-out logs a warning and is
meant for material that cannot be verified at all. The security consequences are
spelled out in [Security model](03-Security).

These properties are what separate a reliable unifier from a one-line `cat`.

Next: [Layouts](02-Layouts) — the two input layouts and the newest-wins rule.
