import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:pool/pool.dart';
import 'package:lunaris_engine/RoutingNET/link_state_routing.dart';

String _wellKnownPortService(int port) {
  switch (port) {
    case 21:
      return 'ftp';
    case 22:
      return 'ssh';
    case 23:
      return 'telnet';
    case 25:
      return 'smtp';
    case 53:
      return 'dns';
    case 80:
      return 'http';
    case 110:
      return 'pop3';
    case 143:
      return 'imap';
    case 443:
      return 'https';
    case 3306:
      return 'mysql';
    case 3389:
      return 'rdp';
    case 8080:
      return 'http-alt';
    default:
      return 'unknown';
  }
}

/// Map a service or port to a severity level and short description.
Map<String, dynamic> _serviceSeverity(String service, int port) {
  final s = service.toLowerCase();
  // severity: critical, high, medium, low, info
  if (s.contains('telnet') || port == 23) {
    return {
      'level': 'critical',
      'score': 9,
      'note': 'Cleartext remote shell (Telnet)',
    };
  }
  if (s.contains('rdp') || port == 3389) {
    return {'level': 'high', 'score': 8, 'note': 'Remote Desktop exposed'};
  }
  if (s.contains('mysql') || port == 3306 || s.contains('mariadb')) {
    return {
      'level': 'high',
      'score': 8,
      'note': 'Database port exposed without authentication checks',
    };
  }
  if (s.contains('ftp') || port == 21) {
    return {
      'level': 'high',
      'score': 7,
      'note': 'FTP may expose credentials (cleartext)',
    };
  }
  if (s.contains('ssh') || port == 22) {
    return {
      'level': 'medium',
      'score': 5,
      'note': 'SSH exposed (use key auth and strong configs)',
    };
  }
  if (s.contains('http') || port == 80 || port == 8080) {
    return {
      'level': 'medium',
      'score': 5,
      'note':
          'HTTP service; check for outdated software and missing security headers',
    };
  }
  if (s.contains('https') || port == 443) {
    return {
      'level': 'medium',
      'score': 5,
      'note': 'HTTPS exposed; check certificate and TLS config',
    };
  }
  if (s.contains('smtp') || port == 25) {
    return {
      'level': 'medium',
      'score': 5,
      'note': 'SMTP service; check for open relays',
    };
  }
  if (s.contains('dns') || port == 53) {
    return {
      'level': 'low',
      'score': 3,
      'note': 'DNS exposed; consider restricting or rate-limiting',
    };
  }
  if (s.contains('imap') || s.contains('pop3') || port == 110 || port == 143) {
    return {'level': 'low', 'score': 3, 'note': 'Legacy mail services exposed'};
  }
  // default: informational
  return {
    'level': 'info',
    'score': 1,
    'note': 'Unclassified service — validate manually',
  };
}

// This scanner uses lunaris_engine's link-state routing implementation to
// compute a more meaningful prioritization for probing hosts. We synthesize
// a small topology with heuristic link costs (same /24 -> low cost, same
// /16 -> medium, else higher) and run the link-state routing algorithm to
// compute route costs from the source; hosts are then ordered by cost.

/// Simple CIDR expansion utility.
/// Lazy CIDR expansion (IPv4 and basic IPv6 support). Use `expandCidrLazy`
/// to iterate addresses without materializing the whole range.
Iterable<String> expandCidrLazy(String cidr) sync* {
  final parts = cidr.split('/');
  if (parts.length != 2) return;
  final base = parts[0];
  final prefix = int.tryParse(parts[1]) ?? 128;

  // IPv4 fast path
  if (base.contains('.') && prefix <= 32) {
    final bytes = base.split('.').map(int.parse).toList();
    if (bytes.length != 4) return;
    final start =
        (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    final mask =
        prefix == 32 ? 0xFFFFFFFF : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
    final network = start & mask;
    final broadcast = network | (~mask & 0xFFFFFFFF);
    // If the prefix is /32 (single address) or /31 (very small), include
    // the network and broadcast addresses as usable hosts for scanning.
    if (prefix >= 31) {
      for (var addr = network; addr <= broadcast; addr++) {
        final b1 = (addr >> 24) & 0xFF;
        final b2 = (addr >> 16) & 0xFF;
        final b3 = (addr >> 8) & 0xFF;
        final b4 = addr & 0xFF;
        yield '$b1.$b2.$b3.$b4';
      }
      return;
    }

    // For common prefixes (/0 - /30) avoid yielding network and broadcast
    // addresses and iterate the host space.
    for (var addr = network + 1; addr < broadcast; addr++) {
      final b1 = (addr >> 24) & 0xFF;
      final b2 = (addr >> 16) & 0xFF;
      final b3 = (addr >> 8) & 0xFF;
      final b4 = addr & 0xFF;
      yield '$b1.$b2.$b3.$b4';
    }
    return;
  }

  // Basic IPv6 support: parse via InternetAddress and iterate numerically.
  // Note: iterating very large IPv6 spaces is impractical; caller should
  // avoid broad prefixes on IPv6.
  try {
    final ia = InternetAddress(base);
    if (ia.type == InternetAddressType.IPv6) {
      // Convert to BigInt
      final bytes = ia.rawAddress;
      BigInt start = BigInt.zero;
      for (final b in bytes) {
        start = (start << 8) | BigInt.from(b & 0xFF);
      }
      final totalBits = 128;
      final hostBits = totalBits - prefix;
      // clamp count to a reasonable BigInt when hostBits is large
      final count =
          hostBits >= 64 ? (BigInt.one << 64) : (BigInt.one << hostBits);
      final network = (start >> hostBits) << hostBits;

      // For very small host spaces (/127 and /128) include the full range
      // (network .. network+count-1). For larger spaces, skip network and
      // broadcast-like endpoints by starting at offset=1 and ending at count-1.
      final includeEndpoints = hostBits <= 1;
      final startOffset = includeEndpoints ? BigInt.zero : BigInt.one;
      final endOffset =
          includeEndpoints ? (count - BigInt.one) : (count - BigInt.one);
      for (
        BigInt offset = startOffset;
        offset <= endOffset;
        offset += BigInt.one
      ) {
        final addr = network + offset;
        // convert BigInt back to 16 bytes
        var b = List<int>.filled(16, 0);
        var v = addr;
        for (var i = 15; i >= 0; i--) {
          b[i] = (v & BigInt.from(0xFF)).toInt();
          v = v >> 8;
        }
        yield InternetAddress.fromRawAddress(Uint8List.fromList(b)).address;
      }
    }
  } catch (_) {
    return;
  }
}

/// Backwards-compatible expansion that materializes the list.
List<String> expandCidr(String cidr) => expandCidrLazy(cidr).toList();

/// Returns true if [ip] is a localhost or RFC1918 private address (IPv4).
bool isPrivateIp(String ip) {
  try {
    final ia = InternetAddress(ip);
    if (ia.type == InternetAddressType.IPv4) {
      final parts = ip.split('.').map(int.parse).toList();
      if (parts.length != 4) return false;
      final a = parts[0];
      final b = parts[1];
      // 127.0.0.1/8 localhost
      if (a == 127) return true;
      // 10.0.0.0/8
      if (a == 10) return true;
      // 172.16.0.0/12 (172.16.0.0 - 172.31.255.255)
      if (a == 172 && b >= 16 && b <= 31) return true;
      // 192.168.0.0/16
      if (a == 192 && b == 168) return true;
      return false;
    } else {
      // IPv6: check loopback and Unique Local Addresses (fc00::/7) and link-local fe80::/10
      final addr = ia.rawAddress;
      // loopback ::1
      if (ia.address == '::1') return true;
      // fc00::/7 -> first 7 bits 1111 110
      final firstByte = addr[0];
      if ((firstByte & 0xFE) == 0xFC) return true;
      // fe80::/10: first 10 bits 1111 1110 10 -> first byte 0xFE and second byte high 0x80..0xBF
      if (firstByte == 0xFE) {
        final second = addr[1];
        if ((second & 0xC0) == 0x80) return true;
      }
      return false;
    }
  } catch (_) {
    return false;
  }
}

/// Scans ports for a single host with limited concurrency.
// Simple EWMA RTT estimator per host for adaptive timeouts.
final Map<String, double> _rttEwma = {};
const double _rttAlpha = 0.2; // smoothing factor

Future<List<int>> scanPorts(
  String host,
  List<int> ports, {
  int concurrency = 50,
  Duration timeout = const Duration(milliseconds: 300),
}) async {
  final open = <int>[];
  final sem = Pool(concurrency);
  final futures = <Future>[];

  for (final p in ports) {
    futures.add(
      sem.withResource(() async {
        final measuredTimeout = _adaptiveTimeoutForHost(host, timeout);
        final start = DateTime.now();
        try {
          final s = await Socket.connect(host, p, timeout: measuredTimeout);
          final elapsed =
              DateTime.now().difference(start).inMilliseconds.toDouble();
          _updateRtt(host, elapsed);
          open.add(p);
          s.destroy();
        } catch (_) {
          final elapsed =
              DateTime.now().difference(start).inMilliseconds.toDouble();
          // update RTT with failed attempt as upper bound
          _updateRtt(host, elapsed);
        }
      }),
    );
  }

  await Future.wait(futures);
  open.sort();
  return open;
}

Duration _adaptiveTimeoutForHost(String host, Duration base) {
  final avg = _rttEwma[host];
  if (avg == null || avg.isNaN || avg <= 0) return base;
  // Aim for ~4x RTT but clamp to reasonable bounds
  final ms = (avg * 4).clamp(50, 2000);
  return Duration(milliseconds: ms.toInt());
}

void _updateRtt(String host, double sampleMs) {
  final prev = _rttEwma[host] ?? sampleMs;
  _rttEwma[host] = (1 - _rttAlpha) * prev + _rttAlpha * sampleMs;
}

/// Scan a single host's ports and attempt a small banner grab for each open
/// port. Returns a map port->optional banner (null if none captured).
/// Returns port -> { 'banner': String?, 'protocol': String? }
Future<Map<int, Map<String, dynamic>>> scanHost(
  String host,
  List<int> ports, {
  int portConcurrency = 50,
  Duration timeout = const Duration(milliseconds: 300),
  Duration bannerTimeout = const Duration(milliseconds: 300),
}) async {
  final result = <int, Map<String, dynamic>>{};
  final sem = Pool(portConcurrency);
  final futures = <Future>[];

  for (final p in ports) {
    futures.add(
      sem.withResource(() async {
        final measuredTimeout = _adaptiveTimeoutForHost(host, timeout);
        try {
          final s = await Socket.connect(host, p, timeout: measuredTimeout);
          // try a tiny banner grab
          String? banner;
          try {
            s.write('\r\n');
            final data = await s.first.timeout(bannerTimeout);
            banner = String.fromCharCodes(data).trim();
          } catch (_) {
            banner = null;
          }
          final proto =
              banner != null ? identifyProtocolFromBanner(banner) : null;
          final svc = _wellKnownPortService(p);
          final sev = _serviceSeverity(svc, p);
          result[p] = {
            'banner': banner,
            'protocol': proto,
            'service': svc,
            'severity': sev,
          };
          s.destroy();
        } catch (_) {
          // closed or filtered
        }
      }),
    );
  }

  await Future.wait(futures);
  final orderedPorts = result.keys.toList()..sort();
  final sorted = <int, Map<String, dynamic>>{};
  for (final k in orderedPorts) {
    sorted[k] = result[k]!;
  }
  return sorted;
}

/// Inspect TLS certificate information for a host:port. Returns a small map
/// with subject, issuer, validFrom, validTo, and SANs when available.
Future<Map<String, dynamic>?> inspectTlsCertificate(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  try {
    final socket = await SecureSocket.connect(
      host,
      port,
      onBadCertificate: (_) => true,
      timeout: timeout,
    );
    final cert = socket.peerCertificate;
    socket.destroy();
    if (cert == null) return null;
    return {
      'subject': cert.subject,
      'issuer': cert.issuer,
      'start': cert.startValidity.toIso8601String(),
      'end': cert.endValidity.toIso8601String(),
      'sha1': cert.sha1,
    };
  } catch (_) {
    return null;
  }
}

/// Scan multiple hosts concurrently (host-level concurrency) and scan each
/// host's ports using `scanHost`. Returns a map host->(port->banner).
Future<Map<String, Map<int, Map<String, dynamic>>>> scanNetwork(
  Iterable<String> hosts,
  List<int> ports, {
  int hostConcurrency = 10,
  int portConcurrency = 50,
  Duration timeout = const Duration(milliseconds: 300),
  Duration bannerTimeout = const Duration(milliseconds: 300),
  void Function(String host, Map<int, Map<String, dynamic>> result)?
  onHostResult,
  // If provided, write per-host JSON lines to this sink as results arrive.
  IOSink? jsonlSink,
}) async {
  final results = <String, Map<int, Map<String, dynamic>>>{};
  final hostPool = Pool(hostConcurrency);
  final futures = <Future>[];

  for (final h in hosts) {
    futures.add(
      hostPool.withResource(() async {
        final r = await scanHost(
          h,
          ports,
          portConcurrency: portConcurrency,
          timeout: timeout,
          bannerTimeout: bannerTimeout,
        );
        // Always record results (may be empty) and stream a JSONL line if requested
        results[h] = r;
        // Build per-host JSON object
        final hostObj = <String, dynamic>{
          'host': h,
          'timestamp': DateTime.now().toIso8601String(),
          'open_count': r.length,
        };
        final portsList = <Map<String, dynamic>>[];
        for (final entry in r.entries) {
          final p = entry.key;
          final banner = entry.value['banner'];
          final proto = entry.value['protocol'];
          final service = entry.value['service'] ?? _wellKnownPortService(p);
          final severity = entry.value['severity'];
          portsList.add({
            'port': p,
            'banner': banner,
            'protocol': proto,
            'service': service,
            'severity': severity,
          });
        }
        hostObj['ports'] = portsList;
        // If HTTPS likely present (443 open), try cert inspection
        if (r.keys.contains(443)) {
          try {
            final cert = await inspectTlsCertificate(h, 443);
            if (cert != null) hostObj['tls'] = cert;
          } catch (_) {
            // ignore cert errors
          }
        }

        // Try a quick HTTP HEAD to gather headers for fingerprinting and WAF/CDN detection
        Map<String, String>? headersMap;
        String? cnameTarget;
        try {
          final uri = Uri.parse('https://$h/');
          final reqClient = HttpClient();
          reqClient.connectionTimeout = Duration(seconds: 5);
          final req = await reqClient
              .openUrl('HEAD', uri)
              .timeout(Duration(seconds: 5));
          final resp = await req.close().timeout(Duration(seconds: 5));
          headersMap = <String, String>{};
          resp.headers.forEach((k, v) => headersMap![k] = v.join(', '));
          // attempt DNS CNAME via lookup
          try {
            final addrList = await InternetAddress.lookup(h);
            // use first IP for geo lookup
            if (addrList.isNotEmpty) {
              final ip = addrList.first.address;
              final geo = await geoIpLookup(ip);
              if (geo != null) hostObj['geoip'] = geo;
            }
          } catch (_) {}
          // attempt traceroute (may be slow)
          try {
            final trace = await traceroute(h);
            if (trace.isNotEmpty) hostObj['traceroute'] = trace;
          } catch (_) {}
          reqClient.close(force: true);
        } catch (_) {
          headersMap = null;
        }

        // Fingerprint service and detect WAF/CDN
        final fp = fingerprintService(headers: headersMap, banner: null);
        final waf = detectWafCdns(headersMap, cnameTarget);
        if (fp['name'] != null) hostObj['fingerprint'] = fp;
        if (waf.isNotEmpty) hostObj['waf_cdns'] = waf;
        if (jsonlSink != null) {
          jsonlSink.writeln(JsonEncoder().convert(hostObj));
          await jsonlSink.flush();
        }
        try {
          if (onHostResult != null) onHostResult(h, r);
        } catch (_) {
          // ignore callback errors
        }
      }),
    );
  }

  await Future.wait(futures);
  // If streaming JSONL, produce a final aggregated severity summary line
  if (jsonlSink != null) {
    final summary = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'summary': {},
    };
    final counts = <String, int>{};
    int highestScore = 0;
    String? highestHost;
    int? highestPort;
    for (final hostEntry in results.entries) {
      for (final portEntry in hostEntry.value.entries) {
        final sev = portEntry.value['severity'];
        if (sev is Map && sev['level'] is String) {
          final lvl = sev['level'] as String;
          counts[lvl] = (counts[lvl] ?? 0) + 1;
          final score = (sev['score'] is int) ? sev['score'] as int : 0;
          if (score > highestScore) {
            highestScore = score;
            highestHost = hostEntry.key;
            highestPort = portEntry.key;
          }
        }
      }
    }
    summary['summary'] = {
      'counts': counts,
      'highest':
          highestScore > 0
              ? {
                'score': highestScore,
                'host': highestHost,
                'port': highestPort,
              }
              : null,
    };
    jsonlSink.writeln(JsonEncoder().convert(summary));
    await jsonlSink.flush();
  }

  return results;
}

/// Lightweight banner protocol identification via heuristics/regex.
String? identifyProtocolFromBanner(String banner) {
  final s = banner.trim();
  if (s.startsWith('SSH-')) {
    return 'SSH';
  }
  if (RegExp(r'^HTTP/\d', caseSensitive: false).hasMatch(s) ||
      s.toLowerCase().contains('server:')) {
    return 'HTTP';
  }
  if (RegExp(r'^220', caseSensitive: false).hasMatch(s) &&
      s.toUpperCase().contains('FTP')) {
    return 'FTP';
  }
  if (RegExp(r'^220', caseSensitive: false).hasMatch(s) &&
      s.toUpperCase().contains('SMTP')) {
    return 'SMTP';
  }
  if (s.startsWith('220')) {
    return 'SMTP/FTP';
  }
  if (s.startsWith('220 ')) {
    return 'Service';
  }
  if (s.toUpperCase().contains('TLS') || s.toUpperCase().contains('SSL')) {
    return 'TLS/SSL';
  }
  // fallback: attempt to detect common HTTP request lines
  if (RegExp(r'GET |POST |HEAD ', caseSensitive: false).hasMatch(s)) {
    return 'HTTP-REQ';
  }
  // default to null (unknown)
  return null;
}

/// Run system traceroute (Linux) to trace path to [host]. Returns raw lines.
/// Falls back to empty list if traceroute isn't available or fails.
Future<List<String>> traceroute(String host, {int maxHops = 30}) async {
  try {
    final proc = await Process.start('traceroute', ['-m', '$maxHops', host]);
    final out = <String>[];
    await for (final line in proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      out.add(line);
    }
    await proc.exitCode;
    return out;
  } catch (_) {
    return [];
  }
}

/// GeoIP lookup using ip-api.com (free). Returns null on error.
Future<Map<String, dynamic>?> geoIpLookup(
  String ip, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  try {
    final uri = Uri.parse(
      'http://ip-api.com/json/$ip?fields=status,country,regionName,city,isp,org,as,query',
    );
    final client = HttpClient();
    client.connectionTimeout = timeout;
    final req = await client.getUrl(uri).timeout(timeout);
    final resp = await req.close().timeout(timeout);
    final body = await resp.transform(utf8.decoder).join();
    client.close();
    final map = jsonDecode(body) as Map<String, dynamic>;
    if (map['status'] == 'success') {
      return map;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// Fingerprint a service from HTTP headers and a banner string.
Map<String, dynamic> fingerprintService({
  Map<String, String>? headers,
  String? banner,
}) {
  final result = <String, dynamic>{
    'name': null,
    'version': null,
    'confidence': 0,
  };
  try {
    final server =
        headers != null && headers.containsKey('server')
            ? headers['server']!.toLowerCase()
            : null;
    if (server != null) {
      if (server.contains('apache')) {
        result['name'] = 'Apache';
        final m = RegExp(r'apache/?(?:\s*)([\d.]+)?').firstMatch(server);
        if (m != null) result['version'] = m.group(1);
        result['confidence'] = 90;
        return result;
      }
      if (server.contains('nginx')) {
        result['name'] = 'nginx';
        final m = RegExp(r'nginx/?(?:\s*)([\d.]+)?').firstMatch(server);
        if (m != null) result['version'] = m.group(1);
        result['confidence'] = 90;
        return result;
      }
      if (server.contains('cloudflare')) {
        result['name'] = 'cloudflare';
        result['confidence'] = 80;
        return result;
      }
      if (server.contains('vercel') || server.contains('now')) {
        result['name'] = 'Vercel';
        result['confidence'] = 85;
        return result;
      }
      if (server.contains('gunicorn') || server.contains('uwsgi')) {
        result['name'] = 'python-wsgi';
        result['confidence'] = 70;
        return result;
      }
      if (server.contains('node') || server.contains('express')) {
        result['name'] = 'node.js';
        result['confidence'] = 70;
        return result;
      }
    }

    // fallback: look at banner
    if (banner != null) {
      final b = banner.toLowerCase();
      if (b.contains('nginx')) {
        result['name'] = 'nginx';
        result['confidence'] = 60;
        return result;
      }
      if (b.contains('apache')) {
        result['name'] = 'Apache';
        result['confidence'] = 60;
        return result;
      }
      if (b.contains('http') && b.contains('node')) {
        result['name'] = 'node.js';
        result['confidence'] = 50;
        return result;
      }
    }
  } catch (_) {
    // ignore
  }
  return result;
}

/// Detect WAFs/CDNs from headers and CNAME target; returns list of providers.
List<String> detectWafCdns(Map<String, String>? headers, String? cname) {
  final found = <String>{};
  try {
    if (headers != null) {
      final lower = <String, String>{};
      for (final e in headers.entries) {
        lower[e.key.toLowerCase()] = e.value.toLowerCase();
      }
      if (lower.containsKey('server') && lower['server']!.contains('vercel')) {
        found.add('Vercel');
      }
      if (lower.containsKey('x-vercel-id')) found.add('Vercel');
      if (lower.containsKey('server') &&
          lower['server']!.contains('cloudflare')) {
        found.add('Cloudflare');
      }
      if (lower.containsKey('cf-ray') || lower.containsKey('cf-cache-status')) {
        found.add('Cloudflare');
      }
      if (lower.containsKey('server') && lower['server']!.contains('akamai')) {
        found.add('Akamai');
      }
      if (lower.containsKey('via') && lower['via']!.contains('varnish')) {
        found.add('Varnish/CDN');
      }
      if (lower.containsKey('server') && lower['server']!.contains('fastly')) {
        found.add('Fastly');
      }
      if (lower.containsKey('x-amz-cf-id')) found.add('CloudFront');
      if (lower.containsKey('x-powered-by') &&
          lower['x-powered-by']!.contains('next')) {
        found.add('Next.js');
      }
    }
    if (cname != null && cname.isNotEmpty) {
      final cn = cname.toLowerCase();
      if (cn.endsWith('.vercel.app') || cn.contains('.now.sh')) {
        found.add('Vercel');
      }
      if (cn.endsWith('.cdn.cloudflare.net') || cn.contains('cloudflare')) {
        found.add('Cloudflare');
      }
      if (cn.contains('akamai') || cn.endsWith('.akamaized.net')) {
        found.add('Akamai');
      }
      if (cn.endsWith('.netlify.app') || cn.contains('netlify')) {
        found.add('Netlify');
      }
      if (cn.endsWith('.cloudfront.net')) found.add('CloudFront');
    }
  } catch (_) {}
  return found.toList();
}

// Using package:pool's Pool for concurrency control.

/// Given a list of hosts, produce an ordering based on a shortest-path
/// traversal starting from the first host. We convert IPs to numeric form
/// and build a weighted graph where edge weight is absolute difference.
List<String> prioritizeHosts(
  List<String> hosts, {
  String ordering = 'linkstate',
}) {
  if (hosts.isEmpty) return hosts;
  // Heuristic link cost: same /24 -> 1, same /16 -> 5, else 20
  num linkCost(String a, String b) {
    final A = a.split('.');
    final B = b.split('.');
    if (A.length != 4 || B.length != 4) return 1000;
    if (A[0] == B[0] && A[1] == B[1] && A[2] == B[2]) return 1; // same /24
    if (A[0] == B[0] && A[1] == B[1]) return 5; // same /16
    return 20; // different
  }

  final Map<String, Map<String, num>> network = {};
  for (final a in hosts) {
    network[a] = {};
    for (final b in hosts) {
      if (a == b) continue;
      network[a]![b] = linkCost(a, b);
    }
  }

  try {
    if (ordering == 'heuristic') {
      // Simple heuristic ordering: sort by numeric value to cluster addresses
      final ordered =
          hosts.toList()..sort((x, y) {
            final xa = x.split('.').map(int.parse).toList();
            final ya = y.split('.').map(int.parse).toList();
            for (var i = 0; i < 4; i++) {
              final c = xa[i].compareTo(ya[i]);
              if (c != 0) return c;
            }
            return 0;
          });
      return ordered;
    }

    // default: link-state prioritization
    final routingTable = computeLinkStateRoutes<String>(network, hosts.first);
    final ordered =
        hosts.toList()..sort(
          (x, y) => (routingTable.getRoute(x)?.cost ?? 1e9).compareTo(
            routingTable.getRoute(y)?.cost ?? 1e9,
          ),
        );
    return ordered;
  } catch (_) {
    // fallback to original order
    return hosts;
  }
}
