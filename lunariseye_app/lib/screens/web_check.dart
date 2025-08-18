import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/app_bloc.dart';
import '../bloc/app_state.dart';
import '../widgets/glass_container.dart';

class WebCheckScreen extends StatefulWidget {
  const WebCheckScreen({super.key});

  @override
  State<WebCheckScreen> createState() => _WebCheckScreenState();
}

class _WebCheckScreenState extends State<WebCheckScreen> {
  final _urlController = TextEditingController(
    text: 'https://darklunaris.vercel.app',
  );
  String _output = '';
  bool _running = false;

  Future<void> _runCheck() async {
    setState(() {
      _running = true;
      _output = 'Running web check...';
    });
    try {
      final uri = Uri.parse(_urlController.text);
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

      final result = <String, dynamic>{
        'url': uri.toString(),
        'status': resp.statusCode,
        'title': title,
        'responseTimeMs': sw.elapsedMilliseconds,
        'server': resp.headers.value('server'),
        'contentLength': resp.headers.contentLength,
      };

      final file = File('docs/examples/webcheck_gui.json');
      await file.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(result),
      );

      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _output = const JsonEncoder.withIndent('  ').convert(result);
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
                  children: [
                    TextField(
                      controller: _urlController,
                      decoration: const InputDecoration(labelText: 'URL'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: _running ? null : _runCheck,
                          child: _running
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Run Web Check'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () async {
                            final file = File(
                              'docs/examples/webcheck_gui.json',
                            );
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
                          child: const Text('Show Export'),
                        ),
                      ],
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
