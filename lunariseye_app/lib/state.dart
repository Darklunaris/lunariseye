import 'dart:convert';
import 'dart:io';

class AppState {
  bool allowExternal;
  List<Map<String, dynamic>> profiles;

  AppState({required this.allowExternal, required this.profiles});

  static Future<AppState> load() async {
    final f = File('.app_state.json');
    if (!await f.exists()) {
      return AppState(allowExternal: false, profiles: []);
    }
    try {
      final s = await f.readAsString();
      final m = jsonDecode(s) as Map<String, dynamic>;
      return AppState(
        allowExternal: m['allowExternal'] == true,
        profiles: List<Map<String, dynamic>>.from(m['profiles'] ?? []),
      );
    } catch (_) {
      return AppState(allowExternal: false, profiles: []);
    }
  }

  Future<void> save() async {
    final f = File('.app_state.json');
    final m = {'allowExternal': allowExternal, 'profiles': profiles};
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(m));
  }
}
