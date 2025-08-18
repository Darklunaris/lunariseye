import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/app_bloc.dart';
import '../bloc/app_state.dart';
import '../widgets/glass_container.dart';
import 'package:lunariseye/scanner.dart' as sc;

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _cidrController = TextEditingController(text: '192.168.1.0/30');
  final _portsController = TextEditingController(text: '22,80,443');
  String _output = '';
  bool _running = false;

  Future<void> _runScan() async {
    setState(() {
      _running = true;
      _output = 'Running scan...';
    });
    try {
      final cidr = _cidrController.text.trim();
      final ports = _portsController.text
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toList();
      final hosts = sc.expandCidr(cidr);
      final results = await sc.scanNetwork(
        hosts,
        ports,
        hostConcurrency: 5,
        portConcurrency: 20,
        onHostResult: (host, r) {
          if (!mounted) return;
          setState(() {
            _output = 'Progress: host $host completed — ${r.keys.length} open';
          });
        },
      );
      // Normalize results to be JSON-encodable (map keys must be strings).
      Map<String, dynamic> normalize(
        Map<String, Map<int, Map<String, dynamic>>> r,
      ) {
        final out = <String, dynamic>{};
        r.forEach((host, portsMap) {
          final portsList = <Map<String, dynamic>>[];
          portsMap.forEach((p, info) {
            final m = <String, dynamic>{'port': p};
            info.forEach((k, v) {
              if (v is DateTime) {
                m[k] = v.toIso8601String();
              } else if (v is InternetAddress) {
                m[k] = v.address;
              } else if (v is Map) {
                // Attempt to convert nested maps recursively to simple maps
                try {
                  m[k] = jsonDecode(jsonEncode(v));
                } catch (_) {
                  m[k] = v.toString();
                }
              } else {
                m[k] = v;
              }
            });
            portsList.add(m);
          });
          out[host] = {'open_count': portsList.length, 'ports': portsList};
        });
        return out;
      }

      final enc = normalize(results);
      final file = File('docs/examples/scan_gui.json');
      await file.create(recursive: true);
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(enc));
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _output = const JsonEncoder.withIndent('  ').convert(enc);
        });
      });
    } catch (e) {
      setState(() {
        _output = 'Error: $e';
      });
    } finally {
      setState(() {
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppBloc, AppStatus>(
      builder: (context, appState) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              GlassContainer(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Scan configuration',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _cidrController,
                      decoration: const InputDecoration(labelText: 'CIDR'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _portsController,
                      decoration: const InputDecoration(
                        labelText: 'Ports (comma separated)',
                      ),
                    ),
                    ExpansionTile(
                      title: const Text('Advanced options'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Column(
                            children: const [
                              SizedBox(height: 8),
                              Text('Advanced flags will be implemented here.'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _running ? null : _runScan,
                          icon: _running
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.play_arrow),
                          label: Text(_running ? 'Running...' : 'Run Scan'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final file = File('docs/examples/scan_gui.json');
                            if (await file.exists()) {
                              final content = await file.readAsString();
                              if (!mounted) return;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('Export'),
                                    content: SingleChildScrollView(
                                      child: Text(content),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Close'),
                                      ),
                                    ],
                                  ),
                                );
                              });
                            }
                          },
                          icon: const Icon(Icons.file_open),
                          label: const Text('Show Export'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: GlassContainer(
                  padding: const EdgeInsets.all(12.0),
                  child: SingleChildScrollView(child: SelectableText(_output)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
