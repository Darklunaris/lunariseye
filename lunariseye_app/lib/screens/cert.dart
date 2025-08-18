import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/app_bloc.dart';
import '../bloc/app_state.dart';
import '../widgets/glass_container.dart';
import 'package:lunariseye/scanner.dart' as sc;

class CertScreen extends StatefulWidget {
  const CertScreen({super.key});

  @override
  State<CertScreen> createState() => _CertScreenState();
}

class _CertScreenState extends State<CertScreen> {
  final _hostController = TextEditingController(text: 'darklunaris.vercel.app');
  final _portController = TextEditingController(text: '443');
  String _output = '';
  bool _running = false;

  Future<void> _runCert() async {
    setState(() {
      _running = true;
      _output = 'Inspecting TLS...';
    });
    try {
      final host = _hostController.text.trim();
      final port = int.tryParse(_portController.text.trim()) ?? 443;
      final cert = await sc.inspectTlsCertificate(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      final file = File('docs/examples/cert_gui.json');
      await file.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(cert ?? {}),
      );
      if (!mounted) return;
      setState(() {
        _output = const JsonEncoder.withIndent('  ').convert(cert ?? {});
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
                child: Column(
                  children: [
                    TextField(
                      controller: _hostController,
                      decoration: const InputDecoration(labelText: 'Host'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _portController,
                      decoration: const InputDecoration(labelText: 'Port'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _running ? null : _runCert,
                      child: const Text('Inspect Cert'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(child: SelectableText(_output)),
              ),
            ],
          ),
        );
      },
    );
  }
}
