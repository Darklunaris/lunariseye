import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/app_bloc.dart';
import '../bloc/app_state.dart';
import '../widgets/glass_container.dart';
import '../state.dart';

class SettingsScreen extends StatefulWidget {
  final AppState state;
  const SettingsScreen({required this.state, super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool allowExternal;

  @override
  void initState() {
    super.initState();
    allowExternal = widget.state.allowExternal;
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
                    SwitchListTile(
                      title: const Text('Allow external scans (warning only)'),
                      subtitle: const Text(
                        'Enable scanning of non-private IP ranges after explicit consent',
                      ),
                      value: allowExternal,
                      onChanged: (v) => setState(() => allowExternal = v),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        widget.state.allowExternal = allowExternal;
                        await widget.state.save();
                        if (!mounted) return;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Settings saved')),
                          );
                        });
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
