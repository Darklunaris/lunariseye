import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:pool/pool.dart';
import 'package:lunaris_engine/networkAdv/banner.dart' as banner_alg;
import 'package:lunaris_engine/networkAdv/cidr.dart' as cidr_alg;
import 'package:lunaris_engine/networkAdv/ip_utils.dart' as ip_utils;
import 'package:lunaris_engine/networkAdv/network_helpers.dart' as net_helpers;
import 'package:lunaris_engine/networkAdv/prioritize.dart' as prio_alg;
import 'package:lunaris_engine/networkAdv/timeout.dart' as timeout_alg;
import 'package:lunaris_engine/networkAdv/tls.dart' as tls_alg;
import 'package:lunaris_engine/networkAdv/http_probe.dart' as http_probe;
import 'package:lunaris_engine/networkAdv/reporting.dart' as reporting;
import 'package:lunaris_engine/networkAdv/socket_probe.dart' as socket_probe;

String _wellKnownPortService(int port) => banner_alg.wellKnownPortService(port);

Map<String, dynamic> _serviceSeverity(String service, int port) =>
    banner_alg.serviceSeverity(service, port);

// This scanner uses lunaris_engine's link-state routing implementation to
// compute a more meaningful prioritization for probing hosts. We synthesize
// a small topology with heuristic link costs (same /24 -> low cost, same
// /16 -> medium, else higher) and run the link-state routing algorithm to
// compute route costs from the source; hosts are then ordered by cost.

// Delegate CIDR expansion to the algorithms implementation. Keep top-level
// functions so public API used by tests and the CLI remains the same.
Iterable<String> expandCidrLazy(String cidr) sync* {
  yield* cidr_alg.expandCidrLazy(cidr);
}

List<String> expandCidr(String cidr) => cidr_alg.expandCidr(cidr);

bool isPrivateIp(String ip) => ip_utils.isPrivateIp(ip);

Duration _adaptiveTimeoutForHost(String host, Duration base) =>
    timeout_alg.adaptiveTimeoutForHost(host, base);

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
          // Use the separated socket probe to perform a small banner grab.
          final banner = await socket_probe.grabBanner(
            host,
            p,
            timeout: measuredTimeout,
            bannerTimeout: bannerTimeout,
          );
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
          // socket_probe handles socket lifecycle
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
  return await tls_alg.inspectTlsCertificate(host, port, timeout: timeout);
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

        // Use the separated http probe to gather headers and resolved IP.
        Map<String, String>? headersMap;
        String? cnameTarget;
        try {
          final probe = await http_probe.httpHeadProbe(
            h,
            timeout: Duration(seconds: 5),
          );
          headersMap = probe['headers'] as Map<String, String>?;
          final ip = probe['ip'] as String?;
          if (ip != null) {
            final geo = await geoIpLookup(ip);
            if (geo != null) hostObj['geoip'] = geo;
          }
          try {
            final trace = await traceroute(h);
            if (trace.isNotEmpty) hostObj['traceroute'] = trace;
          } catch (_) {}
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
      'summary': reporting.severitySummary(results),
    };
    jsonlSink.writeln(JsonEncoder().convert(summary));
    await jsonlSink.flush();
  }

  return results;
}

/// Delegate banner protocol identification to algorithm module.
String? identifyProtocolFromBanner(String banner) {
  final r = banner_alg.identifyProtocolFromBanner(banner);
  return (r.isEmpty) ? null : r;
}

Future<List<String>> traceroute(String host, {int maxHops = 30}) async =>
    await net_helpers.traceroute(host, maxHops: maxHops);

Future<Map<String, dynamic>?> geoIpLookup(
  String ip, {
  Duration timeout = const Duration(seconds: 5),
}) async => await net_helpers.geoIpLookup(ip, timeout: timeout);

Map<String, dynamic> fingerprintService({
  Map<String, String>? headers,
  String? banner,
}) => banner_alg.fingerprintService(headers: headers, banner: banner);

List<String> detectWafCdns(Map<String, String>? headers, String? cname) =>
    banner_alg.detectWafCdns(headers, cname);

// Using package:pool's Pool for concurrency control.

/// Given a list of hosts, produce an ordering based on a shortest-path
/// traversal starting from the first host. We convert IPs to numeric form
/// and build a weighted graph where edge weight is absolute difference.
List<String> prioritizeHosts(
  List<String> hosts, {
  String ordering = 'linkstate',
}) => prio_alg.prioritizeHosts(hosts, ordering: ordering);
