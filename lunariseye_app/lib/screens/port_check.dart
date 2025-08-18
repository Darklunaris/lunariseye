import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/app_bloc.dart';
import '../bloc/app_state.dart';
import '../widgets/glass_container.dart';
import 'package:lunariseye/scanner.dart' as sc;

class PortCheckScreen extends StatefulWidget {
  const PortCheckScreen({super.key});

  @override
  State<PortCheckScreen> createState() => _PortCheckScreenState();
}

class _PortCheckScreenState extends State<PortCheckScreen> {
  final _hostController = TextEditingController(text: '192.168.1.1');
  final _portsController = TextEditingController(text: '22,80,443');
  int _hostConcurrency = 5;
  int _portConcurrency = 20;
  int _timeoutMs = 300;
  String _output = '';
  bool _running = false;
  String _lastExport = '';

  Future<void> _runPortCheck() async {
    setState(() {
      _running = true;
      _output = 'Running port check...';
    });
    try {
      final host = _hostController.text.trim();
      final ports = _portsController.text
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toList();
      final results = await sc.scanHost(
        host,
        ports,
        portConcurrency: _portConcurrency,
        timeout: Duration(milliseconds: _timeoutMs),
      );
      final enc = {
        'host': host,
        'results': results.map((k, v) => MapEntry(k.toString(), v)),
        'meta': {
          'hostConcurrency': _hostConcurrency,
          'portConcurrency': _portConcurrency,
          'timeoutMs': _timeoutMs,
          'timestamp': DateTime.now().toIso8601String(),
        },
      };
      final file = File('docs/examples/portcheck_gui.json');
      await file.create(recursive: true);
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(enc));
      _lastExport = file.path;
      if (!mounted) return;
      setState(() {
        _output = const JsonEncoder.withIndent('  ').convert(enc);
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

  Future<void> _revokeLastExport() async {
    if (_lastExport.isEmpty) return;
    final f = File(_lastExport);
    if (await f.exists()) {
      await f.delete();
      if (!mounted) return;
      setState(() {
        _output = 'Export revoked: $_lastExport';
        _lastExport = '';
      });
    }
  }

  Future<void> _runAdvancedProbes() async {
    final host = _hostController.text.trim();
    setState(() {
      _running = true;
      _output = 'Running advanced probes...';
    });
    try {
      Map<String, dynamic>? cert;
      List<String>? trace;
      Map<String, dynamic>? geo;
      Map<String, dynamic> fp = {};
      try {
        cert = await sc.inspectTlsCertificate(host, 443);
      } catch (_) {}
      try {
        trace = await sc.traceroute(host);
      } catch (_) {}
      try {
        geo = await sc.geoIpLookup(host);
      } catch (_) {}
      try {
        fp = sc.fingerprintService(headers: null, banner: null);
      } catch (_) {}

      final result = {
        'host': host,
        'cert': cert,
        'traceroute': trace,
        'geoip': geo,
        'fingerprint': fp,
        'meta': {'timestamp': DateTime.now().toIso8601String()},
      };

      final file = File(
        'docs/examples/portcheck_advanced_${DateTime.now().toIso8601String().replaceAll(':', '')}.json',
      );
      await file.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(result),
      );
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _lastExport = file.path;
          _output = const JsonEncoder.withIndent('  ').convert(result);
        });
      });
    } catch (e) {
      setState(() => _output = 'Advanced probes failed: $e');
    } finally {
      setState(() => _running = false);
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
                      'Port check',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _hostController,
                      decoration: const InputDecoration(labelText: 'Host'),
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
                            children: [
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text('Host concurrency'),
                                        Slider(
                                          value: _hostConcurrency.toDouble(),
                                          min: 1,
                                          max: 50,
                                          divisions: 49,
                                          label: '$_hostConcurrency',
                                          onChanged: (v) => setState(
                                            () => _hostConcurrency = v.toInt(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text('Port concurrency'),
                                        Slider(
                                          value: _portConcurrency.toDouble(),
                                          min: 1,
                                          max: 200,
                                          divisions: 199,
                                          label: '$_portConcurrency',
                                          onChanged: (v) => setState(
                                            () => _portConcurrency = v.toInt(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text('Timeout (ms): '),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: '300',
                                      keyboardType: TextInputType.number,
                                      onChanged: (v) =>
                                          _timeoutMs = int.tryParse(v) ?? 300,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _running ? null : _runPortCheck,
                          icon: _running
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.play_arrow),
                          label: Text(
                            _running ? 'Running...' : 'Run Port Check',
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _running ? null : _runAdvancedProbes,
                          icon: const Icon(Icons.bolt),
                          label: const Text('Advanced Probes'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orangeAccent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _lastExport.isEmpty
                              ? null
                              : () async {
                                  final f = File(_lastExport);
                                  if (await f.exists()) {
                                    final content = await f.readAsString();
                                    if (!mounted) return;
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (!mounted) return;
                                          showDialog(
                                            context: context,
                                            builder: (_) => AlertDialog(
                                              title: const Text('Last Export'),
                                              content: SingleChildScrollView(
                                                child: Text(content),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(context),
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
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _lastExport.isEmpty
                              ? null
                              : _revokeLastExport,
                          icon: const Icon(Icons.delete_forever),
                          label: const Text('Revoke'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                          ),
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
