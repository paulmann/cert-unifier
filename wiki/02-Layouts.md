# Layouts

Cert Unifier understands two layouts. Everything else is reported as "no
matching certificates" and left alone.

## Certbot / live

```text
<root>/<domain>/fullchain.pem
<root>/<domain>/privkey.pem
```

Output: `<root>/<domain>/<domain>.pem`

The bundle is the private key followed by `fullchain.pem` unchanged.

## Legacy

```text
<root>/[<subdir>/]<domain>_le<N>.crt      leaf certificate
<root>/[<subdir>/]<domain>_le<N>.crtca    chain
<root>/[<domain>_le<N>.key | <domain>.key] private key
```

Output: `<domain>.pem` in the same directory.

`N` may be one or more digits. When several generations of the same domain sit
in one directory, the highest `N` wins: a stale `_le1` never overwrites a newer
`_le10`. This is deliberate — renewal counters only grow.

## Scanning depth

By default the target root and its immediate subdirectories are scanned. Add
`--recursive` to descend into the whole tree.

## Output directory

`-o, --output-dir PATH` relocates every bundle to `PATH/<domain>.pem`. The
directory must already exist. If two sources resolve to the same output name
(for example a Certbot entry and a legacy entry for the same domain), the run
logs a warning instead of overwriting silently.

## TLD filter

Only domains ending in the allowed suffixes are processed; the default is
`ru com`. Pass `-t, --tlds` or `ALLOWED_TLDS` to change it, or `--no-tld-filter`
to process everything. A tree that is entirely filtered out ends with exit code
2 and a hint to that effect.
