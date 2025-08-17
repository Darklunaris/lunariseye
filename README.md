# LunarisEye — The Ultimate Network & Web Reconnaissance CLI

![LunarisEye Logo](https://k.top4top.io/p_3514x9kqz1.png)

> **WARNING — Legal Responsibility**
> LunarisEye is **not a toy**. Misuse may be illegal. It is strictly for **authorized testing, research, and internal security auditing**. Authors, maintainers, and contributors are **not liable for misuse**. Always obtain explicit permission before scanning targets.

---

## ⚡ Overview

**LunarisEye** is the **next-generation, multi-modal network and web audit CLI**, built **entirely on `lunaris_engine`**. It combines **state-of-the-art scanning, intelligent prioritization, and advanced heuristics** into a **single, powerful toolkit**.

Whether you are auditing a corporate network, performing penetration tests, or exploring device security, LunarisEye gives you **deep visibility and actionable insights**, all in a **fast, reliable, and scriptable CLI**.

---

## 🚀 Why LunarisEye?

* **Powered by Lunaris Engine:** Full algorithmic control, adaptive scheduling, and intelligent host prioritization.
* **Multi-layered Scanning:** Ports, banners, HTTP, TLS, DNS, traceroute, GeoIP, and device fingerprinting.
* **One-shot Audits:** `web check`, `port check`, `phone check`, `dns check` — all-in-one probes with JSON summaries.
* **Streaming & Memory-efficient:** Handle massive networks with `--jsonl` streaming output.
* **Safety-first UX:** Clear legal notices, external IP warnings, and controlled concurrency.
* **CLI Shortcuts:** Type less, do more with alias `c` (`c web https://example.com`).

---

## 🌐 Key Features

### Advanced Port Scanning

* Adaptive EWMA RTT timeouts.
* Host & port concurrency pools (`package:pool`).
* Service detection: SSH, HTTP, FTP, SMTP, TLS, and more.
* Severity scoring & actionable notes per port.

### Web & HTTP Audits

* Full HTTP fetch (headers + body), resource enumeration, mixed-content detection.
* Header security checks: HSTS, CSP, X-Frame-Options.
* TLS certificate inspection: issuer, validity, fingerprint, chain verification.

### Network Intelligence

* Traceroute & routing insights.
* GeoIP lookups with fail-safe defaults.
* WAF/CDN detection heuristics (Cloudflare, Akamai, Netlify, etc.).
* Fingerprinting from headers and banners.

### DNS & Takeover Detection

* System `dig` integration for CNAME/A lookup.
* Best-effort checks for common takeover indicators.

### Automation & CLI UX

* Interactive menu with **persistent profiles**.
* JSON & JSONL outputs for pipelines and CI/CD.
* Single-shot commands for automated scripting.

---

## 🛠 Commands Overview

```bash
scan --cidr <cidr> [--ports <list>|--all-ports] [--concurrency N] [--jsonl] [--export <path>]
analyze <url> [--scan-ports] [--ports <list>] [--export <path>]
web check <url> [--scan-ports] [--export <path>]
port check <host> [--ports <list>] [--export <path>]
cert check <host> [--port 443] [--export <path>]
dns check <host> [--export <path>]
phone check <host> [--ports <list>] [--export <path>]
resolve <hostname>
```

---

## ⚙ Design & Internals

* **Host Prioritization:** Uses `lunaris_engine`’s Dijkstra-based routing for meaningful probe ordering.
* **CIDR & Large Networks:** Lazy expansion avoids memory spikes.
* **Adaptive Timeouts:** Per-host EWMA RTT tuning ensures speed without dropping packets.
* **Safe Concurrency:** Pools manage host & port scanning simultaneously.
* **Graceful Degradation:** External tools (traceroute, dig, curl) optional; falls back safely if unavailable.

---

## 🛡 Safety & Best Practices

* Always **obtain authorization** for scanning non-owned networks.
* Use low concurrency and limited ports on unfamiliar networks.
* Respect GeoIP API limits and ISP/corporate policies.
* Use `--export <path>` for consistent, machine-readable outputs.

---

## 🚀 Quick Start

```bash
cd lunariseye
dart pub get

# Web audit
dart run bin/lunariseye.dart web check https://darklunaris.vercel.app

# Mobile/device audit
dart run bin/lunariseye.dart phone check 192.168.1.42

#Resolve (get IP)
dart run bin/lunariseye.dart resolve darklunaris.vercel.app

#Analyze (HTTP headers, metrics)
dart run bin/lunariseye.dart analyze https://darklunaris.vercel.app --export lunariseye_analyze_darklunaris.json --allow-external

#Web check (full web audit: TLS, geoip, traceroute, fingerprint, WAF/CDN)
dart run bin/lunariseye.dart web check https://darklunaris.vercel.app --export lunariseye_webcheck_darklunaris.json --allow-external

#Port check (banner grabs; default ports if omitted)
dart run bin/lunariseye.dart port check darklunaris.vercel.app --ports 80,443 --export lunariseye_portcheck_darklunaris.json --allow-external

#Cert check (TLS certificate)
dart run bin/lunariseye.dart port check darklunaris.vercel.app --ports 80,443 --export lunariseye_portcheck_darklunaris.json --allow-external

#DNS check (dig, CNAME, takeover hints)
dart run bin/lunariseye.dart dns check darklunaris.vercel.app --export lunariseye_dns_darklunaris.json --allow-external

#Phone check (composite mobile-device-focused scan)
dart run bin/lunariseye.dart phone check darklunaris.vercel.app --export lunariseye_phone_darklunaris.json --allow-external
```

---

## 🏗 Contributing

**LunarisEye** is a **demonstration of `lunaris_engine`** at its best. Contributions that **improve safety, reliability, performance, or coverage** are highly encouraged.

---

## 📄 License & Support

* See the `LICENSE` file.
* Report issues, submit PRs, or share sample exports via the repository.
