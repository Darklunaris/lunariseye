WARNING — Legal responsibility and proper use

This tool is built exclusively using the lunaris_engine library.

Using this tool incorrectly is dangerous and may be illegal. We are not responsible for misuse.
You will be convicted before the judges and the law. You are the one who will bear the consequences of your actions if they are bad and twisted.

Overview

This document describes every command available in the `lunariseye` network scanner included in this repository. It explains syntax, flags, outputs, default behaviors (including automatic JSON export), and examples. Read and understand all sections before running scans. Always obtain authorization before scanning systems you do not own.

Quick facts

- Default auto-export: many commands automatically write a timestamped JSON export file to the current directory unless `--export <path>` is provided.
- Short alias: `c` maps to `<topic> check <target>`. Example: `c web https://example.com` → `web check https://example.com`.
- Interactive mode: run the binary with no arguments to enter an interactive menu (profiles, picker, export, saved results).

Commands reference

1) scan

Usage
  dart run bin/lunariseye.dart scan --cidr <cidr> [--ports <list>|--all-ports] [--concurrency N] [--json] [--jsonl] [--export <path>] [--ordering <linkstate|heuristic>] [--allow-external]

What it does
  Performs a full network scan across the CIDR you supply. For each host it probes the requested ports and performs lightweight banner grabs. When `--jsonl` is used plus an output path, per-host JSON lines are streamed to the file to avoid high memory usage.

Important flags
  --cidr <cidr>       : target CIDR (required)
  --ports <list>      : comma-separated ports (e.g. 22,80,443). If omitted the default behavior is to scan a large set (project default may vary; check the README header).
  --all-ports         : scan ports 1..65535 (very heavy)
  --concurrency N     : number of host-level concurrent workers
  --json              : print aggregated JSON to stdout
  --jsonl             : stream per-host JSON lines to the output file (use with --export)
  --export <path>     : write aggregate JSON or JSONL to this path; if omitted a timestamped file is created by default
  --ordering <...>    : choose prioritization algorithm (linkstate or heuristic)
  --allow-external    : explicitly mark that you allow scanning non-private IPs (the tool will warn if external targets are included)

Output
  - When not streaming, the CLI writes a single pretty-printed JSON aggregate and also prints it to stdout unless `--json` is used to restrict formatting.
  - When `--jsonl` + `--export` are used, each host result is written as one JSON object per line and at the end a summary JSON line is appended.

Notes
  - Scanning public IPs may be illegal without authorization. The CLI will warn when non-private targets are present; proceed only if authorized.


2) analyze

Usage
  dart run bin/lunariseye.dart analyze <url> [--json] [--scan-ports] [--ports <list>] [--export <path>]

What it does
  Fetches the URL, reads response headers and body, extracts title and basic metrics (response time, body size), checks header security (HSTS, CSP, X-Frame-Options), and optionally runs a quick port scan of the resolved IP.

Important outputs
  - headerSecurity: map containing HSTS/CSP/X-Frame-Options presence and notes
  - portScan (optional): result of a small port scan performed when `--scan-ports` is provided

Default export
  - A timestamped JSON file is created by default (unless `--export` is provided)


3) web check

Usage
  dart run bin/lunariseye.dart web check <url> [--json] [--scan-ports] [--export <path>]
  Alias: c web <url>

What it does
  A higher-level web auditing command that performs:
    - HTTP fetch (body + headers)
    - Title and resource extraction (detect mixed content)
    - TLS certificate inspection (if HTTPS)
    - GeoIP lookup for the resolved IP
    - traceroute (system traceroute) to the host
    - fingerprinting via response headers
    - WAF/CDN detection heuristics
    - Optional quick port scan when `--scan-ports` is provided

Important fields in output JSON
  - url, status, title, responseTimeMs, bodyBytes
  - resourceCount, externalResources, mixedContentCount
  - headerSecurity: HSTS, CSP, X-Frame-Options summary
  - tls: certificate subject/issuer/validity and fingerprint
  - geoip: result from ip-api.com (country, region, city, isp)
  - traceroute: raw traceroute lines (may be empty if traceroute not available)
  - fingerprint: name/version/confidence
  - waf_cdns: detected providers like Cloudflare, Vercel, Fastly

Notes
  - This command auto-exports JSON to a timestamped file by default.
  - The tool will warn when the resolved IP is external; you must have authorization to scan. The web check is primarily a passive probe but does perform active TLS and optional port probes.


4) port check

Usage
  dart run bin/lunariseye.dart port check <host> [--ports 80,443] [--json] [--export <path>]

What it does
  Performs a port scan (banner grabs) against a single host and reports per-port banner/protocol/service and severity. Default ports: 80,443,22,8080 if not supplied.

Output JSON structure
  { "host": "...", "ports": { "80": {"banner":..., "protocol":..., "service":..., "severity":{...}}, ... } }

Default export
  - A timestamped JSON file is created by default unless `--export` is provided.


5) cert check

Usage
  dart run bin/lunariseye.dart cert check <host> [--port 443] [--json] [--export <path>]

What it does
  Connects with TLS to the target host:port and extracts peer certificate fields:
    - subject, issuer, start, end, SHA1 fingerprint

Notes
  - The tool accepts invalid certificates (onBadCertificate) to extract data.
  - Default export is created automatically unless overridden.


6) dns check

Usage
  dart run bin/lunariseye.dart dns check <host> [--json] [--export <path>]

What it does
  Uses system `dig` to obtain CNAME and A records, then performs a quick HTTP probe of a CNAME target (if present) to look for simple takeover hints (404/no-service responses).

Output
  { "host": "...", "cname": <string|null>, "a": [<ip1>,...], "takeoverHints": [ ... ] }

Default export
  - A timestamped JSON file is created by default unless `--export` is provided.


7) phone check (new)

Usage
  dart run bin/lunariseye.dart phone check <host> [--ports 22,80,443,...] [--json] [--export <path>]

What it does
  A convenience/composite command that runs the checks most useful for assessing a phone or mobile device reachable on the network. By default it scans a sensible set of ports often present on phones or phone-related services and reports detailed, per-port information and an aggregated severity summary.

Default ports scanned (unless overridden):
  22    - SSH
  23    - Telnet (critical if open)
  80    - HTTP
  443   - HTTPS
  5555  - Android ADB (dangerous if exposed)
  5228  - Google-related Android push services
  8000  - common dev/web port
  8080  - alternative HTTP

Collected information
  - Per-port: banner, protocol, service, severity (level, score, note)
  - TLS certificate summary for 443 (if open)
  - Quick HTTP headers when HTTP(S) ports are open
  - GeoIP (ip-api.com) and traceroute
  - Fingerprint & WAF/CDN heuristics
  - severity_summary: counts per level and "highest" (score, level, port)

Default export
  - A timestamped JSON file is saved by default unless `--export` is provided.

Warnings
  - Ports like 5555 (ADB) and 23 (Telnet) are high risk if exposed; take appropriate action if these appear open on devices you control.


8) resolve

Usage
  dart run bin/lunariseye.dart resolve <hostname>

What it does
  Resolves DNS to IP addresses and prints them.


9) Interactive mode

Usage
  dart run bin/lunariseye.dart

What it does
  Launches the interactive menu where you can:
    - list/create/run profiles
    - run saved profiles
    - view and export last results
    - open the interactive command picker (option 7)

Notes
  - Profiles are stored under `~/.lunariseye/config.json` by default.
  - The interactive picker requires a terminal supporting raw-mode input (arrow keys).


10) Short alias `c`

Usage
  c <topic> <target> [...flags]

What it does
  Shorthand: transforms `c web https://example.com` into `web check https://example.com` and runs it.


Output formats and structure

- JSON: pretty-printed aggregate JSON for `analyze`, `web`, `port`, `cert`, `dns`, `phone`, and `scan` (aggregate). Keys and nested structures use primitives, arrays, and plain maps so they are JSON-encodable.
- JSONL: each host is written as one line JSON; final summary appended as a JSON line.
- Files: by default timestamped files are created with prefixes like `lunariseye_webcheck_YYYY-MM-DDTHHMMSSsss.json`, `lunariseye_phonecheck_...`, `lunariseye_dnscheck_...`.

Examples

- Web check with auto-export:
  dart run bin/lunariseye.dart web check https://example.com
  (creates lunariseye_webcheck_<timestamp>.json)

- Port check of an IP with explicit export:
  dart run bin/lunariseye.dart port check 192.168.1.10 --ports 22,80,443 --export myports.json

- Full scan (stream to JSONL):
  dart run bin/lunariseye.dart scan --cidr 192.168.1.0/24 --ports 80,443 --jsonl --export results.jsonl

Good practices and troubleshooting

- Start small: use a small port list and low concurrency against unknown devices.
- Use `--export <path>` when automating to control filenames.
- If traceroute is unavailable on your system, the traceroute field will be empty.
- If JSON serialization errors occur, open the export file and inspect any non-standard objects; report back and a sanitization helper can be added.

Final reminder

This tool performs active network probes. You are responsible for ensuring you have authorization to scan any target. Misuse can be illegal and harmful. The project authors and maintainers assume no responsibility for misuse — you bear the legal consequences.

