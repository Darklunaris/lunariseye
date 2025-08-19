// # Web audit
// dart run bin/lunariseye.dart web check https://darklunaris.vercel.app

// # Mobile/device audit
// dart run bin/lunariseye.dart phone check 192.168.1.42

// #Resolve (get IP)
// dart run bin/lunariseye.dart resolve darklunaris.vercel.app

// #Analyze (HTTP headers, metrics)
// dart run bin/lunariseye.dart analyze https://darklunaris.vercel.app --export lunariseye_analyze_darklunaris.json --allow-external

// #Web check (full web audit: TLS, geoip, traceroute, fingerprint, WAF/CDN)
// dart run bin/lunariseye.dart web check https://darklunaris.vercel.app --export lunariseye_webcheck_darklunaris.json --allow-external

// #Port check (banner grabs; default ports if omitted)
// dart run bin/lunariseye.dart port check darklunaris.vercel.app --ports 80,443 --export lunariseye_portcheck_darklunaris.json --allow-external

// #Cert check (TLS certificate)
// dart run bin/lunariseye.dart port check darklunaris.vercel.app --ports 80,443 --export lunariseye_portcheck_darklunaris.json --allow-external

// #DNS check (dig, CNAME, takeover hints)
// dart run bin/lunariseye.dart dns check darklunaris.vercel.app --export lunariseye_dns_darklunaris.json --allow-external

// #Phone check (composite mobile-device-focused scan)
// dart run bin/lunariseye.dart phone check darklunaris.vercel.app --export lunariseye_phone_darklunaris.json --allow-external

// #
//  dart run bin/lunariseye.dart scan --cidr 192.168.1.0/30 --ports 22,80,443 --json; echo '---FILES---'; ls -t lunariseye_scan_*.json 2>/dev/null | head -n1; echo '---CONTENT---'; FILE=$(ls -t lunariseye_scan_*.json 2>/dev/null | head -n1); if [ -n \"$FILE\" ]; then sed -n '1,240p' \"$FILE\"; fi"