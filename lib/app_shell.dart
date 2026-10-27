import 'package:flutter/material.dart';

import 'screens/activity_screen.dart';
import 'screens/add_alerts_screen.dart';
import 'screens/ask_screen.dart';
import 'screens/home_screen.dart';

/// Responsive frame for phone, tablet and web.
/// Narrow: bottom navigation + floating "Add alerts".
/// Wide (web, tablets): navigation rail with "Add alerts" on top, content centred.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  /// Lets any screen switch tabs (e.g. the getting-started guide).
  static final tab = ValueNotifier<int>(0);

  static Future<void> openAddAlerts(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const AddAlertsScreen()));

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _destinations = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Activity'),
    (Icons.chat_bubble_outline, Icons.chat_bubble, 'Ask'),
  ];

  final _pages = const [HomeScreen(), ActivityScreen(), AskScreen()];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppShell.tab,
      builder: (context, index, _) {
        final wide = MediaQuery.sizeOf(context).width >= 760;
        final body = IndexedStack(index: index, children: _pages);

        if (wide) {
          return Scaffold(
            body: SafeArea(
              child: Row(children: [
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: (i) => AppShell.tab.value = i,
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    child: FloatingActionButton(
                      elevation: 0,
                      tooltip: 'Add alerts',
                      onPressed: () => AppShell.openAddAlerts(context),
                      child: const Icon(Icons.add),
                    ),
                  ),
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: body),
                  ),
                ),
              ]),
            ),
          );
        }

        return Scaffold(
          body: body,
          floatingActionButton: index == 2
              ? null // Ask has its own input at the bottom
              : FloatingActionButton.extended(
                  onPressed: () => AppShell.openAddAlerts(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add alerts'),
                ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => AppShell.tab.value = i,
            destinations: [
              for (final d in _destinations) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
            ],
          ),
        );
      },
    );
  }
}
