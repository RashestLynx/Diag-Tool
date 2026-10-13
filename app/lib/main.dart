import 'package:flutter/material.dart';

import 'controller/controller_screen.dart';
import 'knowledge.dart';
import 'recovery/recovery.dart';
import 'recovery/recovery_screen.dart';
import 'reference/reference.dart';
import 'screens/diagnose_screen.dart';
import 'screens/identify_screen.dart';
import 'screens/scan_screen.dart';
import 'theme.dart';

void main() {
  runApp(const DiagToolApp());
}

class DiagToolApp extends StatelessWidget {
  const DiagToolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Diag-Tool',
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      home: const _Home(),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  late final Future<(Knowledge, Recovery, Reference)> _data =
      Future.wait([Knowledge.load(), Recovery.load(), Reference.load()])
          .then((r) => (r[0] as Knowledge, r[1] as Recovery, r[2] as Reference));
  int _tab = 0;

  static const _titles = ['Scan', 'Diagnose', 'Controller', 'Recovery', 'Identify'];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(Knowledge, Recovery, Reference)>(
      future: _data,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Diag-Tool')),
            body: Center(child: Text('Failed to load: ${snap.error}')),
          );
        }
        final (knowledge, recovery, reference) = snap.data!;
        final screens = [
          ScanScreen(knowledge: knowledge, reference: reference),
          DiagnoseScreen(knowledge: knowledge, reference: reference),
          const ControllerScreen(),
          RecoveryScreen(recovery: recovery),
          IdentifyScreen(reference: reference),
        ];

        // Phones get a bottom bar; wider screens (tablet/desktop) get a rail.
        final wide = MediaQuery.sizeOf(context).width >= 700;
        return Scaffold(
          appBar: AppBar(
            title: Text('Diag-Tool  ·  ${_titles[_tab]}'),
            centerTitle: false,
          ),
          body: Row(
            children: [
              if (wide)
                NavigationRail(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                        icon: Icon(Icons.health_and_safety_outlined),
                        selectedIcon: Icon(Icons.health_and_safety),
                        label: Text('Scan')),
                    NavigationRailDestination(
                        icon: Icon(Icons.healing_outlined),
                        selectedIcon: Icon(Icons.healing),
                        label: Text('Diagnose')),
                    NavigationRailDestination(
                        icon: Icon(Icons.sports_esports_outlined),
                        selectedIcon: Icon(Icons.sports_esports),
                        label: Text('Controller')),
                    NavigationRailDestination(
                        icon: Icon(Icons.lock_reset_outlined),
                        selectedIcon: Icon(Icons.lock_reset),
                        label: Text('Recovery')),
                    NavigationRailDestination(
                        icon: Icon(Icons.badge_outlined),
                        selectedIcon: Icon(Icons.badge),
                        label: Text('Identify')),
                  ],
                ),
              if (wide) const VerticalDivider(width: 1),
              Expanded(child: SafeArea(child: screens[_tab])),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  destinations: const [
                    NavigationDestination(
                        icon: Icon(Icons.health_and_safety_outlined),
                        selectedIcon: Icon(Icons.health_and_safety),
                        label: 'Scan'),
                    NavigationDestination(
                        icon: Icon(Icons.healing_outlined),
                        selectedIcon: Icon(Icons.healing),
                        label: 'Diagnose'),
                    NavigationDestination(
                        icon: Icon(Icons.sports_esports_outlined),
                        selectedIcon: Icon(Icons.sports_esports),
                        label: 'Controller'),
                    NavigationDestination(
                        icon: Icon(Icons.lock_reset_outlined),
                        selectedIcon: Icon(Icons.lock_reset),
                        label: 'Recovery'),
                    NavigationDestination(
                        icon: Icon(Icons.badge_outlined),
                        selectedIcon: Icon(Icons.badge),
                        label: 'Identify'),
                  ],
                ),
        );
      },
    );
  }
}
