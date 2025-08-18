import 'dart:io';
import 'dart:convert';
import 'package:lunariseye/scanner.dart' as sc;
import 'package:lunariseye/config.dart';
import 'package:dart_console/dart_console.dart';

String _defaultExportPath(String prefix) {
  final t = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '')
      .replaceAll('.', '');
  return 'lunariseye_${prefix}_$t.json';
}

void printHelp() {
  print('lunariseye scan --cidr <cidr> --ports <ports> [--concurrency N]');
  print('Example: lunariseye scan --cidr 192.168.1.0/30 --ports 22,80,443');
  print(
    'By default (no --ports) the tool will scan ports 1-1024 for a comprehensive check.',
  );
  print(
    'WARNING: You are responsible for legal compliance when scanning networks.',
  );
  print(
    'Do not scan systems you do not own or have explicit authorization to test.',
  );
}

void printLogo() {
  // small ASCII logo emphasizing lunaris_engine
  stdout.writeln(r'''
 _                _            _
| |    _   _  ___| | ___   ___| |_
| |   | | | |/ __| |/ _ \ / __| __|
| |___| |_| | (__| | (_) | (__| |_
|______\__,_|\___|_|\___/ \___|\__|

lunaris_engine - lunariseye
''');
}

/// Recursively convert values into JSON-encodable structures.
/// - Map keys are converted to strings.
/// - DateTime -> ISO8601 string.
/// - InternetAddress/Uri -> string.
dynamic _jsonEncodable(dynamic v) {
  if (v == null) return null;
  if (v is String || v is num || v is bool) return v;
  if (v is DateTime) return v.toIso8601String();
  try {
    // InternetAddress and Uri both have useful string forms
    if (v is Uri) return v.toString();
    if (v.runtimeType.toString().contains('InternetAddress')) {
      // avoid importing dart:io types explicitly here
      try {
        return v.address; // InternetAddress
      } catch (_) {
        return v.toString();
      }
    }
  } catch (_) {}
  if (v is Map) {
    final out = <String, dynamic>{};
    v.forEach((k, val) {
      final key = k is String ? k : k.toString();
      out[key] = _jsonEncodable(val);
    });
    return out;
  }
  if (v is Iterable) {
    return v.map(_jsonEncodable).toList();
  }
  // Fallback to string representation for any other type
  try {
    return v.toString();
  } catch (_) {
    return null;
  }
}

Future<int> main(List<String> args) async {
  // Short alias: `c` maps to <topic> check <target>
  if (args.isNotEmpty && args.first == 'c' && args.length >= 2) {
    // transform: c web https://example.com -> web check https://example.com
    final rest = args.sublist(1);
    final cmd = rest.first;
    final newArgs = <String>[];
    newArgs.add(cmd);
    newArgs.add('check');
    if (rest.length > 1) newArgs.addAll(rest.sublist(1));
    args = newArgs;
  }
  if (args.isEmpty) {
    // Menu-driven interactive interface with profiles and persistence
    final cfg = await ToolConfig.load();
    stdout.writeln(
      'lunariseye interactive menu (profiles saved in ${cfg.dir.path})',
    );
    stdout.writeln(
      'LEGAL: The user is solely responsible for any scanning activity and its consequences.',
    );
    stdout.writeln(
      'Do not use this tool on systems without proper authorization.',
    );
    printLogo();
    final console = Console();
    while (true) {
      stdout.writeln('');
      stdout.writeln('1) List profiles');
      stdout.writeln('2) Create profile');
      stdout.writeln('3) Run profile');
      stdout.writeln('4) Show last results');
      stdout.writeln('5) Export last results');
      stdout.writeln('6) Help');
      stdout.writeln('0) Exit');
      stdout.write('Select> ');
      final sel = stdin.readLineSync();
      if (sel == null) break;
      if (sel.trim() == '0') break;
      if (sel.trim() == '1') {
        if (cfg.profiles.isEmpty) {
          stdout.writeln('No profiles found');
        } else {
          for (final p in cfg.profiles.values) {
            stdout.writeln(
              '- ${p.name}: ${p.cidr} ports=${p.ports} concurrency=${p.concurrency}',
            );
          }
        }
        continue;
      }
      if (sel.trim() == '2') {
        stdout.write('Profile name: ');
        final name = stdin.readLineSync() ?? '';
        stdout.write('CIDR (e.g. 192.168.1.0/30): ');
        final cidr = stdin.readLineSync() ?? '';
        stdout.write('Ports (comma list): ');
        final ports = stdin.readLineSync() ?? '';
        stdout.write('Concurrency (hosts): ');
        final conc = int.tryParse(stdin.readLineSync() ?? '') ?? 100;
        final p = ToolProfile(
          name: name,
          cidr: cidr,
          ports: ports,
          concurrency: conc,
        );
        cfg.profiles[name] = p;
        await cfg.save();
        stdout.writeln('Profile saved');
        continue;
      }
      if (sel.trim() == '3') {
        stdout.write('Profile name to run: ');
        final name = stdin.readLineSync() ?? '';
        final p = cfg.profiles[name];
        if (p == null) {
          stdout.writeln('Profile not found');
          continue;
        }
        final hostsIter = sc.expandCidrLazy(p.cidr);
        final hosts = hostsIter.toList();
        final allowExternal =
            Platform.environment['lunariseye_ALLOW_EXTERNAL'] == '1';
        if (!allowExternal && hosts.any((h) => !sc.isPrivateIp(h))) {
          stdout.writeln('Refusing to scan non-private addresses by default.');
          stdout.writeln(
            'Set lunariseye_ALLOW_EXTERNAL=1 to override after ensuring authorization.',
          );
          continue;
        }
        // For very large ranges prefer lazy iteration and skip heavy prioritization
        final runHosts = hosts;
        final ordered = sc.prioritizeHosts(runHosts);
        stdout.writeln(
          'Running profile ${p.name} on ${ordered.length} hosts...',
        );
        final portList =
            p.ports
                .split(',')
                .map((s) => int.tryParse(s.trim()))
                .whereType<int>()
                .toList();
        var completed = 0;
        final results = await sc.scanNetwork(
          ordered,
          portList,
          hostConcurrency: p.concurrency,
          onHostResult: (host, r) {
            completed++;
            stdout.writeln(
              'Completed $completed/${ordered.length}: $host  -> ${r.keys.length} open ports',
            );
          },
        );
        cfg.setLastResults({'profile': p.name, 'results': results});
        await cfg.save();
        stdout.writeln('Scan complete. Use "Show last results" to view.');
        continue;
      }
      if (sel.trim() == '4') {
        if (cfg.lastResults == null) {
          stdout.writeln('No last results');
        } else {
          stdout.writeln(
            JsonEncoder.withIndent(
              '  ',
            ).convert(_jsonEncodable(cfg.lastResults)),
          );
        }
        continue;
      }
      if (sel.trim() == '5') {
        if (cfg.lastResults == null) {
          stdout.writeln('No last results');
          continue;
        }
        stdout.write('Export file path: ');
        final path = stdin.readLineSync() ?? '';
        try {
          final f = File(path);
          await f.writeAsString(
            JsonEncoder.withIndent(
              '  ',
            ).convert(_jsonEncodable(cfg.lastResults)),
          );
          stdout.writeln('Exported');
        } catch (e) {
          stdout.writeln('Failed to write: $e');
        }
        continue;
      }
      if (sel.trim() == '6') {
        printHelp();
        continue;
      }
      if (sel.trim() == '7') {
        // Interactive command picker
        final commands = [
          {
            'label': 'Scan (internal)  --cidr 192.168.1.0/24 --ports 80,443',
            'cmd': 'scan --cidr 192.168.1.0/24 --ports 80,443',
          },
          {
            'label':
                'Scan (external)  --cidr 198.51.100.0/24 --ports 80,443 --allow-external',
            'cmd':
                'scan --cidr 198.51.100.0/24 --ports 80,443 --allow-external',
          },
          {
            'label': 'Analyze URL      analyze https://example.com --json',
            'cmd': 'analyze https://example.com --json',
          },
          {
            'label': 'Resolve host     resolve example.com',
            'cmd': 'resolve example.com',
          },
        ];
        final picker = ListPicker(
          console,
          commands.map((c) => c['label'] as String).toList(),
        );
        final selection = picker.pick();
        if (selection != null) {
          final cmd = commands[selection]['cmd'] as String;
          stdout.writeln('Selected: $cmd');
          stdout.write('Run it? (y/N): ');
          final run = stdin.readLineSync() ?? 'n';
          if (run.toLowerCase() == 'y') {
            final parts = cmd.split(' ');
            await main(parts);
            return 0;
          }
        }
        continue;
      }
      stdout.writeln('Unknown selection');
    }
    return 0;
  }

  // Non-interactive single-shot mode
  // Very small manual parser: expected form -> scan --cidr <cidr> --ports 22,80
  if (args.first == 'resolve') {
    if (args.length < 2) {
      print('Usage: lunariseye resolve <hostname>');
      return 2;
    }
    final host = args[1];
    try {
      final ips = await InternetAddress.lookup(host);
      print('Resolved $host to:');
      for (final ip in ips) {
        print('  ${ip.address}');
      }
      print(
        'Suggestion: pick the IP you control or contact your hosting provider for the correct CIDR.',
      );
      return 0;
    } catch (e) {
      print('Failed to resolve $host: $e');
      return 2;
    }
  }

  if (args.first == 'analyze') {
    if (args.length < 2) {
      print('Usage: lunariseye analyze <url> [--json]');
      return 2;
    }
    final uriStr = args[1];
    final outputJsonFlag = args.contains('--json');
    final scanPortsFlag = args.contains('--scan-ports');
    // export path: allow explicit --export, otherwise default to timestamped file
    String? exportPathArg;
    for (var i = 2; i < args.length; i++) {
      if (args[i] == '--export' && i + 1 < args.length) {
        exportPathArg = args[i + 1];
      }
    }
    final exportPath = exportPathArg ?? _defaultExportPath('analyze');
    String? portsArg;
    for (var i = 2; i < args.length; i++) {
      if (args[i] == '--ports' && i + 1 < args.length) {
        portsArg = args[i + 1];
      }
    }

    try {
      final uri = Uri.parse(uriStr);
      final client = HttpClient();
      final sw = Stopwatch()..start();
      final req = await client.getUrl(uri);
      final resp = await req.close();
      sw.stop();
      final body = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));

      final titleMatch = RegExp(
        r'<title[^>]*>([\s\S]*?)<\/title>',
        caseSensitive: false,
      ).firstMatch(body);
      final title = titleMatch?.group(1)?.trim();
      final server = resp.headers.value('server');
      final contentLength = resp.headers.contentLength;

      final result = <String, dynamic>{
        'url': uri.toString(),
        'status': resp.statusCode,
        'server': server,
        'responseTimeMs': sw.elapsedMilliseconds,
        'title': title,
        'contentLength': contentLength,
      };

      // Header security checks
      final headers = resp.headers;
      final hsts = headers.value('strict-transport-security');
      final csp =
          headers.value('content-security-policy') ??
          headers.value('x-content-security-policy');
      final xfo = headers.value('x-frame-options');
      final headerSecurity = <String, dynamic>{};

      if (hsts == null) {
        headerSecurity['hsts'] = {
          'present': false,
          'warning':
              'HSTS missing; enable Strict-Transport-Security with an appropriate max-age.',
        };
      } else {
        final m = RegExp(r'max-age=(\d+)').firstMatch(hsts);
        var maxAge = m != null ? int.tryParse(m.group(1)!) ?? 0 : 0;
        final includeSub = hsts.toLowerCase().contains('includesubdomains');
        headerSecurity['hsts'] = {
          'present': true,
          'maxAge': maxAge,
          'includeSubDomains': includeSub,
        };
        if (maxAge < 31536000) {
          headerSecurity['hsts']['warning'] =
              'HSTS max-age is below 1 year; consider increasing to at least 31536000.';
        }
      }
      headerSecurity['csp'] =
          csp == null ? {'present': false} : {'present': true};
      headerSecurity['x-frame-options'] =
          xfo == null ? {'present': false} : {'present': true, 'value': xfo};

      result['headerSecurity'] = headerSecurity;

      // Optional port scan of the target host (requires --scan-ports)
      if (scanPortsFlag) {
        List<int> portsToScan;
        if (portsArg != null) {
          portsToScan =
              portsArg
                  .split(',')
                  .map((s) => int.tryParse(s.trim()))
                  .where((v) => v != null)
                  .map((v) => v!)
                  .toList();
        } else {
          portsToScan = [
            21,
            22,
            23,
            25,
            53,
            80,
            110,
            143,
            443,
            3306,
            3389,
            8080,
          ];
        }

        final hostName = uri.host;
        try {
          final addrs = await InternetAddress.lookup(hostName);
          InternetAddress? chosen;
          for (final a in addrs) {
            if (a.type == InternetAddressType.IPv4) {
              chosen = a;
              break;
            }
          }
          chosen ??= addrs.isNotEmpty ? addrs.first : null;
          if (chosen == null) {
            result['portScan'] = {'error': 'failed to resolve host'};
          } else {
            final isPrivate = sc.isPrivateIp(chosen.address);
            if (!isPrivate) {
              stdout.writeln(
                'Warning: target resolves to non-private IP; ensure you have authorization to scan external hosts.',
              );
            }
            final scanResult = await sc.scanHost(
              chosen.address,
              portsToScan,
              portConcurrency: 20,
            );
            result['portScan'] = scanResult;
          }
        } catch (e) {
          result['portScan'] = {'error': 'lookup failed: $e'};
        }
      }

      // Always write a JSON export (default path used when none provided).
      try {
        final f = File(exportPath);
        await f.writeAsString(
          JsonEncoder.withIndent('  ').convert(_jsonEncodable(result)),
        );
        stdout.writeln('Wrote JSON export to $exportPath');
      } catch (e) {
        stdout.writeln('Failed to write export to $exportPath: $e');
      }

      if (outputJsonFlag) {
        print(JsonEncoder.withIndent('  ').convert(_jsonEncodable(result)));
      } else {
        print('Analysis for ${uri.toString()}');
        print('  Status: ${resp.statusCode}');
        print('  Server: ${server ?? "(unknown)"}');
        print('  Title: ${title ?? "(none)"}');
        print('  Response time: ${sw.elapsedMilliseconds} ms');
        print('  Content-Length header: $contentLength');
        // print header security warnings
        if (headerSecurity.isNotEmpty) {
          print('  Header security:');
          headerSecurity.forEach((k, v) {
            print('    $k: $v');
          });
        }
        if (result.containsKey('portScan')) {
          print('  Port scan: ${result['portScan']}');
        }
      }

      return 0;
    } catch (e) {
      print('Failed to analyze $uriStr: $e');
      return 2;
    }
  }

  // New: web subcommand for higher-level web checks
  if (args.first == 'web') {
    // usage: lunariseye web check <url> [--json] [--scan-ports] [--allow-external]
    if (args.length < 3) {
      print('Usage: lunariseye web check <url> [--json] [--scan-ports]');
      return 2;
    }
    final sub = args[1];
    if (sub != 'check') {
      print('Unknown web command: $sub');
      return 2;
    }
    final uriStr = args[2];
    final outputJsonFlag = args.contains('--json');
    final scanPortsFlag = args.contains('--scan-ports');
    String? exportPathArg;
    for (var i = 3; i < args.length; i++) {
      if (args[i] == '--export' && i + 1 < args.length) {
        exportPathArg = args[i + 1];
      }
    }
    final exportPath = exportPathArg ?? _defaultExportPath('webcheck');
    try {
      final uri = Uri.parse(uriStr);
      final sw = Stopwatch()..start();
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(uri);
      final resp = await req.close().timeout(const Duration(seconds: 10));
      sw.stop();
      final body = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));

      // Basic performance metrics
      final bytes = utf8.encode(body).length;
      final resourceUrls = <String>[];
      final urlRegex = RegExp(
        r'(?:src|href)=\"([^\"]+)\"',
        caseSensitive: false,
      );
      for (final m in urlRegex.allMatches(body)) {
        resourceUrls.add(m.group(1)!);
      }
      final externalResources =
          resourceUrls.where((u) => u.startsWith('http')).toList();
      final mixed =
          externalResources.where((u) => u.startsWith('http://')).toList();

      final titleMatch = RegExp(
        r'<title[^>]*>([\s\S]*?)<\/title>',
        caseSensitive: false,
      ).firstMatch(body);
      final title = titleMatch?.group(1)?.trim();

      // header security checks (reuse existing logic)
      final headers = resp.headers;
      final hsts = headers.value('strict-transport-security');
      final csp =
          headers.value('content-security-policy') ??
          headers.value('x-content-security-policy');
      final xfo = headers.value('x-frame-options');
      final headerSecurity = <String, dynamic>{};
      if (hsts == null) {
        headerSecurity['hsts'] = {'present': false, 'warning': 'HSTS missing'};
      } else {
        final m = RegExp(r'max-age=(\d+)').firstMatch(hsts);
        var maxAge = m != null ? int.tryParse(m.group(1)!) ?? 0 : 0;
        final includeSub = hsts.toLowerCase().contains('includesubdomains');
        headerSecurity['hsts'] = {
          'present': true,
          'maxAge': maxAge,
          'includeSubDomains': includeSub,
        };
      }
      headerSecurity['csp'] =
          csp == null ? {'present': false} : {'present': true};
      headerSecurity['x-frame-options'] =
          xfo == null ? {'present': false} : {'present': true, 'value': xfo};

      // TLS cert inspection
      Map<String, dynamic>? certInfo;
      try {
        final host = uri.host;
        final cert = await sc.inspectTlsCertificate(host, 443);
        if (cert != null) certInfo = cert;
      } catch (_) {}

      // GeoIP and traceroute and fingerprint/waf detection
      Map<String, dynamic>? geoip;
      List<String>? trace;
      final headersMap = <String, String>{};
      resp.headers.forEach((k, v) => headersMap[k] = v.join(', '));
      try {
        final addrs = await InternetAddress.lookup(uri.host);
        if (addrs.isNotEmpty) {
          final ip = addrs.first.address;
          final g = await sc.geoIpLookup(ip);
          if (g != null) geoip = g;
        }
      } catch (_) {}
      try {
        trace = await sc.traceroute(uri.host);
      } catch (_) {
        trace = null;
      }
      final fp = sc.fingerprintService(headers: headersMap, banner: null);
      final waf = sc.detectWafCdns(headersMap, null);

      final result = <String, dynamic>{
        'url': uri.toString(),
        'status': resp.statusCode,
        'title': title,
        'responseTimeMs': sw.elapsedMilliseconds,
        'bodyBytes': bytes,
        'resourceCount': resourceUrls.length,
        'externalResources': externalResources.length,
        'mixedContentCount': mixed.length,
        'headerSecurity': headerSecurity,
        'server': resp.headers.value('server'),
        'tls': certInfo,
        'geoip': geoip,
        'traceroute': trace,
        'fingerprint': fp,
        'waf_cdns': waf,
      };

      // optional quick port scan
      if (scanPortsFlag) {
        try {
          final ips = await InternetAddress.lookup(uri.host);
          final chosen = ips.isNotEmpty ? ips.first.address : null;
          if (chosen != null && !sc.isPrivateIp(chosen)) {
            stdout.writeln(
              'Warning: target resolves to non-private IP; ensure you have authorization to scan external hosts.',
            );
          }
          if (chosen != null) {
            final scanRes = await sc.scanHost(chosen, [
              80,
              443,
              22,
              8080,
            ], portConcurrency: 8);
            result['portScan'] = scanRes;
          }
        } catch (e) {
          result['portScan'] = {'error': 'lookup failed: $e'};
        }
      }

      // Always write a JSON export by default
      try {
        final f = File(exportPath);
        await f.writeAsString(
          JsonEncoder.withIndent('  ').convert(_jsonEncodable(result)),
        );
        stdout.writeln('Wrote JSON export to $exportPath');
      } catch (e) {
        stdout.writeln('Failed to write export to $exportPath: $e');
      }

      if (outputJsonFlag) {
        print(JsonEncoder.withIndent('  ').convert(_jsonEncodable(result)));
      } else {
        print('Web check for ${uri.toString()}');
        print('  Status: ${resp.statusCode}');
        print('  Title: ${title ?? '(none)'}');
        print('  Server: ${resp.headers.value('server') ?? '(unknown)'}');
        print('  Response time: ${sw.elapsedMilliseconds} ms');
        print('  Body size (bytes): $bytes');
        print(
          '  Resources found: ${resourceUrls.length}, external: ${externalResources.length}, mixed: ${mixed.length}',
        );
        print('  Header security summary:');
        headerSecurity.forEach((k, v) => print('    $k: $v'));
        if (certInfo != null) print('  TLS cert: $certInfo');
        if (geoip != null) {
          print(
            '  GeoIP: ${geoip['country'] ?? geoip['regionName'] ?? geoip['isp'] ?? geoip}',
          );
        }
        if (trace != null && trace.isNotEmpty) {
          print('  Traceroute hops: ${trace.length}');
        }
        if (fp['name'] != null) {
          print(
            '  Fingerprint: ${fp['name']} (confidence ${fp['confidence']})',
          );
        }
        if (waf.isNotEmpty) print('  WAF/CDN detected: ${waf.join(', ')}');
        if (result.containsKey('portScan')) {
          print('  Port scan: ${result['portScan']}');
        }
      }
      return 0;
    } catch (e) {
      print('Web check failed for $uriStr: $e');
      return 2;
    }
  }

  // port check: lunariseye port check <host> [--ports 80,443] [--json] [--allow-external]
  if (args.first == 'port') {
    if (args.length < 3 || args[1] != 'check') {
      print('Usage: lunariseye port check <host> [--ports 80,443] [--json]');
      return 2;
    }
    final host = args[2];
    final outputJsonFlag = args.contains('--json');
    String? exportPathArg;
    for (var i = 3; i < args.length; i++) {
      if (args[i] == '--export' && i + 1 < args.length) {
        exportPathArg = args[i + 1];
      }
    }
    final exportPath = exportPathArg ?? _defaultExportPath('portcheck');
    String? portsArg;
    for (var i = 3; i < args.length; i++) {
      if (args[i] == '--ports' && i + 1 < args.length) portsArg = args[++i];
    }
    final ports =
        portsArg != null
            ? portsArg
                .split(',')
                .map((s) => int.tryParse(s.trim()))
                .whereType<int>()
                .toList()
            : [80, 443, 22, 8080];
    try {
      final addrs = await InternetAddress.lookup(host);
      final chosen = addrs.isNotEmpty ? addrs.first.address : null;
      final allowExternal =
          Platform.environment['lunariseye_ALLOW_EXTERNAL'] == '1' ||
          args.contains('--allow-external');
      if (chosen != null && !sc.isPrivateIp(chosen) && !allowExternal) {
        print(
          'Target resolves to non-private IP; set --allow-external or lunariseye_ALLOW_EXTERNAL=1 to permit external checks.',
        );
        return 2;
      }
      final res = await sc.scanHost(chosen ?? host, ports, portConcurrency: 8);
      final result = {'host': host, 'ports': res};
      // write export
      try {
        final f = File(exportPath);
        await f.writeAsString(
          JsonEncoder.withIndent('  ').convert(_jsonEncodable(result)),
        );
        stdout.writeln('Wrote JSON export to $exportPath');
      } catch (e) {
        stdout.writeln('Failed to write export to $exportPath: $e');
      }
      if (outputJsonFlag) {
        print(JsonEncoder.withIndent('  ').convert(_jsonEncodable(result)));
      } else {
        print('Port check for $host:');
        for (final e in res.entries) {
          print('  ${e.key}: ${e.value}');
        }
      }
      return 0;
    } catch (e) {
      print('Port check failed: $e');
      return 2;
    }
  }

  // cert check: lunariseye cert check <host> [--port 443] [--json]
  if (args.first == 'cert') {
    if (args.length < 3 || args[1] != 'check') {
      print('Usage: lunariseye cert check <host> [--port 443] [--json]');
      return 2;
    }
    final host = args[2];
    var port = 443;
    final outputJsonFlag = args.contains('--json');
    String? exportPathArg;
    for (var i = 3; i < args.length; i++) {
      if (args[i] == '--export' && i + 1 < args.length) {
        exportPathArg = args[i + 1];
      }
    }
    final exportPath = exportPathArg ?? _defaultExportPath('certcheck');
    for (var i = 3; i < args.length; i++) {
      if (args[i] == '--port' && i + 1 < args.length) {
        port = int.tryParse(args[++i]) ?? port;
      }
    }
    try {
      final cert = await sc.inspectTlsCertificate(host, port);
      if (cert == null) {
        print('No certificate retrieved for $host:$port');
        return 2;
      }
      final result = {'host': host, 'port': port, 'cert': cert};
      try {
        final f = File(exportPath);
        await f.writeAsString(
          JsonEncoder.withIndent('  ').convert(_jsonEncodable(result)),
        );
        stdout.writeln('Wrote JSON export to $exportPath');
      } catch (e) {
        stdout.writeln('Failed to write export to $exportPath: $e');
      }
      if (outputJsonFlag) {
        print(JsonEncoder.withIndent('  ').convert(_jsonEncodable(result)));
      } else {
        print('Certificate for $host:$port');
        cert.forEach((k, v) => print('  $k: $v'));
      }
      return 0;
    } catch (e) {
      print('Cert check failed: $e');
      return 2;
    }
  }

  // dns check: lunariseye dns check <host> [--json]
  if (args.first == 'dns') {
    if (args.length < 3 || args[1] != 'check') {
      print('Usage: lunariseye dns check <host> [--json]');
      return 2;
    }
    final host = args[2];
    final outputJsonFlag = args.contains('--json');
    String? exportPathArg;
    for (var i = 3; i < args.length; i++) {
      if (args[i] == '--export' && i + 1 < args.length) {
        exportPathArg = args[i + 1];
      }
    }
    final exportPath = exportPathArg ?? _defaultExportPath('dnscheck');
    try {
      final cname =
          (await Process.run('dig', [
            '+short',
            'CNAME',
            host,
          ])).stdout.toString().trim();
      final a =
          (await Process.run('dig', ['+short', 'A', host])).stdout
              .toString()
              .trim()
              .split('\n')
              .where((s) => s.isNotEmpty)
              .toList();
      final takeoverHint = <String>[];
      if (cname.isNotEmpty) {
        // probe cname target quickly
        try {
          final httpHead = await Process.run('curl', ['-sI', 'http://$cname']);
          final httpOut = httpHead.stdout.toString();
          if (httpOut.contains('404') ||
              httpOut.toLowerCase().contains('no such')) {
            takeoverHint.add(
              'CNAME target responded with 404 or no-service (possible takeover)',
            );
          }
        } catch (_) {}
      }
      final result = {
        'host': host,
        'cname': cname.isEmpty ? null : cname,
        'a': a,
        'takeoverHints': takeoverHint,
      };
      try {
        final f = File(exportPath);
        await f.writeAsString(
          JsonEncoder.withIndent('  ').convert(_jsonEncodable(result)),
        );
        stdout.writeln('Wrote JSON export to $exportPath');
      } catch (e) {
        stdout.writeln('Failed to write export to $exportPath: $e');
      }
      if (outputJsonFlag) {
        print(JsonEncoder.withIndent('  ').convert(_jsonEncodable(result)));
      } else {
        print('DNS check: $result');
      }
      return 0;
    } catch (e) {
      print('DNS check failed: $e');
      return 2;
    }
  }

  // phone check: lunariseye phone check <host> [--ports 80,443] [--json] [--export <path>]
  if (args.first == 'phone') {
    if (args.length < 3 || args[1] != 'check') {
      print(
        'Usage: lunariseye phone check <host> [--ports 80,443] [--json] [--export <path>]',
      );
      return 2;
    }
    final host = args[2];
    final outputJsonFlag = args.contains('--json');
    String? exportPathArg;
    for (var i = 3; i < args.length; i++) {
      if (args[i] == '--export' && i + 1 < args.length) {
        exportPathArg = args[i + 1];
      }
    }
    final exportPath = exportPathArg ?? _defaultExportPath('phonecheck');
    String? portsArg;
    for (var i = 3; i < args.length; i++) {
      if (args[i] == '--ports' && i + 1 < args.length) portsArg = args[++i];
    }
    final ports =
        portsArg != null
            ? portsArg
                .split(',')
                .map((s) => int.tryParse(s.trim()))
                .whereType<int>()
                .toList()
            : [22, 23, 80, 443, 5555, 5228, 8000, 8080];

    try {
      // Resolve host to IP if possible
      String? chosen;
      try {
        final addrs = await InternetAddress.lookup(host);
        if (addrs.isNotEmpty) chosen = addrs.first.address;
      } catch (_) {
        chosen = host;
      }

      if (chosen == null) {
        print('Failed to resolve $host');
        return 2;
      }

      if (!sc.isPrivateIp(chosen)) {
        stdout.writeln(
          'Warning: target resolves to non-private IP; ensure you have authorization to scan.',
        );
      }

      final scanRes = await sc.scanHost(chosen, ports, portConcurrency: 20);

      // Collect TLS info if 443 open
      Map<String, dynamic>? certInfo;
      if (scanRes.keys.contains(443)) {
        try {
          certInfo = await sc.inspectTlsCertificate(chosen, 443);
        } catch (_) {}
      }

      // Try quick HTTP HEAD if http(s) ports present
      Map<String, String>? headersMap;
      try {
        if (scanRes.keys.any(
          (p) => p == 80 || p == 8080 || p == 8000 || p == 443,
        )) {
          final uri = Uri.parse('https://$chosen/');
          final client = HttpClient();
          client.connectionTimeout = Duration(seconds: 5);
          try {
            final req = await client.getUrl(uri).timeout(Duration(seconds: 5));
            final resp = await req.close().timeout(Duration(seconds: 5));
            headersMap = <String, String>{};
            resp.headers.forEach((k, v) => headersMap![k] = v.join(', '));
          } catch (_) {
            // try plain http
            try {
              final uri2 = Uri.parse('http://$chosen/');
              final req2 = await client
                  .getUrl(uri2)
                  .timeout(Duration(seconds: 5));
              final resp2 = await req2.close().timeout(Duration(seconds: 5));
              headersMap = <String, String>{};
              resp2.headers.forEach((k, v) => headersMap![k] = v.join(', '));
            } catch (_) {}
          }
          client.close();
        }
      } catch (_) {
        headersMap = null;
      }

      // GeoIP and traceroute
      Map<String, dynamic>? geoip;
      List<String>? trace;
      try {
        geoip = await sc.geoIpLookup(chosen);
      } catch (_) {}
      try {
        trace = await sc.traceroute(chosen);
      } catch (_) {}

      final fp = sc.fingerprintService(headers: headersMap, banner: null);
      final waf = sc.detectWafCdns(headersMap, null);

      // Build ports detail list
      final portsList = <Map<String, dynamic>>[];
      for (final e in scanRes.entries) {
        portsList.add({
          'port': e.key,
          'banner': e.value['banner'],
          'protocol': e.value['protocol'],
          'service': e.value['service'],
          'severity': e.value['severity'],
        });
      }

      // Aggregate severity counts
      final counts = <String, int>{};
      int highestScore = 0;
      String? highestLevel;
      int? highestPort;
      for (final p in portsList) {
        final sev = p['severity'];
        if (sev is Map && sev['level'] is String) {
          final lvl = sev['level'] as String;
          counts[lvl] = (counts[lvl] ?? 0) + 1;
          final score = (sev['score'] is int) ? sev['score'] as int : 0;
          if (score > highestScore) {
            highestScore = score;
            highestLevel = lvl;
            highestPort = p['port'] as int;
          }
        }
      }

      final result = <String, dynamic>{
        'host': host,
        'ip': chosen,
        'timestamp': DateTime.now().toIso8601String(),
        'ports': portsList,
        'ports_open_count': portsList.length,
        'tls': certInfo,
        'headers': headersMap,
        'fingerprint': fp,
        'waf_cdns': waf,
        'geoip': geoip,
        'traceroute': trace,
        'severity_summary': {
          'counts': counts,
          'highest':
              highestScore > 0
                  ? {
                    'score': highestScore,
                    'level': highestLevel,
                    'port': highestPort,
                  }
                  : null,
        },
      };

      // write export
      try {
        final f = File(exportPath);
        await f.writeAsString(
          JsonEncoder.withIndent('  ').convert(_jsonEncodable(result)),
        );
        stdout.writeln('Wrote JSON export to $exportPath');
      } catch (e) {
        stdout.writeln('Failed to write export to $exportPath: $e');
      }

      if (outputJsonFlag) {
        print(JsonEncoder.withIndent('  ').convert(_jsonEncodable(result)));
      } else {
        print('Phone check for $host ($chosen)');
        print('  Open ports: ${portsList.length}');
        if (counts.isNotEmpty) print('  Severity counts: $counts');
        if (highestLevel != null) {
          print(
            '  Highest: $highestLevel on port $highestPort (score $highestScore)',
          );
        }
        if (certInfo != null) print('  TLS: $certInfo');
        if (fp['name'] != null) {
          print(
            '  Fingerprint: ${fp['name']} (confidence ${fp['confidence']})',
          );
        }
        if (waf.isNotEmpty) print('  WAF/CDN detected: ${waf.join(', ')}');
      }

      return 0;
    } catch (e) {
      print('Phone check failed: $e');
      return 2;
    }
  }

  if (args.first != 'scan') {
    printHelp();
    return 1;
  }

  String? cidr;
  String? portsStr;
  var concurrency = 100;
  var outputJson = false;
  String? exportPath;
  var jsonl = false;
  var ordering = 'linkstate';
  for (var i = 1; i < args.length; i++) {
    final a = args[i];
    if (a == '--cidr' && i + 1 < args.length) {
      cidr = args[++i];
    } else if (a == '--ports' && i + 1 < args.length) {
      portsStr = args[++i];
    } else if (a == '--all-ports') {
      // signal to scan all 1..65535
      portsStr = 'ALL';
    } else if ((a == '--concurrency' || a == '-n') && i + 1 < args.length) {
      concurrency = int.tryParse(args[++i]) ?? concurrency;
    } else if (a == '--json') {
      outputJson = true;
    } else if (a == '--jsonl') {
      jsonl = true;
    } else if (a == '--export' && i + 1 < args.length) {
      exportPath = args[++i];
    } else if (a == '--output' && i + 1 < args.length) {
      exportPath = args[++i];
    } else if (a == '--ordering' && i + 1 < args.length) {
      ordering = args[++i];
    }
  }

  if (cidr == null) {
    print('Please provide --cidr');
    return 2;
  }

  // Default export path for scans when not provided explicitly
  exportPath ??= _defaultExportPath('scan');

  // Default: scan all TCP ports (1..65535) unless --ports is provided.
  final ports =
      (portsStr == null)
          ? List<int>.generate(65535, (i) => i + 1)
          : (portsStr == 'ALL'
              ? List<int>.generate(65535, (i) => i + 1)
              : portsStr
                  .split(',')
                  .map((s) => int.tryParse(s.trim()))
                  .where((v) => v != null)
                  .map((v) => v!)
                  .toList());
  // For large CIDRs, prefer lazy expansion
  final hostsIter = sc.expandCidrLazy(cidr);
  final hosts = hostsIter.toList();
  final allowExternal =
      Platform.environment['lunariseye_ALLOW_EXTERNAL'] == '1' ||
      args.contains('--allow-external');
  if (hosts.any((h) => !sc.isPrivateIp(h))) {
    stdout.writeln(
      'Warning: target list includes non-private addresses; ensure you have authorization to scan external hosts.',
    );
    if (!allowExternal) {
      stdout.writeln(
        'Note: previously the tool refused to scan external addresses by default; that restriction has been lifted per configuration.',
      );
    }
  }
  final ordered = sc.prioritizeHosts(hosts, ordering: ordering);
  print(
    'Scanning ${ordered.length} hosts (ordered) with ${ports.length} ports each',
  );
  // Note: default now scans all TCP ports if --ports is not provided.
  // Large/intrusive scans are allowed by default; ensure you have authorization
  // to scan targets before running this tool.
  var completed = 0;

  IOSink? sink;
  if (jsonl) {
    try {
      final f = File(exportPath);
      // Truncate file to start fresh for this JSONL run
      sink = f.openWrite(mode: FileMode.write);
    } catch (e) {
      stdout.writeln('Failed to open output file $exportPath for JSONL: $e');
      return 2;
    }
  }

  final results = await sc.scanNetwork(
    ordered,
    ports,
    hostConcurrency: concurrency,
    onHostResult: (host, r) {
      completed++;
      stdout.writeln(
        'Completed $completed/${ordered.length}: $host  -> ${r.keys.length} open ports',
      );
    },
    jsonlSink: sink,
  );

  if (sink != null) {
    await sink.flush();
    await sink.close();
  }

  // Prepare a pretty JSON output of full results and write/export as requested.
  final out = JsonEncoder.withIndent('  ').convert(_jsonEncodable(results));
  if (outputJson) print(out);
  if (!jsonl) {
    try {
      final f = File(exportPath);
      await f.writeAsString(out);
      stdout.writeln('Exported results to $exportPath');
    } catch (e) {
      stdout.writeln('Failed to export to $exportPath: $e');
    }
  }

  // Always show detailed results to the user after a scan completes.
  stdout.writeln('Detailed scan results:');
  stdout.writeln(out);

  return 0;
}

/// Small console list picker using arrow keys. Returns selected index or null.
class ListPicker {
  final Console _console;
  final List<String> _items;
  ListPicker(this._console, this._items);

  int? pick() {
    if (_items.isEmpty) return null;
    var idx = 0;
    _console.rawMode = true;
    try {
      while (true) {
        _console.clearScreen();
        _console.writeLine(
          'Use Up/Down to navigate, Enter to select, q to cancel',
        );
        for (var i = 0; i < _items.length; i++) {
          if (i == idx) {
            _console.setForegroundColor(ConsoleColor.brightGreen);
            _console.writeLine('> ${_items[i]}');
            _console.resetColorAttributes();
          } else {
            _console.writeLine('  ${_items[i]}');
          }
        }
        final key = _console.readKey();
        if (key.controlChar == ControlCharacter.enter) {
          return idx;
        }
        if (key.char == 'q') return null;
        if (key.controlChar == ControlCharacter.arrowUp) {
          idx = (idx - 1) < 0 ? _items.length - 1 : idx - 1;
        }
        if (key.controlChar == ControlCharacter.arrowDown) {
          idx = (idx + 1) % _items.length;
        }
      }
    } finally {
      _console.rawMode = false;
    }
  }
}
