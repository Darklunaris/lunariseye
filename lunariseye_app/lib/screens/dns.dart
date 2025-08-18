import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/app_bloc.dart';
import '../bloc/app_state.dart';
import '../widgets/glass_container.dart';

class DnsScreen extends StatefulWidget {
  const DnsScreen({super.key});

  @override
  State<DnsScreen> createState() => _DnsScreenState();
}

class _DnsScreenState extends State<DnsScreen> {
  final _nameController = TextEditingController(text: 'darklunaris.vercel.app');
  String _output = '';
  bool _running = false;

  Future<void> _runDns() async {
    setState(() {
      _running = true;
      _output = 'Resolving...';
    });
    try {
      final name = _nameController.text.trim();
      final addrs = await InternetAddress.lookup(name);
      final out = addrs.map((a) => a.address).toList();
      final file = File('docs/examples/dns_gui.json');
      await file.create(recursive: true);
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
      if (!mounted) return;
      setState(() {
        _output = const JsonEncoder.withIndent('  ').convert(out);
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
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _running ? null : _runDns,
                      child: const Text('Resolve'),
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
