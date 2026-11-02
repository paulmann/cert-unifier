# FAQ

## What is Cert Unifier?

A single Bash script that scans Certbot `live/` and legacy `_leN` certificate
material, verifies that each private key belongs to its leaf certificate, and
writes one atomic `<domain>.pem` bundle per domain (private key, then the full
chain), plus an optional `.pfx`. Start at [Home](Home).

## Does it request, renew or revoke certificates?

No. It never touches the network and never talks to an ACME server. It only
assembles files that already exist on disk. Renewal stays with Certbot or
whatever client you use.

## Does it reload nginx, Apache or any service?

No. It writes files and exits. Run the reload yourself after a successful exit
code — `systemctl reload nginx`, for example. The script cannot know which
service consumes a bundle.

## Which input layouts are supported?

Two, recognised by file name: `<root>/<domain>/fullchain.pem` with
`privkey.pem`, and `<dir>/<domain>_le<N>.crt` with `.crtca` and a `.key`. Other
ACME clients' file names are not detected. See [Layouts](02-Layouts).

## Why is the version 3.1.1 and not 3.0.0?

Version 3.1.1 is the first published release of the 3.x line. 3.0.0 and 3.1.0
were prepared and reviewed but never released: 3.1.0 failed review with the
defects listed under "Fixed" in the
[CHANGELOG](https://github.com/paulmann/cert-unifier/blob/main/CHANGELOG.md), and
their changes are folded into 3.1.1.

## How is this different from `cat privkey.pem fullchain.pem > site.pem`?

The script adds, in this order:

1. a public-key check that the key and the leaf certificate belong together
   (RSA and EC) before anything is written;
2. atomic writes in the target directory, so a reader never sees a truncated
   bundle;
3. mode 0600 on the result, enforced even when the content did not change;
4. idempotency, so a byte-identical bundle keeps its mtime;
5. refusal of a missing or unreadable key instead of a key-less bundle;
6. a machine-readable summary and meaningful exit codes for automation.

The reasoning behind each item is in [Why unify certificates](01-Why-Unify).

## Can I run it from cron repeatedly?

Yes. It is idempotent: an unchanged bundle is not rewritten and keeps its mtime,
so a cron run does not trigger needless reloads. The mode is still corrected to
0600. Ensure only one run touches a tree at a time; `flock` enforces that when
it is installed. See [Install and upgrade](07-Install-and-Upgrade).

## Can I point it at `/etc/letsencrypt/live`?

Yes. It reads there and, by default, writes `<domain>.pem` into the same
directory, which usually needs root. If the process should not write into
`/etc/letsencrypt`, use `-o /var/www/tls` (the directory must exist). Always run
`--dry-run` first.

## Why does pointing at one `live/<domain>/` directory exit 2?

Because the Certbot scanner reads the immediate subdirectories of
`ROOT_DIRECTORY`, and a single domain directory has no such subdirectories.
Pass the `live/` directory instead. This is the most common "nothing matched"
surprise; see [Troubleshooting](08-Troubleshooting).

## Why was my `.org` domain skipped?

The TLD filter is on by default and allows `ru com`. Use `-t org` (or the
`ALLOWED_TLDS` environment variable) to change the list, or `--no-tld-filter` to
process everything. A tree where every domain is filtered out exits 2.

## Does it check that the certificate matches the domain name?

No. Only the key-to-leaf-certificate match is verified. The domain is a label
taken from the directory or file name, and no subject/SAN comparison is made.
That is a deliberate scope limit, stated in [Security model](03-Security).

## Does it check expiry?

Only with `--check-expiry`, and only as a warning. It inspects bundles written
in the current run; an all-`unchanged` run reports nothing. It never refuses an
expired certificate and never changes the exit code. To check an existing
bundle: `openssl x509 -in <domain>.pem -noout -enddate`.

## Does it validate chain trust, CRL or OCSP?

No. A bundle can be perfectly assembled and still fail client validation
because an intermediate is wrong or a certificate was revoked. The script
guarantees key/certificate matching, format, permissions and atomicity — not
trust.

## Is `--json` safe to parse in automation?

Yes, with two rules: capture stdout and stderr separately, and treat empty
stdout as failure. With `--json`, stdout carries only the JSON document (INFO
logs are suppressed, WARN/ERROR go to stderr), but failures before scanning —
usage errors, a missing root, another instance holding the lock — exit without
writing any JSON. The schema is in
[JSON summary and exit codes](06-JSON-and-Exit-Codes).

## Is there an exit code 3?

No. The contract is `0` done, `1` refused or failed, `2` nothing matched, `130`
interrupted.

## Does `--json` change the exit codes?

No. The document explains the run; the exit code is still chosen from the same
counters. `status` `success` / `none` / `error` mirrors `0` / `2` / `1`, with the
dry-run case counting as success.

## How do I keep the PFX password out of the process list?

You cannot hide it completely: the password is passed to OpenSSL as a command
line argument, and the environment variable has the same property once read.
Prefer `PFX_PASSWORD` over `--pfx-password`, keep the value short-lived, and do
not run `--pfx` on a host with untrusted local users. See
[Security model](03-Security).

## Can it fix a bundle left at 0644 by an older release?

Yes. On the idempotent path the content is kept but the mode is forced to 0600.
Where the filesystem does not implement modes (FAT, some network mounts, Git
Bash's chmod emulation) the correction cannot take effect and a warning is
possible.

## Does it ever delete or modify my source files?

No. Sources are only read. The script removes its own temporary files on exit;
generated bundles and PFX files stay where they were written. Uninstalling it
removes nothing else.

## Does it run on Windows and macOS?

macOS needs a Bash 4+ interpreter because the system Bash is 3.2. WSL is a
normal Linux environment. Git Bash on Windows runs it, but `chmod` is emulated
and `/var/lock` may be unavailable, so the lock and mode guarantees degrade to
warnings.

Still unanswered? Read the [Command reference](05-Command-Reference), then
[Troubleshooting](08-Troubleshooting); if the answer is not there, the
repository's [issues](https://github.com/paulmann/cert-unifier/issues) are the
place for a sanitized report.
