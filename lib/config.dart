import 'dart:io';
import 'dart:convert';

class ToolProfile {
  String name;
  String cidr;
  String ports; // comma-separated
  int concurrency;

  ToolProfile({
    required this.name,
    required this.cidr,
    required this.ports,
    this.concurrency = 100,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'cidr': cidr,
    'ports': ports,
    'concurrency': concurrency,
  };

  static ToolProfile fromJson(Map<String, dynamic> j) => ToolProfile(
    name: j['name'] as String,
    cidr: j['cidr'] as String,
    ports: j['ports'] as String,
    concurrency: (j['concurrency'] ?? 100) as int,
  );
}

class ToolConfig {
  final Directory dir;
  final File file;
  Map<String, ToolProfile> profiles = {};
  Map<String, dynamic>? lastResults;

  ToolConfig._(this.dir, this.file);

  static Future<ToolConfig> load() async {
    final env = Platform.environment['lunariseye_CONFIG_DIR'];
    final home = env ?? '${Platform.environment['HOME'] ?? '.'}/.lunariseye';
    final dir = Directory(home);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('${dir.path}/config.json');
    final cfg = ToolConfig._(dir, file);
    if (file.existsSync()) {
      try {
        final text = await file.readAsString();
        final json = jsonDecode(text) as Map<String, dynamic>;
        if (json.containsKey('profiles')) {
          final p = json['profiles'] as Map<String, dynamic>;
          p.forEach((k, v) {
            cfg.profiles[k] = ToolProfile.fromJson(v as Map<String, dynamic>);
          });
        }
        if (json.containsKey('lastResults')) {
          cfg.lastResults = json['lastResults'];
        }
      } catch (_) {
        // ignore parse errors; start fresh
      }
    }
    return cfg;
  }

  Future<void> save() async {
    final json = <String, dynamic>{};
    final p = <String, dynamic>{};
    profiles.forEach((k, v) => p[k] = v.toJson());
    json['profiles'] = p;
    if (lastResults != null) json['lastResults'] = lastResults;
    await file.writeAsString(JsonEncoder.withIndent('  ').convert(json));
  }

  void setLastResults(Map<String, dynamic> r) {
    lastResults = r;
  }
}
