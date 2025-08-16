lunariseye SCAN_INSTRUCTIONS

This tool is built exclusively using the lunaris_engine library.

Overview

This file documents the short "check" commands and default auto-export behavior of the lunariseye example scanner.

Short alias

- c <topic> <target> ...
  - Example: c web https://example.com -> runs the same work as: lunariseye web check https://example.com

Commands (single-shot)

- analyze <url> [--json] [--export <path>] [--scan-ports]
  - Performs an HTTP fetch, header security checks (HSTS, CSP, X-Frame-Options), and optional port scan.
  - Always writes a JSON export file by default to a timestamped path (unless --export is provided).

- web check <url> [--json] [--scan-ports] [--export <path>]
  - Performs a higher-level web check: TLS cert inspection, GeoIP, traceroute, fingerprinting (from headers), mixed-content checks, and optional quick port scan.
  - Always writes a JSON export file by default.

- port check <host> [--ports 80,443] [--json] [--export <path>]
  - Performs a port scan against the provided host. Default ports: 80,443,22,8080.
  - Always writes a JSON export file by default.

- cert check <host> [--port 443] [--json] [--export <path>]
  - Fetches TLS certificate details (issuer, validity, fingerprints).
  - Always writes a JSON export file by default.

- dns check <host> [--json] [--export <path>]
  - Checks CNAME/A records and does a basic takeover probe of any CNAME target.
  - Always writes a JSON export file by default.

- scan --cidr <cidr> [--ports <list>|--all-ports] [--concurrency N] [--jsonl|--export <path>]
  - Full network scan over a CIDR. For safety this now warns about external targets; the tool no longer refuses external targets by default but you must ensure you have permission to scan.
  - By default results are exported to a timestamped JSON file unless --export is provided.

Notes & Safety

- The tool will warn when targets include non-private addresses. You are responsible for authorization.
- Exports are saved in the current working directory. Filenames look like lunariseye_<prefix>_YYYY-MM-DDTHHMMSSsss.json.

Examples

- c web https://darklunaris.vercel.app
- lunariseye analyze https://example.com --scan-ports
- lunariseye dns check example.com --export mydns.json

