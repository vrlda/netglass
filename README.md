# netglass

[![CI](https://github.com/vrlda/netglass/actions/workflows/ci.yml/badge.svg)](https://github.com/vrlda/netglass/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/vrlda/netglass)](https://github.com/vrlda/netglass/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A process-aware network monitor for macOS. Netglass shows which apps are talking, to whom, and how much — live per-app connections, domains with reverse-DNS evidence, DNS activity, packet capture and inspection, and persistent history. It also runs read-only OPSEC sessions that watch for leaks: tunnel bypasses, resolver drift, out-of-scope destinations, and periodic background communication.

## Features

- **Live connections** — per-process flows with real-time throughput, app icons, process ancestry (`launchd → zsh → python3`), and per-connection details
- **Apps & Domains** — traffic aggregated per application and per domain, with forward-confirmed reverse-DNS evidence for every hostname
- **DNS activity** — live DNS query monitoring
- **Packet capture & inspector** — ring-rotated pcapng captures with packet decoding (Ethernet, IP, TCP, UDP, ICMP, DNS, HTTP, TLS SNI, certificate details), TCP stream reassembly, hex viewer, and a **sensitive-data scanner** that flags plaintext credentials (HTTP auth headers, URLs with embedded passwords, FTP/Telnet/POP3 logins, sensitive DNS names)
- **Operation Mode** — a named OPSEC session: pick an expected tunnel interface and a scope, then get a live timeline of connections/DNS/listeners, leak warnings (interface mismatch, IPv6 escape, pre-tunnel DNS, resolver drift, out-of-scope or excluded destinations, exposed listeners, traffic after stop), **periodic-communication detection** (regular outbound intervals per process/destination), a cleanup report when the session ends, and a JSON evidence export
- **Scope import** — define scope inline or import a YAML file (`allowed:` / `excluded:` blocks with CIDRs and `*.domains`)
- **Trust inspection** — for any process: signed/unsigned, team ID, signing authority, SHA-256, temp-path/disk-image/system-binary flags, executable changed since first seen, network entitlements
- **History** — persistent flow database with full-text search, filters, and CSV/JSON export
- **Menu bar meter** — Little-Snitch-style speed bars showing per-second download/upload
- **GeoIP** — offline country lookup for IPv4 and IPv6
- **flowdump** — a headless CLI that streams flow samples to the terminal

## Requirements

- macOS 15 or later
- Apple Silicon or Intel

## Install

Download `Netglass-v1.1.0-macos15.zip` from the [latest release](https://github.com/vrlda/netglass/releases), unzip, and drag `Netglass.app` into Applications. On first launch, right-click the app and choose **Open** (the app is ad-hoc signed and not notarized).

Starting your first packet capture prompts for an admin password — this is required to read packet data and is only used for the capture itself.

## Building from source

```sh
git clone https://github.com/vrlda/netglass.git
cd netglass
swift build          # builds the app and the flowdump CLI
swift test           # runs the test suite (218 tests, fully offline)
./scripts/build-app.sh --open   # assemble the .app bundle and launch it
```

## Usage

- Click the menu bar meter for a quick speed readout; click the Dock icon or launch the app for the full window
- The sidebar organizes traffic by Applications, Domains, DNS, Captures, Packet Inspector, History, and Operations
- Packet Inspector opens pcap/pcapng files or live captures; select a flow to follow its TCP stream, inspect TLS certificates, and see a trust report for the process behind it
- **Operations**: Start → pick a tunnel interface and scope → run your tools normally → Netglass warns on leaks and periodic communication → Stop → review the cleanup report → Export evidence
- Filters support token-based expressions (e.g. `app contains "chrome"`, `domain is-not "apple.com"`) via the toolbar search

## How it works

Netglass collects data exclusively through read-only macOS APIs:

- One-shot `nettop` snapshots per second give per-connection byte counters (a lightweight alternative to a hot streaming process)
- `lsof` snapshots fill in process identities; sockets are joined to flows across protocols
- Process parents come from `proc_pidinfo`; signing/trust checks use the offline Security framework
- Domain names come from reverse DNS with forward-confirmation (FCrDNS), so every displayed name is evidence-backed
- Packet capture uses a helper launched via `osascript` with your one-time consent; files are ring-rotated to bound disk usage
- Sampling is adaptive: when nothing changes, ticks slow down automatically

All history lives locally in `~/Library/Application Support/Netglass`. Nothing leaves your machine.

## Repository layout

```
apps/NetglassMac   the macOS app (SwiftUI, AppKit-rendered menu bar meter)
packages/FlowModel   shared flow event model
packages/FlowSource   nettop/lsof sampling, DNS resolution, session tracking, process ancestry
packages/Persistence  SQLite flow database
tools/flowdump     headless CLI
scripts/           build and packaging helpers
```

## License

MIT — see [LICENSE](LICENSE).
