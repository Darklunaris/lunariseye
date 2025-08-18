import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/app_bloc.dart';
import '../bloc/app_state.dart';
import '../widgets/glass_container.dart';
import '../state.dart';

class ProfilesScreen extends StatefulWidget {
  final AppState state;
  const ProfilesScreen({required this.state, super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
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
                    ElevatedButton(
                      onPressed: () async {
                        // create a basic profile dialog
                        final nameC = TextEditingController();
                        final cidrC = TextEditingController();
                        final portsC = TextEditingController();
                        final res = await showDialog<Map<String, String>>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Create profile'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextField(
                                  controller: nameC,
                                  decoration: const InputDecoration(
                                    labelText: 'Name',
                                  ),
                                ),
                                TextField(
                                  controller: cidrC,
                                  decoration: const InputDecoration(
                                    labelText: 'CIDR',
                                  ),
                                ),
                                TextField(
                                  controller: portsC,
                                  decoration: const InputDecoration(
                                    labelText: 'Ports (comma)',
                                  ),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, {
                                  'name': nameC.text,
                                  'cidr': cidrC.text,
                                  'ports': portsC.text,
                                }),
                                child: const Text('Save'),
                              ),
                            ],
                          ),
                        );
                        if (res != null) {
                          widget.state.profiles.add({
                            'name': res['name'] ?? '',
                            'cidr': res['cidr'] ?? '',
                            'ports': res['ports'] ?? '',
                          });
                          await widget.state.save();
                          setState(() {});
                        }
                      },
                      child: const Text('Create Profile'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.state.profiles.length,
                  itemBuilder: (c, i) {
                    final p = widget.state.profiles[i];
                    return ListTile(
                      title: Text(p['name'] ?? ''),
                      subtitle: Text('CIDR: ${p['cidr']} ports: ${p['ports']}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_forever),
                        onPressed: () async {
                          widget.state.profiles.removeAt(i);
                          await widget.state.save();
                          setState(() {});
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
