import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/app_bloc.dart';
import '../bloc/app_state.dart';
import '../widgets/glass_container.dart';

class AnalyzeScreen extends StatefulWidget {
  const AnalyzeScreen({super.key});

  @override
  State<AnalyzeScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends State<AnalyzeScreen> {
  final _urlController = TextEditingController();
  String _output = '';
  bool _running = false;

  Future<void> _runAnalyze() async {
    setState(() {
      _running = true;
      _output = 'Running analyze...';
    });
    try {
      final uri = Uri.parse(_urlController.text.trim());
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
      final result = {
        'url': uri.toString(),
        'status': resp.statusCode,
        'title': title,
        'responseTimeMs': sw.elapsedMilliseconds,
        'server': resp.headers.value('server'),
      };
      final file = File('docs/examples/analyze_gui.json');
      await file.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(result),
      );
      if (!mounted) return;
      setState(() {
        _output = const JsonEncoder.withIndent('  ').convert(result);
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
                      controller: _urlController,
                      decoration: const InputDecoration(labelText: 'URL'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _running ? null : _runAnalyze,
                      child: const Text('Run Analyze'),
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
