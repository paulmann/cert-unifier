# Why unify certificates

Assembling a usable TLS bundle from the files that Certbot, acme.sh or custom
scripts leave on disk looks trivial. In practice it is a frequent source of
outages, mismatched keys and security incidents.

## 1. Key / certificate mismatch

The single most common failure mode.

- Certbot rotates the private key on every renewal.
- Legacy scripts keep `_le1`, `_le2`, `_le10` side by side.
- Operators copy the wrong key, or a monitoring tool writes a new key without
  updating the chain.
- Result: the web server starts, the handshake fails with "key does not match
  certificate", or worse — the wrong key is served.

**Detection**: public-key comparison (`openssl x509 -pubkey` against
`openssl pkey -pubout`). Modulus hashing works only for RSA and is meaningless
for EC keys. Cert Unifier 3.1.1 compares public keys for both algorithms, and
it does so before every write, not only when a `.pfx` is requested.

## 2. PEM order and newline discipline

Many consumers are strict:

- Nginx and Apache expect the private key first, then the leaf, then the
  intermediates.
- Some older Java and Windows stacks require exactly one trailing newline and no
  blank lines between blocks.
- Concatenating with `cat` without a terminating newline produces a PEM that
  OpenSSL accepts but the web server rejects.

**Mitigation**: key first, then the full chain (leaf first), and a guaranteed
newline after every block.

## 3. Race conditions on renewal

Certbot renews in place. A web server that reads the bundle while it is being
overwritten can see a truncated file.

**Mitigation**: write to a temporary file in the same directory (same
filesystem, therefore an atomic rename), set the permissions on that file, then
`mv -f`.

## 4. Permissions

Private keys must be mode 0600 or tighter. Deployment scripts often leave 0644,
and a `.pfx` contains the private key too.

**Mitigation**: `umask 077` for the whole run, an explicit `chmod 600` before
the rename, and a mode correction even when the content is unchanged.

## 5. Layout fragmentation

| Source | Typical files |
|--------|---------------|
| Certbot | `live/<domain>/fullchain.pem` + `privkey.pem` |
| acme.sh | `<domain>/<domain>.cer` + `<domain>.key` + `ca.cer` |
| dehydrated | `certs/<domain>/fullchain.pem` + `privkey.pem` |
| Custom / ISP | `<domain>_le1.crt` + `<domain>_le1.crtca` + `<domain>_le1.key` |
| Windows / IIS | a single `.pfx` |

No single convention exists. Cert Unifier detects the two most common patterns
and refuses to guess at the rest.

## 6. Intermediate chain completeness

- `fullchain.pem` already contains leaf and intermediates.
- Legacy layouts usually store the leaf and the chain in separate files.
- Some CAs return the root; most servers do not want it.
- A missing intermediate breaks clients that do not have it cached.

**Mitigation**: for the legacy layout, concatenate leaf plus `.crtca`; for
Certbot, trust `fullchain.pem`.

## 7. PFX specifics

- Password handling: a command-line password is visible in the process list.
- The friendly name is set with `-name`; there is no `-friendlyname` option in
  the `pkcs12` command, on OpenSSL 1.1.1 or 3.x. Using a nonexistent option was
  a real defect that made `--pfx` fail on every OpenSSL 3.x release.
- The order inside the PKCS#12 bag matters for some IIS versions.
- An empty password is legal and insecure.

## 8. Operational hazards

- Running as root versus a dedicated user.
- Lock files in `/var/lock`, which systemd-tmpfiles may clean.
- Dry-run modes that still create temporary files.
- Logging that accidentally includes private key material — never do this.
- Idempotency: rewriting an identical file changes mtime and can trigger
  unnecessary reloads.

## 9. What "audited" means here

An audited bundle guarantees:

1. The private key cryptographically matches the leaf certificate.
2. The PEM is well formed and ends with a newline.
3. Permissions are 0600.
4. The write was atomic.
5. The certificate is not expired or near expiry, if `--check-expiry` was used.
6. A SHA-256 fingerprint is reported for correlation.
7. Identical content is not rewritten.

These properties separate a reliable unifier from a one-line `cat`. They are
enforced, not merely intended: an entry that cannot satisfy 1 is refused with an
error and no bundle is written.
