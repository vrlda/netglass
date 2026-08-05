# G4 calibration — real nettop capture (`Fixtures/nettop/capture-1.txt`)

Research gate G4 from `docs/roadmap.md`: pin down exactly what `nettop -J` exposes
as a non-root user on this machine, so the Task 5 `NettopParser` contract is
grounded in reality. This fixture is the parser's reference input; the synthetic
fixture (`synthetic.txt`) mirrors it for deterministic CI tests.

## Machine

- macOS 26.5.2 (build 25F84) — `sw_vers`
- `netttop` at `/usr/bin/nettop` (Darwin man page date 4/5/10)
- No root used; all values visible to the current user, including
  root-owned daemons (e.g. `syspolicyd.685` shows byte counters without root)

## Capture command (final)

```bash
/usr/bin/nettop -L 1 -J bytes_in,bytes_out,interface,state,time > Fixtures/nettop/capture-1.txt
```

`scripts/fetch-nettop-fixture.sh` wraps this and verifies the first line is a
`time,,` CSV header before reporting success (nettop prints usage text and still
exits 0 when given invalid flags — the script catches that).

### Why the command differs from the plan

The plan (`docs/architecture.md`) assumed
`nettop -P -L 1 -J bytes_in,bytes_out,interface,state,local_address,remote_address,protocol`.
Three of those column names **do not exist** on this macOS version. Giving
`local_address`/`remote_address`/`protocol` (or `local`, `remote`, `conn_id`,
`pid`, `process`, `name`, `provenance`) makes nettop print its usage banner to
stdout and exit 0 — silently producing a garbage fixture. The header shows every
column that **does** exist; the endpoint pair and protocol are carried in the
provenance token instead (below). `-P` (collapse-to-process-summary) was dropped
because it suppresses all connection rows entirely, leaving no endpoints to parse.

## Observed format (302 lines: 1 header + 301 data rows)

Header line (exactly as emitted):

```
time,,interface,state,bytes_in,bytes_out,
```

- The provenance column is **unnamed** (empty header field, always the second column).
- Column order in the header is **nettop's default order, not the `-J` request
  order** (man page: "The ordering is currently as per nettop default"). Every
  line ends with a trailing comma (an always-empty final field). All rows have
  exactly 7 CSV fields with the 5-column `-J` set used here.
- `-J` does correctly **limit** which columns appear (verified: requesting
  `uuid,time` emits only `time,,uuid,`). `-j` adds, `-k` removes, `-J` selects.

Row classes (interleaved per process, one process summary row + its connection rows):

| Class | Example (redacted) |
|---|---|
| Process summary | `00:34:29.230774,apsd.590,,,5542,34103,` |
| TCP connection | `00:34:29.225703,tcp4 198.18.0.1:65333<->17.57.146.137:5223,utun8,Established,5542,34103,` |
| Listener | `00:34:29.2...,tcp4 *:51560<->*:*,,Listen,,,` |
| UDP connection | `00:34:29.2...,udp4 192.168.1.42:5353<->239.255.255.250:1900,en0,,0,0,` |
| Wildcard UDP | `00:34:29.2...,udp4 *:*<->*:*,,,,,` |
| QUIC | `00:34:29.2...,quic4 192.168.1.134:64243<->8.47.69.0:443,en0,,4182,3700,` |
| Scoped IPv6 (1 row) | `00:34:29.2...,quic6 fe80::7ca2:20ff:fe4d:277%awdl0.52214<->fe80::13:faff:fe55:a839%awdl0.50386,awdl0,,1001065,136242,` |

### Provenance token grammar (LOCKED for Task 5)

`PROTO local<->remote` — a single space separates the protocol prefix from the
endpoint pair. Everything before the first space is the protocol; the rest is
`local<->remote` split on the `<-` and `->` tokens.

- Protocols observed: `tcp4`, `tcp6`, `udp4`, `udp6`, `quic4`, `quic6`.
  (No plain `tcp`/`udp` — there is **no separate protocol column**.)
- Local/remote rendering:
  - IPv4: `ip:port` (`192.168.1.42:51234`)
  - IPv6: `addr.port` — **`.` separator, not `:`** (`fe80::...%awdl0.52214`)
  - Wildcard: `*:*`, `*.5353` (bound), `*.*` (unbound; `udp6` uses `.` throughout)
  - Hostnames appear when name resolution succeeds (`one.one.one.one:443`,
    `localhost:49618`, `cdn-185-199-111-133.github.com:443`) — resolution is on
    by default and works without root; numeric IPs appear otherwise.
  - **Scoped IPv6 `%zone` observed** (`fe80::7ca2:20ff:fe4d:277%awdl0.52214`,
    awdl0 link-local). `IPAddress` rejects `%zone` input by design
    (`19f9edb`), so the parser must skip such rows — exactly 1 row in this capture.
- Process summary rows use `Name.pid` as the whole provenance token (no endpoint).

### Deviations from the assumed contract (the plan's `ProcName.pid [conn-id]` model)

1. **No `[conn-id]` token anywhere.** Connection rows carry the endpoint pair in
   the provenance token; there is no bracket token. Process summary rows carry
   only `Name.pid`.
2. **No `local_address` / `remote_address` / `protocol` columns** — these names
   are invalid on macOS 26.5.2 and trigger the usage dump (exit 0, no data).
3. **`-P` suppresses connection rows** — per-process summaries only
   (`Name.pid,,,bytes_in,bytes_out,`); the fixture omits `-P` on purpose.
4. **Missing values are empty fields, never `-`.** `-` appears nowhere in the
   capture. Empty `interface`/`state`/`bytes_in`/`bytes_out` are normal
   (process rows, listeners, QUIC/UDP).
5. **`-J` does not reorder columns** — the header defines the order; the parser
   must read the header and map by position, never assume `-J` order.
6. **Protocol is a provenance prefix** (`tcp4`/`udp4`/`quic6`…), not a field.
7. **State values**: `Established`, `Listen`, `TimeWait`, `Closed`, or empty
   (UDP/QUIC have no state). Capitalized.
8. **`time` column exists** (`HH:MM:SS.ffffff`) — the plan's parser didn't
   account for a leading time field.
9. **Process names may contain spaces and parentheses**
   (`Google Chrome H.74297`, `Codex (Service).65506`, `OpenCode Helper.71829`,
   `com.apple.WebKi.1790`). **No commas observed in any name** — a naive CSV
   split stays safe, but the parser should still split provenance on the first
   space and never re-join.
10. There is a valid `uuid` column (per-connection UUID, empty on process
    rows) if a connection identifier is needed later; it was omitted from the
    fixture to keep the column set minimal.

### Interfaces and states seen

- Interfaces: `en0`, `lo0`, `utun8` (Tailscale), `awdl0` — no wired `enX` variety here.
- Sample composition: 302 lines, 168 `Established` rows, ~48 `quic*` rows, 1 scoped row.

## Parser contract for Task 5 (LOCKED)

Given the header `time,,interface,state,bytes_in,bytes_out,`:

1. Skip the header line (line 1; first field is `time`).
2. Split each line on `,` — 7 fields for the 5-column capture (trailing empty
   field after the final comma).
3. Field 0 = `time`, field 1 = provenance token, fields 2..6 = columns named by
   the header (`interface`, `state`, `bytes_in`, `bytes_out`).
4. Provenance `Name.pid` (no `<->`) → process summary row → **skip** (no usable
   endpoint; optionally surface as a process-only record later).
5. Provenance `PROTO local<->remote`:
   - protocol = prefix up to first space (`tcp4`/`udp4`/`tcp6`/`udp6`/`quic4`/`quic6`)
   - endpoint pair = remainder split on `<->`
   - skip rows with wildcard endpoints (`*:*`, `*.5353`, `*.*`)
   - skip rows with `%zone` scoped addresses (IPAddress rejects them)
6. Missing byte counters (empty `bytes_in`/`bytes_out`, e.g. listeners) → `0`.

## Synthetic fixture

`synthetic.txt` follows this locked format exactly (header + 10 rows:
process-summary, established IPv4, scoped IPv6, listener, UDP, QUIC, hostname
remote, two deliberately malformed rows). The two malformed rows are the
`%zone` scoped row and a `tcp4 malformed-endpoint-token` row — both must be
skipped by the parser. Deterministic timestamps (`00:00:00.000001`…) so tests
are reproducible.

## Regenerating

```bash
./scripts/fetch-nettop-fixture.sh
```

The capture is a live snapshot; do **not** regenerate it inside CI (contents
would vary). `synthetic.txt` is the deterministic test input.
