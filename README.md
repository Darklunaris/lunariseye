![Temporary Logo](https://k.top4top.io/p_3514x9kqz1.png)

LunarisEye — Network scanner (built on lunaris_engine)

WARNING — legal responsibility

Using LunarisEye incorrectly may be illegal and harmful. This tool is provided for authorized testing and research only. The authors, maintainers, and contributors accept no responsibility for misuse. You alone are responsible for obtaining permission and for any legal consequences.

Overview

LunarisEye is an advanced network scanning and web-audit CLI built exclusively on top of the `lunaris_engine` library. All core scheduling, prioritization and algorithmic behaviors in LunarisEye are implemented using `lunaris_engine` primitives — LunarisEye is intentionally a showcase and consumer of that library.

This README documents the tool's features, commands, internals, and usage examples.

Core characteristics and capabilities

- Exclusive runtime: built entirely on `lunaris_engine` for host prioritization and scheduling.
- Multi-modal scanning: port scanning with lightweight banner grabs, web header analysis, TLS certificate inspection, DNS checks, traceroute and GeoIP lookups.
- Composite one-shot checks: convenience commands like `web check`, `port check`, `cert check`, `dns check`, and `phone check` run a suite of probes and return a detailed JSON summary.
- Streaming JSONL for large scans: `scan` supports `--jsonl` to stream per-host results to disk to avoid high memory usage.
- Auto-export defaults: commands write a timestamped JSON export by default (overridable with `--export <path>`).
- Short alias: `c` is a shorthand that transforms `c web https://example.com` into `web check https://example.com`.
- Safety UX: the tool warns on scanning external (non-private) IPs and prints a clear legal notice in interactive mode.

Key features

- Port scanning and banner grabs
  - Adaptive timeouts: per-host EWMA RTT estimator to tune probe timeouts.
  - Concurrency pools (host-level and port-level via `package:pool`).
  - Banner grabs and lightweight protocol identification (SSH, HTTP, FTP, SMTP, TLS, etc.).
  - Per-port severity heuristics (levels: critical / high / medium / low / info) with scores and short notes.

- Web & HTTP analysis
  - Full HTTP fetch (headers + body), title extraction, resource enumeration and mixed-content detection.
  - Header security checks: HSTS, Content-Security-Policy (CSP), X-Frame-Options and other warnings.
  - TLS certificate inspection including subject, issuer, validity, and SHA1 fingerprint.

- Network intelligence
  - Traceroute (system traceroute when available).
  - GeoIP lookup (ip-api.com by default, with timeouts and graceful failure handling).
  - Service fingerprinting heuristics from response headers and banners.
  - WAF/CDN detection heuristics (Cloudflare, Vercel, Fastly, Akamai, CloudFront, Netlify, etc.).

- DNS checks and takeover heuristics
  - System `dig` usage (when available) to fetch CNAME/A records and a best-effort check for obvious takeover indicators.

- CLI UX
  - Interactive menu with saved profiles, picker, and persistence (profiles saved locally).
  - Single-shot commands for automation and scripting.
  - JSON and JSONL outputs for integration with pipelines.

Commands (summary)

- scan --cidr <cidr> [--ports <list>|--all-ports] [--concurrency N] [--jsonl] [--export <path>]
  - Full network scan over a CIDR, per-host banner/probe. Use `--jsonl` for streaming.

- analyze <url> [--scan-ports] [--ports <list>] [--export <path>]
  - HTTP fetch, header security checks and optional quick port scan.

- web check <url> [--scan-ports] [--export <path>]
  - High-level web audit: TLS cert, headers, mixed content, GeoIP, traceroute, fingerprint, WAF detection.

- port check <host> [--ports <list>] [--export <path>]
  - Single-host port scan with banners and severity scoring.

- cert check <host> [--port 443] [--export <path>]
  - TLS certificate inspection and summary.

- dns check <host> [--export <path>]
  - CNAME/A lookup and takeover probe heuristics.

- phone check <host> [--ports <list>] [--export <path>]
  - Composite command targeted at mobile devices: scans a curated set of ports (ADB/Google/HTTP/Telnet/SSH), collects banners, TLS, headers, GeoIP, traceroute, fingerprint, and aggregated severity summary.

- resolve <hostname>
  - DNS resolution helper.

Interactive usage

- Run the CLI with no arguments to enter the interactive menu. Profiles are persisted locally and can be run, exported or inspected from the menu.

Outputs and exports

- Default behavior: most check commands auto-write a timestamped JSON export. Filenames follow the pattern `lunariseye_<command>_<ISO-timestamp>.json`.
- For large scans use `--jsonl --export results.jsonl` to stream per-host JSON objects (one per line) and a final summary line.

Design notes & internals

- Prioritization: host ordering uses `lunaris_engine`'s routing implementation (link-state/Dijkstra) on a small synthesized graph to produce meaningful probe ordering.
- CIDR handling: lazy CIDR expansion to avoid materializing large address lists when possible.
- Timeout tuning: EWMA RTT per-host estimator to adapt timeouts across network conditions.
- Concurrency control: `package:pool` for host and port concurrency.
- External tools & services: traceroute/dig/curl may be invoked; GeoIP uses ip-api.com by default. These are optional and the tool degrades gracefully if unavailable.

Safety, legal and best practices

- Always obtain authorization before scanning targets you do not own.
- Start with low concurrency and small port lists on unfamiliar networks.
- Use `--export <path>` when scripting to control filenames for automation.
- Be mindful of rate limits for public GeoIP APIs and of any corporate or ISP scanning policies.

Production readiness notes

LunarisEye is a mature and feature-rich demo built on `lunaris_engine`. It is well-suited for authorized research and internal testing. Before broad public release or automated scanning at scale, consider:

- Adding CI with automated tests and integration smoke runs.
- Harden safe defaults (do not scan 1..65535 by default; require an explicit `--all-ports`).
- Add `--no-export` opt-out and a single-line export-path output for CI integration.
- Add sanitization and stricter error handling for external dependencies (traceroute, dig, ip-api).

Installation & quick start

1. Enter the `lunariseye` folder and get dependencies:

```bash
cd lunariseye
dart pub get
```

2. Run a quick web check (example):

```bash
dart run bin/lunariseye.dart web check https://example.com
```

3. Run a phone check (example):

```bash
dart run bin/lunariseye.dart phone check 192.168.1.42
```

Contributing

- LunarisEye showcases `lunaris_engine` and welcomes code and doc contributions that improve safety, testing, and reliability.

License

- See the repository `LICENSE` file for license terms.

Contact & support

- For issues, open PRs or Issues in the repository. Include sample exports and steps to reproduce any bug.

