# netglass

[![CI](https://github.com/vrlda/netglass/actions/workflows/ci.yml/badge.svg)](https://github.com/vrlda/netglass/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/vrlda/netglass)](https://github.com/vrlda/netglass/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A process-aware network monitor for macOS. Netglass shows which apps are talking, to whom, and how much — live per-app connections, domains with reverse-DNS evidence, DNS activity, packet capture and inspection, and persistent history.

## Features

- **Live connections** — per-process flows with real-time throughput, app icons, and per-connection details
- **Apps & Domains** — traffic aggregated per application and per domain, with forward-confirmed reverse-DNS evidence for every hostname
- **DNS activity** — live DNS query monitoring
- **Packet capture & inspector** — ring-rotated pcapng captures with packet decoding (Ethernet, IP, TCP, UDP, ICMP, DNS, HTTP, TLS SNI, certificate details), TCP stream reassembly, and a hex viewer
- **History** — persistent flow database with full-text search, filters, and CSV/JSON export
- **Menu bar meter** — Little-Snitch-style speed bars showing per-second download/upload
- **GeoIP** — offline country lookup for IPv4 and IPv6
- **flowdump** — a headless CLI that streams flow samples to the terminal

## Requirements

- macOS 15 or later
- Apple Silicon or Intel

## Install

Download `Netglass-v1.0.0-macos15.zip` from the [latest release](https://github.com/vrlda/netglass/releases), unzip, and drag `Netglass.app` into Applications. On first launch, right-click the app and choose **Open** (the app is ad-hoc signed and not notarized).

Starting your first packet capture prompts for an admin password — this is required to read packet data and is only used for the capture itself.

## Building from source

```sh
git clone https://github.com/vrlda/netglass.git
cd netglass
swift build          # builds the app and the flowdump CLI
swift test           # runs the test suite (162 tests, fully offline)
./scripts/build-app.sh --open   # assemble the .app bundle and launch it
```

## Usage

- Click the menu bar meter for a quick speed readout; click the Dock icon or launch the app for the full window
- The sidebar organizes traffic by Applications, Domains, DNS, Captures, and History
- Packet Inspector opens pcap/pcapng files or live captures; select a flow to follow its TCP stream and inspect TLS certificates
- Filters support token-based expressions (e.g. `app contains "chrome"`, `domain is-not "apple.com"`) via the toolbar search

## How it works

Netglass collects data exclusively through read-only macOS APIs:

- A long-lived `nettop` process streams per-connection byte counters in real time
- `lsof` snapshots fill in process identities; sockets are joined to flows across protocols
- Domain names come from reverse DNS with forward-confirmation (FCrDNS), so every displayed name is evidence-backed
- Packet capture uses a helper launched via `osascript` with your one-time consent; files are ring-rotated to bound disk usage

All history lives locally in `~/Library/Application Support/Netglass`. Nothing leaves your machine.

## Repository layout

```
apps/NetglassMac   the macOS app (SwiftUI, AppKit-rendered menu bar meter)
packages/FlowModel   shared flow event model
packages/FlowSource   nettop/lsof streaming, DNS resolution, session tracking
packages/Persistence  SQLite flow database
tools/flowdump     headless CLI
scripts/           build and packaging helpers
```

## License

MIT — see [LICENSE](LICENSE).
