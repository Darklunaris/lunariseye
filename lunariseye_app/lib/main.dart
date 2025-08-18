import 'dart:ui';
import 'package:flutter/material.dart';
import 'screens/web_check.dart';
import 'screens/scan.dart';
import 'screens/settings.dart';
import 'screens/profiles.dart';
import 'screens/analyze.dart';
import 'screens/cert.dart';
import 'screens/dns.dart';
import 'screens/port_check.dart';
import 'state.dart' as sstate;
import 'bloc/app_bloc.dart';
import 'bloc/app_event.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'widgets/glass_container.dart';

void main() {
  runApp(const LunarisEyeApp());
}

class LunarisEyeApp extends StatelessWidget {
  const LunarisEyeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AppBloc()..add(LoadAppEvent()),
      child: MaterialApp(
        title: 'LunarisEye GUI',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.dark(
            primary: const Color.fromARGB(24, 255, 255, 255),
          ),
          appBarTheme: const AppBarTheme(centerTitle: true, elevation: 2),
          textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: Colors.white,
            displayColor: Colors.white,
          ),
          scaffoldBackgroundColor: Colors.transparent,
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

/// Small animated moving glass bar used behind the AppBar for a lively glass effect.
class _MovingGlassBar extends StatefulWidget {
  @override
  State<_MovingGlassBar> createState() => __MovingGlassBarState();
}

class __MovingGlassBarState extends State<_MovingGlassBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctr;

  @override
  void initState() {
    super.initState();
    _ctr = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _ctr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctr,
      builder: (context, child) {
        final t = _ctr.value;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * t, -1.0),
              end: Alignment(1.0 - 2.0 * t, 1.0),
              colors: [
                const Color.fromARGB(32, 255, 255, 255),
                const Color.fromARGB(8, 255, 255, 255),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Widget that paints the shared background image for app pages.
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/fxc.png', fit: BoxFit.cover),
        Container(color: const Color.fromARGB(115, 0, 0, 0)),
        child,
      ],
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Simulate initialization (load state, warm up scanner)
    Future.delayed(const Duration(milliseconds: 900), () async {
      // proceed to home
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.asset('assets/sp.png', fit: BoxFit.cover),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color.fromARGB(102, 0, 0, 0),
                  const Color.fromARGB(153, 0, 0, 0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.remove_red_eye, size: 64, color: Colors.white70),
                SizedBox(height: 12),
                Text(
                  'LunarisEye',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Network reconnaissance toolkit',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<sstate.AppState> _stateFuture;
  Widget _current = const WebCheckScreen();

  @override
  void initState() {
    super.initState();
    _stateFuture = sstate.AppState.load();
  }

  void _open(Widget w) {
    setState(() => _current = w);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<sstate.AppState>(
      future: _stateFuture,
      builder: (context, snap) {
        final st = snap.data;
        return AppBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: const Text('LunarisEye GUI'),
              flexibleSpace: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                  child: _MovingGlassBar(),
                ),
              ),
            ),
            drawer: Drawer(
              child: GlassContainer(
                padding: EdgeInsets.zero,
                borderRadius: 0,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    DrawerHeader(
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(20, 44, 44, 44),
                      ),
                      child: const Text(
                        'LunarisEye',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ),
                    ListTile(
                      title: const Text('Web Check'),
                      leading: const Icon(Icons.web, color: Colors.white),
                      onTap: () => _open(const WebCheckScreen()),
                    ),
                    ListTile(
                      title: const Text('Scan'),
                      leading: const Icon(Icons.dns, color: Colors.white),
                      onTap: () => _open(const ScanScreen()),
                    ),
                    ListTile(
                      title: const Text('Port Check'),
                      leading: const Icon(
                        Icons.portable_wifi_off,
                        color: Colors.white,
                      ),
                      onTap: () => _open(const PortCheckScreen()),
                    ),
                    ListTile(
                      title: const Text('Analyze'),
                      leading: const Icon(Icons.search, color: Colors.white),
                      onTap: () => _open(const AnalyzeScreen()),
                    ),
                    ListTile(
                      title: const Text('Cert'),
                      leading: const Icon(Icons.security, color: Colors.white),
                      onTap: () => _open(const CertScreen()),
                    ),
                    ListTile(
                      title: const Text('DNS'),
                      leading: const Icon(Icons.cloud, color: Colors.white),
                      onTap: () => _open(const DnsScreen()),
                    ),
                    const Divider(),
                    if (st != null)
                      ListTile(
                        title: const Text('Profiles'),
                        leading: const Icon(Icons.person, color: Colors.white),
                        onTap: () => _open(ProfilesScreen(state: st)),
                      ),
                    if (st != null)
                      ListTile(
                        title: const Text('Settings'),
                        leading: const Icon(
                          Icons.settings,
                          color: Colors.white,
                        ),
                        onTap: () => _open(SettingsScreen(state: st)),
                      ),
                  ],
                ),
              ),
            ),
            body: _current,
          ),
        );
      },
    );
  }
}
